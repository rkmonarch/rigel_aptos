/// Pool Router has similar interfaces as aptos_framework::delegation_pool
/// because it is used as a proxy to underlying delegation pools without exposing them to the outside world.
/// These interfaces are used by thala_lsd::staking to stake, unstake and withdraw, including:
/// - add_stake: add stake to an underlying pool.
/// - unlock: unlock from underlying pools, and withdraw inactive stakes from them as a possible side effect.
/// - withdraw: withdraw inactive stakes from all underlying pools.
module thala_lsd::pool_router {
    use std::vector;

    use aptos_std::math64;
    use aptos_std::simple_map::{Self, SimpleMap};
    use aptos_framework::aptos_coin::AptosCoin;
    use aptos_framework::coin;
    use aptos_framework::delegation_pool;

    use thala_lsd::package;
    // use thala_manager::manager;

    friend thala_lsd::staking;

    // Error Codes

    const ERR_TLSD_POOL_ROUTER_UNINITIALIZED: u64 = 0;
    const ERR_TLSD_POOL_ROUTER_UNAUTHORIZED: u64 = 1;
    const ERR_TLSD_POOL_ROUTER_POOL_EXISTS: u64 = 2;
    const ERR_TLSD_POOL_ROUTER_POOL_INVALID: u64 = 3;
    const ERR_TLSD_POOL_ROUTER_TARGET_UTILIZATION_INVALID: u64 = 4;
    const ERR_TLSD_POOL_ROUTER_INTERNAL_ERROR: u64 = 5;
    const ERR_TLSD_POOL_ROUTER_UNLOCK_AMOUNT_TOO_LARGE: u64 = 6;

    // Constants

    const BPS_BASE: u64 = 10000;
    const MAX_U64: u64 = 18446744073709551615;

    // Resources

    struct PoolRouter has key {
        /// delegation pool address -> target_utilization_bps
        target_utilization: SimpleMap<address, u64>,
    }

    // Functions

    fun init_module(account: &signer) {
        move_to(account, PoolRouter {
            target_utilization: simple_map::new(),
        });
    }

    /// Add a new pool to the router.
    /// If this is the first pool, set the target utilization to 10000 since we want to make sure they sum up to 10000;
    /// Otherwise, leave the target utilization as 0.
    public entry fun add_pool(manager: &signer, new_pool: address) acquires PoolRouter {
        // assert!(manager::is_authorized(manager), ERR_TLSD_POOL_ROUTER_UNAUTHORIZED);

        let pool_router = borrow_global_mut<PoolRouter>(package::resource_account_address());
        assert!(!simple_map::contains_key(&pool_router.target_utilization, &new_pool), ERR_TLSD_POOL_ROUTER_POOL_EXISTS);
        assert!(delegation_pool::delegation_pool_exists(new_pool), ERR_TLSD_POOL_ROUTER_POOL_INVALID);

        if (simple_map::length(&pool_router.target_utilization) == 0) {
            simple_map::add(&mut pool_router.target_utilization, new_pool, BPS_BASE);
        } else {
            simple_map::add(&mut pool_router.target_utilization, new_pool, 0);
        }
    }

    /// Set target utilization for all pools.
    /// It checks the input so that:
    /// 1. the input pools are the same as the existing ones.
    /// 2. the input target utilization sums up to 10000.
    public entry fun set_target_utilization(manager: &signer, pools: vector<address>, target_utilization: vector<u64>) acquires PoolRouter {
        // assert!(manager::is_authorized(manager), ERR_TLSD_POOL_ROUTER_UNAUTHORIZED);

        let total_utilization = vector::fold(target_utilization, 0, |acc, e| acc + e);
        assert!(total_utilization == BPS_BASE, ERR_TLSD_POOL_ROUTER_TARGET_UTILIZATION_INVALID);

        let new_target_utilization = simple_map::new_from(pools, target_utilization);

        let pool_router = borrow_global_mut<PoolRouter>(package::resource_account_address());
        assert!(simple_map::length(&pool_router.target_utilization) == simple_map::length(&new_target_utilization), ERR_TLSD_POOL_ROUTER_POOL_INVALID);

        // now that we're certain that pools are deduped
        // dev: do NOT use vector::all since that causes runtime error UNKNOWN_INVARIANT_VIOLATION_ERROR.
        vector::for_each(pools, |pool| {
            assert!(simple_map::contains_key(&pool_router.target_utilization, &pool), ERR_TLSD_POOL_ROUTER_POOL_INVALID);
        });

        pool_router.target_utilization = new_target_utilization;
    }

    /// Find the most underutilized pool and stake to it.
    /// Returns (pool_address, actual_staked).
    /// By underutilized we mean the actual utilization is less than the target utilization.
    public(friend) fun add_stake(amount: u64): (address, u64) acquires PoolRouter {
        let resource_account_signer = package::resource_account_signer();
        let resource_account_address = package::resource_account_address();

        // stake to the underutilized pool
        let most_underutilized_pool = get_most_underutilized_pool();
        let (active_before, _, _) = delegation_pool::get_stake(most_underutilized_pool, resource_account_address);
        delegation_pool::add_stake(&resource_account_signer, most_underutilized_pool, amount);
        let (active_after, _, _) = delegation_pool::get_stake(most_underutilized_pool, resource_account_address);

        (most_underutilized_pool, active_after - active_before)
    }

    /// Unlock from underlying pools, and withdraw inactive stakes from them as a possible side effect,
    /// and return (active decrement, pending inactive increment, withdrawn amount).
    /// The reason why we compute both active decrement and pending inactive increment is that
    /// due to the coins-to-shares conversion in delegation_pool module, it is possible that
    /// active decrement >= pending inactive increment, and we cannot simply just use 1 variable
    /// to represent the 2.
    /// Now that we can differentiate between active decrement and pending inactive increment,
    /// we use them for separate purpose:
    /// - active decrement is used to compare with target_amount to determine the unlock progress.
    /// - pending inactive increment is used to determine (combining the request_amount) how much
    ///   the unstaker should be able to unstake from the pool.
    /// In terms of "which pool to unlock from", we want to unlock from overutilized pools first,
    /// then underutilized pools if necessary.
    public(friend) fun unlock(target_amount: u64): (u64, u64, u64) acquires PoolRouter {
        let resource_account_signer = package::resource_account_signer();
        let resource_account_address = package::resource_account_address();

        // get active stakes
        let router = borrow_global<PoolRouter>(resource_account_address);
        let pools = simple_map::keys(&router.target_utilization);
        let active_coins = vector::map(pools, |pool_addr| {
            let (active, _, _) = delegation_pool::get_stake(pool_addr, resource_account_address);
            active
        });
        let active_coins_by_pool = simple_map::new_from(pools, active_coins);
        let total_coins = vector::fold(active_coins, 0, |acc, a| acc + a);
        assert!(target_amount <= total_coins, ERR_TLSD_POOL_ROUTER_UNLOCK_AMOUNT_TOO_LARGE);

        // it is possible that we need to unlock from all pools if the amount equals to current active stake.
        // therefore, we want to go through overutilized pools first, then underutilized pools if necessary.
        // that's why we partition pools so that overutilized pools are at the head, and underutilized ones
        // are at the tail.
        vector::partition(&mut pools, |pool| {
            let active = *simple_map::borrow(&active_coins_by_pool, pool);
            let target_utilization_bps = *simple_map::borrow(&router.target_utilization, pool);
            let actual_utilization_bps = math64::mul_div(active, BPS_BASE, total_coins);
            actual_utilization_bps >= target_utilization_bps
        });

        // keep track of withdrawn amount since unlock may withdraw from inactive via execute_pending_withdrawal.
        let balance_before = coin::balance<AptosCoin>(resource_account_address);
        let active_decrement = 0;
        let pending_inactive_increment = 0;
        let i = 0;
        let len = vector::length(&pools);
        // the reason why we stop the loop when active_decrement + 1 >= target_amount is that
        // due to the coins-to-shares conversion in delegation_pool::unlock, it is possible that
        // delegation_pool::unlock(10000000000) only changes active stake by 9999999999.
        // if we continue with the loop, we will run delegation_pool::unlock(1) against the next pool, that may only
        // change active stake by 0. so the loop continues and we will never reach target_amount despite wasting gas.
        // therefore we stop the loop when active_decrement + 1 >= target_amount.
        while (i < len && active_decrement + 1 < target_amount) {
            let pool = *vector::borrow(&pools, i);
            let (active_before, _, pending_inactive_before) = delegation_pool::get_stake(pool, resource_account_address);
            let amount = math64::min(target_amount - active_decrement, active_before);
            delegation_pool::unlock(&resource_account_signer, pool, amount);
            let (active_after, _, pending_inactive_after) = delegation_pool::get_stake(pool, resource_account_address);
            active_decrement = active_decrement + active_before - active_after;
            pending_inactive_increment = pending_inactive_increment + pending_inactive_after - pending_inactive_before;
            i = i + 1;
        };
        let balance_after = coin::balance<AptosCoin>(resource_account_address);

        (active_decrement, pending_inactive_increment, balance_after - balance_before)
    }

    /// Withdraw inactive stakes from all underlying pools, and return withdrawn amount.
    public(friend) fun withdraw(): u64 acquires PoolRouter {
        let resource_account_signer = package::resource_account_signer();
        let resource_account_address = package::resource_account_address();

        let balance_before = coin::balance<AptosCoin>(resource_account_address);
        vector::for_each(get_pools(), |pool| {
            delegation_pool::withdraw(&resource_account_signer, pool, MAX_U64);
        });
        let balance_after = coin::balance<AptosCoin>(resource_account_address);
        balance_after - balance_before
    }

    #[view]
    /// Return addresses of all underlying pools
    public fun get_pools(): vector<address> acquires PoolRouter {
        let router = borrow_global<PoolRouter>(package::resource_account_address());
        simple_map::keys(&router.target_utilization)
    }


    #[view]
    /// Return target utilization of all underlying pools
    public fun get_pools_target_utilization(): (vector<address>, vector<u64>) acquires PoolRouter {
        let router = borrow_global<PoolRouter>(package::resource_account_address());
        simple_map::to_vec_pair(router.target_utilization)
    }

    #[view]
    /// Return actual utilization of all underlying pools
    public fun get_pools_actual_utilization(): (vector<address>, vector<u64>) acquires PoolRouter {
        let pools = get_pools();
        let active_coins = vector::map(pools, |pool_addr| {
            let (active, _, _) = delegation_pool::get_stake(pool_addr, package::resource_account_address());
            active
        });
        let total_coins = vector::fold(active_coins, 0, |acc, a| acc + a);
        let utilization = if (total_coins == 0) {
            let i = 0;
            let len = vector::length(&pools);
            let v = vector::empty<u64>();
            while (i < len) {
                vector::push_back(&mut v, 0);
                i = i + 1;
            };
            v
        } else {
            vector::map(active_coins, |active| math64::mul_div(active, BPS_BASE, total_coins))
        };
        (pools, utilization)
    }

    #[view]
    /// Return active, inactive and pending_inactive stakes of all underlying pools
    public fun get_stakes(): (vector<u64>, vector<u64>, vector<u64>) acquires PoolRouter {
        let active = vector::empty<u64>();
        let inactive = vector::empty<u64>();
        let pending_inactive = vector::empty<u64>();

        vector::for_each(get_pools(), |pool| {
            let (pool_active, pool_inactive, pool_pending_inactive) = delegation_pool::get_stake(pool, package::resource_account_address());
            vector::push_back(&mut active, pool_active);
            vector::push_back(&mut inactive, pool_inactive);
            vector::push_back(&mut pending_inactive, pool_pending_inactive);
        });

        (active, inactive, pending_inactive)
    }

    #[view]
    /// Return active, inactive and pending_inactive stakes summed up
    public fun get_total_stakes(): (u128, u128, u128) acquires PoolRouter {
        let (active, inactive, pending_inactive) = get_stakes();
        (
            vector::fold(active, 0u128, |acc, e| acc + (e as u128)),
            vector::fold(inactive, 0u128, |acc, e| acc + (e as u128)),
            vector::fold(pending_inactive, 0u128, |acc, e| acc + (e as u128)),
        )
    }

    #[view]
    /// Get add_stake_fee for the incoming add_stake call.
    public fun get_add_stake_fee(amount: u64): u64 acquires PoolRouter {
        let pool = get_most_underutilized_pool();
        delegation_pool::get_add_stake_fee(pool, amount)
    }

    #[view]
    /// Get the most underutilized pool which has the most difference from its target utilization.
    /// Based on our stake allocation strategy, the next add_stake call will be to this pool.
    public fun get_most_underutilized_pool(): address acquires PoolRouter {
        // get active stakes
        let (pools, target_utilization) = get_pools_target_utilization();
        let active_coins = vector::map(pools, |pool_addr| {
            let (active, _, _) = delegation_pool::get_stake(pool_addr, package::resource_account_address());
            active
        });
        let total_coins = vector::fold(active_coins, 0, |acc, a| acc + a);

        // find the underutlizied pool which has the most difference from its target utilization
        let most_underutilized_pool_index = {
            let len = vector::length(&pools);
            let (i, idx, max_diff) = (0, len, 0);
            while (i < len) {
                let target_utilization_bps = *vector::borrow(&target_utilization, i);
                let actual_utilization_bps = if (total_coins == 0) 0 else math64::mul_div(*vector::borrow(&active_coins, i), BPS_BASE, total_coins);
                if (actual_utilization_bps + max_diff <= target_utilization_bps) {
                    max_diff = target_utilization_bps - actual_utilization_bps;
                    idx = i;
                };
                i = i + 1;
            };
            // idx should always be valid, if not, it's an internal logic error.
            assert!(idx < len, ERR_TLSD_POOL_ROUTER_INTERNAL_ERROR);
            idx
        };

        *vector::borrow(&pools, most_underutilized_pool_index)
    }

    #[test_only]
    public fun init_module_for_test() {
        init_module(&package::resource_account_signer());
    }

    #[test_only]
    public fun add_stake_for_test(amount: u64): address acquires PoolRouter {
        let (pool, _) = add_stake(amount);
        pool
    }

    #[test_only]
    public fun unlock_for_test(amount: u64): (u64, u64, u64) acquires PoolRouter {
        unlock(amount)
    }

    #[test_only]
    public fun withdraw_for_test(): u64 acquires PoolRouter {
        withdraw()
    }
}