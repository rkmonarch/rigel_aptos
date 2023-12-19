/// Thala Liquid Staking Derivatives (TLSD)
/// is a liquid staking derivates protocol built on top of Aptos Delegated Staking.
/// It leverages dual-token model (thAPT and sthAPT) inspired by Frax Ether
/// with the focus of getting higher yield for stakers compared to staking directly with delegation pools.
module thala_lsd::staking {
    use std::option;
    use std::signer;
    use std::string;
    use std::vector;

    use aptos_std::math64;
    use aptos_std::simple_map;
    use aptos_std::smart_table::{Self, SmartTable};
    use aptos_framework::aptos_coin::AptosCoin;
    use aptos_framework::coin::{Self, Coin, BurnCapability, FreezeCapability, MintCapability};
    use aptos_framework::event;
    use aptos_framework::timestamp;

    // use thala_manager::manager;
    use thala_lsd::package;
    use thala_lsd::pool_router;

    // Error Codes

    // Authorization
    const ERR_TLSD_UNAUTHORIZED: u64 = 0;

    // Others
    const ERR_TLSD_INVALID_BPS: u64 = 1;
    const ERR_TLSD_INVALID_COIN_AMOUNT: u64 = 2;
    const ERR_TLSD_USER_UNSTAKE_NOT_EXIST: u64 = 3;
    const ERR_TLSD_INVALID_REQUEST_ID: u64 = 4;
    const ERR_TLSD_UNSTAKE_REQUEST_NOT_COMPLETABLE: u64 = 5;


    // Defaults

    /// 30 days is a reasonable duration given it's the staking lockup cycle
    const DEFAULT_UNSTAKING_DURATION_SECONDS: u64 = 30 * 86400;

    // Constants

    const BPS_BASE: u64 = 10000;
    const FEE_MANAGER_ROLE: vector<u8> = b"fee_manager";

    // Resources

    /// Liquid staking APT that can be exchanged for APT at a 1:1 ratio.
    /// In order to redeem ThalaAPT for APT, user either:
    /// (1) calls request_unstake_APT followed by complete_unstake_APT.
    /// (2) exit through thAPT-APT pool in ThalaSwap.
    struct ThalaAPT {}

    /// Yield bearing coin that accrues Aptos staking rewards.
    /// Over time, 1 sthAPT can be exchanged for increasing amount of thAPT.
    struct StakedThalaAPT {}

    struct TLSD has key {
        // invariant: cumulative_restake + cumulative_deposit + cumulative_rewards = total_stake + cumulative_withdrawn (inflow = outflow).
        // we store cumulative_restake, cumulative_deposit, cumulative_withdrawn in contract, and calculate total_stake
        // through contract call to delegation_pool, then derive cumulative_rewards from the invariant
        // and store in contract as well.
        // NOTE: we use u128 for these counter variables since they're all cumulative and can grow very large.
        cumulative_restake: u128,
        cumulative_deposit: u128,
        cumulative_withdrawn: u128,
        cumulative_rewards: u128,

        /// Charged upon request_unstake_APT to encourage long-term staking
        unstake_APT_fee_bps: u64,

        /// Charged upon stake_thAPT to discourage mev between reward epochs
        stake_thAPT_fee_bps: u64,

        // Reward allocation mechanism
        // ----------------------------
        // Rewards generated from validator will be minted as thAPT and they have 3 destinations:
        // 1) commission_fee: retained by the protocol as fee.
        // 2) sthAPT_stakers: via added to thAPT_staking so that each sthAPT can be exchanged for more thAPT.
        // 3) rewards_kept: the rest are kept in the contract and later on distributed to thAPT-APT LPs.
        //
        // Imagine commission_fee_bps = 10%, extra_rewards_for_sthAPT_holders_bps = 75%,
        // thAPT_staking = 8_000_000, thAPT_supply = 10_000_000.
        // given 100 thAPT rewards:
        // - 10 thAPT goes to commission_fee.
        // - for the remaining 90 thAPT, 90*0.8+(90-90*0.8)*0.75 = 85.5 thAPT goes to thAPT_staking.
        //   note the 90*0.8 is pro rate rewards, and the (90-90*0.8)*0.75 is extra rewards.
        // - the remaining 4.5 thAPT goes to rewards_kept.

        commission_fee_bps: u64,
        commission_fee: Coin<ThalaAPT>,
        extra_rewards_for_sthAPT_holders_bps: u64,
        rewards_kept: Coin<ThalaAPT>,

        /// Staking thAPT comes from three sources:
        /// 1) thAPT staked in exchange for sthAPT.
        /// 2) A portion of thAPT minted upon sync_rewards.
        /// 3) Charged thAPT fees from redemption (request_unstake_APT) and stake (stake_thAPT).
        thAPT_staking: Coin<ThalaAPT>,

        /// When user requests to unstake APT, same amount of thAPT will be locked in the contract,
        /// in order to ensure that the user can't spend the thAPT elsewhere.
        /// After user completes unstake APT, same amount of thAPT will be burned.
        thAPT_unstaking: Coin<ThalaAPT>,

        /// A cache that sits between user and underlying delegation pools.
        /// It stores APT that comes from underlying pools upon `request_unstake_APT` and `complete_unstake_APT`.
        /// Whenever user tries to complete a unstake request, the cache will be used first.
        /// If APT in the cache is not enough to fulfill the request, the cache will be refilled from underlying pools
        /// via `withdraw` call.
        apt_pending_withdrawal: Coin<AptosCoin>,

        /// next unstake_request_id, incremented by 1 for each new request
        next_unstake_request_id: u64,

        /// Duration of unstaking period in seconds.
        /// This should be set the same as staking_config::StakingConfig::recurring_lockup_duration_secs
        /// in order to guarantee that after this period of wait, the user can unstake desired APT
        /// from the underlying pools, despite the fact that different pools have different lockup cycles.
        unstake_duration_seconds: u64,

        // thAPT capabilities
        thAPT_burn_capability: BurnCapability<ThalaAPT>,
        thAPT_freeze_capability: FreezeCapability<ThalaAPT>,
        thAPT_mint_capability: MintCapability<ThalaAPT>,

        // sthAPT capabilities
        sthAPT_burn_capability: BurnCapability<StakedThalaAPT>,
        sthAPT_freeze_capability: FreezeCapability<StakedThalaAPT>,
        sthAPT_mint_capability: MintCapability<StakedThalaAPT>,
    }

    /// User's unstake request
    struct UserUnstake has key {
        // unstake_request_id -> UnstakeRequest struct
        requests: SmartTable<u64, UnstakeRequest>,
    }

    struct UnstakeRequest has store, copy, drop {
        account: address,
        request_id: u64,
        start_sec: u64,
        end_sec: u64,
        /// Amount of APT that will be sent to requester after unstake request is completed.
        amount: u64
    }

    #[event]
    /// Event emitted when user stakes APT with TLSD
    struct StakeAPTEvent has drop, store {
        account: address,
        /// The underlying delegation pool
        pool: address,
        /// Amount of APT staked
        staked_APT: u64,
        /// Amount of thAPT minted
        minted_thAPT: u64,
    }

    #[event]
    /// Event emitted when user requests to unstake APT from TLSD
    struct RequestUnstakeAPTEvent has drop, store {
        /// The unstake request id
        request_id: u64,
        /// The account who requests to unstake APT
        account: address,
        /// Amount of APT requested to unstake
        request_amount: u64,
        /// Fee
        fee_amount: u64,
        /// Decrement in active stake due to the unlock operation against underlying pools
        active_decrement: u64,
        /// Increment in pending_inactive stake due to the unlock operation against underlying pools
        pending_inactive_increment: u64,
        /// Amount of APT withdrawn from underlying pools and saved to apt_pending_withdrawal
        withdrawn_amount: u64,
    }

    #[event]
    /// Event emitted when user completes the unstake request.
    struct CompleteUnstakeAPTEvent has drop, store {
        /// The unstake request id
        request_id: u64,
        /// The account who completes the unstake request
        account: address,
        /// Amount of APT unlocked for user, also the amount of thAPT burnt
        unlocked_amount: u64,
        /// Amount of APT withdrawn from underlying pools and saved to apt_pending_withdrawal
        withdrawn_amount: u64,
    }

    #[event]
    /// Event emitted when user restakes pending_inactive rewards
    struct RestakeAPTEvent has drop, store {
        /// The unstake request id
        request_id: u64,
        /// The pool that is restaked to
        pool: address,
        /// Amount of APT restaked
        restaked_APT: u64,
        /// Total restake increment
        cumulative_restake_increment: u64,
    }

    #[event]
    /// Event emitted when user stakes thAPT in exchange of sthAPT
    struct StakeThalaAPTEvent has drop, store {
        account: address,
        /// Amount of thAPT staked
        thAPT_staked: u64,
        /// Fee
        thAPT_fee: u64,
        /// Amount of sthAPT minted
        sthAPT_minted: u64,
    }

    #[event]
    /// Event emitted when user returns sthAPT and unstakes thAPT
    struct UnstakeThalaAPTEvent has drop, store {
        account: address,
        /// Amount of thAPT unstaked
        thAPT_unstaked: u64,
        /// Amount of sthAPT burned
        sthAPT_burnt: u64,
    }

    #[event]
    /// Event emitted whenever user interacts with LSD
    struct SyncRewardsEvent has drop, store {
        total_active: u128,
        total_inactive: u128,
        total_pending_inactive: u128,
        cumulative_restake: u128,
        cumulative_deposit: u128,
        cumulative_withdrawn: u128,
        prev_cumulative_rewards: u128,
        cumulative_rewards: u128,
        rewards_amount: u64,
        rewards_commission: u64,
        rewards_for_sthAPT_holders: u64,
        rewards_kept: u64,
    }

    // Initialization

    fun init_module(resource_account_signer: &signer) {
        // register APT since the resource account needs to store APT for delegation_pool interactions
        coin::register<AptosCoin>(resource_account_signer);

        let (thAPT_burn_capability, thAPT_freeze_capability, thAPT_mint_capability) = coin::initialize<ThalaAPT>(
            resource_account_signer,
            string::utf8(b"Thala APT"),
            string::utf8(b"thAPT"),
            8,
            true,
        );
        let (sthAPT_burn_capability, sthAPT_freeze_capability, sthAPT_mint_capability) = coin::initialize<StakedThalaAPT>(
            resource_account_signer,
            string::utf8(b"Staked Thala APT"),
            string::utf8(b"sthAPT"),
            8,
            true,
        );
        move_to(resource_account_signer, TLSD {
            cumulative_restake: 0,
            cumulative_deposit: 0,
            cumulative_rewards: 0,
            cumulative_withdrawn: 0,

            unstake_APT_fee_bps: 0,
            stake_thAPT_fee_bps: 0,
            commission_fee_bps: 0,
            commission_fee: coin::zero<ThalaAPT>(),
            // By default sthAPT holder reward ratio is 100%, but it can be changed later.
            extra_rewards_for_sthAPT_holders_bps: BPS_BASE,
            rewards_kept: coin::zero<ThalaAPT>(),

            thAPT_staking: coin::zero<ThalaAPT>(),
            thAPT_unstaking: coin::zero<ThalaAPT>(),
            apt_pending_withdrawal: coin::zero<AptosCoin>(),

            next_unstake_request_id: 0,
            unstake_duration_seconds: DEFAULT_UNSTAKING_DURATION_SECONDS,

            thAPT_burn_capability,
            thAPT_freeze_capability,
            thAPT_mint_capability,

            sthAPT_burn_capability,
            sthAPT_freeze_capability,
            sthAPT_mint_capability,
        });
    }

    // Config & Param Management

    public entry fun set_unstake_APT_fee_bps(manager: &signer, new_bps: u64) acquires TLSD {
        // assert!(manager::is_authorized(manager), ERR_TLSD_UNAUTHORIZED);
        assert!(new_bps <= BPS_BASE, ERR_TLSD_INVALID_BPS);

        let tlsd = borrow_global_mut<TLSD>(package::resource_account_address());
        tlsd.unstake_APT_fee_bps = new_bps;
    }

    public entry fun set_stake_thAPT_fee_bps(manager: &signer, new_bps: u64) acquires TLSD {
        // assert!(manager::is_authorized(manager), ERR_TLSD_UNAUTHORIZED);
        assert!(new_bps <= BPS_BASE, ERR_TLSD_INVALID_BPS);

        let tlsd = borrow_global_mut<TLSD>(package::resource_account_address());
        tlsd.stake_thAPT_fee_bps = new_bps;
    }

    public entry fun set_commission_fee_bps(manager: &signer, new_bps: u64) acquires TLSD {
        // assert!(manager::is_authorized(manager), ERR_TLSD_UNAUTHORIZED);
        assert!(new_bps <= BPS_BASE, ERR_TLSD_INVALID_BPS);

        let tlsd = borrow_global_mut<TLSD>(package::resource_account_address());
        tlsd.commission_fee_bps = new_bps;
    }

    public entry fun set_extra_rewards_for_sthAPT_holders_bps(manager: &signer, new_bps: u64) acquires TLSD {
        // assert!(manager::is_authorized(manager), ERR_TLSD_UNAUTHORIZED);
        assert!(new_bps <= BPS_BASE, ERR_TLSD_INVALID_BPS);

        let tlsd = borrow_global_mut<TLSD>(package::resource_account_address());
        tlsd.extra_rewards_for_sthAPT_holders_bps = new_bps;
    }

    public entry fun set_unstake_duration_seconds(manager: &signer, new_duration_seconds: u64) acquires TLSD {
        // assert!(manager::is_authorized(manager), ERR_TLSD_UNAUTHORIZED);

        let tlsd = borrow_global_mut<TLSD>(package::resource_account_address());
        tlsd.unstake_duration_seconds = new_duration_seconds;
    }

    public fun extract_commission_fee(account: &signer): Coin<ThalaAPT> acquires TLSD {
        // assert!(manager::is_role_member(signer::address_of(account), FEE_MANAGER_ROLE), ERR_TLSD_UNAUTHORIZED);
        let tlsd = borrow_global_mut<TLSD>(package::resource_account_address());
        coin::extract_all(&mut tlsd.commission_fee)
    }

    public fun extract_rewards_kept(account: &signer): Coin<ThalaAPT> acquires TLSD {
        // assert!(manager::is_role_member(signer::address_of(account), FEE_MANAGER_ROLE), ERR_TLSD_UNAUTHORIZED);
        let tlsd = borrow_global_mut<TLSD>(package::resource_account_address());
        coin::extract_all(&mut tlsd.rewards_kept)
    }

    // User operations

    /// Stake APT. Under the hood:
    /// 1) TLSD mints thAPT at a 1:1 ratio to staker.
    /// 2) TLSD stakes APT to delegation pools right away.
    public fun stake_APT(account: &signer, coin: Coin<AptosCoin>): Coin<ThalaAPT> acquires TLSD {
        let staked_APT = coin::value(&coin);
        assert!(staked_APT > 0, ERR_TLSD_INVALID_COIN_AMOUNT);

        sync_rewards();

        let resource_account_address = package::resource_account_address();

        // stake post fee APT to delegation pool
        let staked_APT = coin::value(&coin);
        coin::deposit(resource_account_address, coin);
        let (pool, actual_staked) = pool_router::add_stake(staked_APT);

        let tlsd = borrow_global_mut<TLSD>(resource_account_address);
        let thAPT_coin = coin::mint(actual_staked, &tlsd.thAPT_mint_capability);
        event::emit(StakeAPTEvent {
            account: signer::address_of(account),
            pool,
            staked_APT,
            minted_thAPT: actual_staked,
        });

        tlsd.cumulative_deposit = tlsd.cumulative_deposit + (actual_staked as u128);

        thAPT_coin
    }

    /// Request to unstake APT.
    /// The unstake request will be queued awaiting for triggered by `complete_unstake_APT`.
    public fun request_unstake_APT(account: &signer, coin: Coin<ThalaAPT>) acquires TLSD, UserUnstake {
        let request_amount = coin::value(&coin);
        assert!(request_amount > 0, ERR_TLSD_INVALID_COIN_AMOUNT);

        let account_addr = signer::address_of(account);
        let resource_account_signer = package::resource_account_signer();
        let resource_account_address = package::resource_account_address();

        sync_rewards();

        // charge fee
        let tlsd = borrow_global_mut<TLSD>(resource_account_address);
        let fee_amount = math64::mul_div(request_amount, tlsd.unstake_APT_fee_bps, BPS_BASE);
        let fee = coin::extract(&mut coin, fee_amount);
        coin::merge(&mut tlsd.thAPT_staking, fee);

        // unlock
        let request_amount_post_fee = request_amount - fee_amount;
        let (active_decrement, pending_inactive_increment, withdrawn_amount) = pool_router::unlock(request_amount_post_fee);

        // withdrawn_amount is the side effect of unlock, learn more details at pool_router::unlock
        coin::merge(&mut tlsd.apt_pending_withdrawal, coin::withdraw<AptosCoin>(&resource_account_signer, withdrawn_amount));
        tlsd.cumulative_withdrawn = tlsd.cumulative_withdrawn + (withdrawn_amount as u128);

        // request_amount_post_fee < pending_inactive_increment is possible due to min stake requirement.
        // request_amount_post_fee > pending_inactive_increment is possible due to coins-to-shares rounding error.
        // we lock thAPT for amount = min of two and burn the rest to ensure that
        // it is the user rather than the protocol who cover the inevitable rounding error,
        // which is very important to maintain the protocol health.
        let thAPT_unstaking = math64::min(request_amount_post_fee, pending_inactive_increment);
        coin::merge(&mut tlsd.thAPT_unstaking, coin::extract(&mut coin, thAPT_unstaking));
        if (coin::value(&coin) == 0) {
            coin::destroy_zero(coin)
        } else {
            coin::burn(coin, &tlsd.thAPT_burn_capability);
        };

        // queue the unstake request
        try_init_user_unstake(account);
        let start_sec = timestamp::now_seconds();
        let end_sec = start_sec + tlsd.unstake_duration_seconds;
        let request_id = tlsd.next_unstake_request_id;
        tlsd.next_unstake_request_id = request_id + 1;
        let user_unstake = borrow_global_mut<UserUnstake>(account_addr);
        smart_table::add(&mut user_unstake.requests, request_id, UnstakeRequest {
            account: account_addr,
            request_id,
            start_sec,
            end_sec,
            amount: thAPT_unstaking,
        });

        event::emit(RequestUnstakeAPTEvent {
            request_id,
            account: account_addr,
            request_amount,
            fee_amount,
            active_decrement,
            pending_inactive_increment,
            withdrawn_amount
        });
    }

    /// Complete a queuing unstake APT request, following up to request_unstake_APT.
    public fun complete_unstake_APT(account: &signer, request_id: u64): Coin<AptosCoin> acquires TLSD, UserUnstake {
        sync_rewards();

        let account_addr = signer::address_of(account);
        let resource_account_signer = package::resource_account_signer();
        let resource_account_address = package::resource_account_address();

        // validate request_id
        assert!(exists<UserUnstake>(account_addr), ERR_TLSD_USER_UNSTAKE_NOT_EXIST);
        let user_unstake = borrow_global_mut<UserUnstake>(account_addr);
        assert!(smart_table::contains(&user_unstake.requests, request_id), ERR_TLSD_INVALID_REQUEST_ID);

        // check if the unstake request has passed unstake duration
        let request = *smart_table::borrow(&user_unstake.requests, request_id);
        assert!(request.end_sec <= timestamp::now_seconds(), ERR_TLSD_UNSTAKE_REQUEST_NOT_COMPLETABLE);
        let amount = request.amount;

        // if so, remove the completed request
        smart_table::remove(&mut user_unstake.requests, request_id);

        // refill if apt_pending_withdrawal is not enough to fulfill the request
        let tlsd = borrow_global_mut<TLSD>(resource_account_address);
        let withdrawn_amount = if (coin::value(&tlsd.apt_pending_withdrawal) < amount) pool_router::withdraw() else 0;
        if (withdrawn_amount > 0) {
            coin::merge(
                &mut tlsd.apt_pending_withdrawal,
                coin::withdraw<AptosCoin>(&resource_account_signer, withdrawn_amount)
            );
            tlsd.cumulative_withdrawn = tlsd.cumulative_withdrawn + (withdrawn_amount as u128);
        };

        event::emit(CompleteUnstakeAPTEvent {
            account: account_addr,
            request_id,
            unlocked_amount: amount,
            withdrawn_amount,
        });

        // burn locked thAPT
        coin::burn(coin::extract(&mut tlsd.thAPT_unstaking, amount), &tlsd.thAPT_burn_capability);

        // complete the unstake request
        let requested_APT = coin::extract<AptosCoin>(&mut tlsd.apt_pending_withdrawal, amount);

        // restake pending_inactive rewards.
        // at this point, TLSD's inactive stake has been all cleared from underlying pools,
        // and the difference between apt_pending_withdrawal and thAPT_unstaking is pending_inactive rewards.
        // note the rewards are attributed to all stakers, not just the user who completes the unstake request.
        // however, there is no a feasible way to tell how much exact rewards are attributed to the unstaking user.
        // therefore we decide to restake the rewards in order to generate more rewards.
        let apt_pending_withdrawal = coin::value(&tlsd.apt_pending_withdrawal);
        let thAPT_unstaking = coin::value(&tlsd.thAPT_unstaking);
        if (apt_pending_withdrawal > thAPT_unstaking) {
            let restake_amount = apt_pending_withdrawal - thAPT_unstaking;
            let restake_coin = coin::extract<AptosCoin>(&mut tlsd.apt_pending_withdrawal, restake_amount);
            coin::deposit(resource_account_address, restake_coin);
            let (pool, actual_staked) = pool_router::add_stake(restake_amount);
            // we increment cumulative_restake by the same amount as total_stake,
            // which make sense because the restake should not generate extra rewards into the system,
            // as rewards have already been generated by sync_rewards() at the start of this function, if not earlier.
            tlsd.cumulative_restake = tlsd.cumulative_restake + (actual_staked as u128);
            event::emit(RestakeAPTEvent {
                request_id,
                pool,
                restaked_APT: restake_amount,
                cumulative_restake_increment: actual_staked,
            });
        };

        requested_APT
    }

    /// Stakes thAPT and gets sthAPT given exchange rate.
    public fun stake_thAPT(account: &signer, coin: Coin<ThalaAPT>): Coin<StakedThalaAPT> acquires TLSD {
        let thAPT_amount = coin::value(&coin);
        assert!(thAPT_amount > 0, ERR_TLSD_INVALID_COIN_AMOUNT);

        sync_rewards();

        // calculate fee amount
        let fee_amount = math64::mul_div(thAPT_amount, get_lsd().stake_thAPT_fee_bps, BPS_BASE);

        // exchange_rate = thAPT_staking / sthAPT_supply
        // sthAPT_amount = thAPT_amount / exchange_rate = thAPT_amount * sthAPT_supply / thAPT_staking
        let (thAPT_staking, sthAPT_supply) = thAPT_sthAPT_exchange_rate();
        let sthAPT_amount = math64::mul_div(thAPT_amount - fee_amount, sthAPT_supply, thAPT_staking);

        // stake thAPT
        let tlsd = borrow_global_mut<TLSD>(package::resource_account_address());
        // note the fee also goes to thAPT_staking
        coin::merge(&mut tlsd.thAPT_staking, coin);

        // mint sthAPT
        let sthAPT_minted = coin::mint<StakedThalaAPT>(sthAPT_amount, &tlsd.sthAPT_mint_capability);
        event::emit(StakeThalaAPTEvent {
            account: signer::address_of(account),
            thAPT_staked: thAPT_amount,
            thAPT_fee: fee_amount,
            sthAPT_minted: sthAPT_amount,
        });

        sthAPT_minted
    }

    /// Burn sthAPT and unlocks thAPT given exchange rate.
    public fun unstake_thAPT(account: &signer, coin: Coin<StakedThalaAPT>): Coin<ThalaAPT> acquires TLSD {
        let sthAPT_amount = coin::value(&coin);
        assert!(sthAPT_amount > 0, ERR_TLSD_INVALID_COIN_AMOUNT);

        sync_rewards();

        // exchange_rate = thAPT_staking / sthAPT_supply
        // thAPT_amount = sthAPT_amount * exchange_rate = sthAPT_amount * thAPT_staking / sthAPT_supply
        let (thAPT_staking, sthAPT_supply) = thAPT_sthAPT_exchange_rate();
        let thAPT_amount = math64::mul_div(sthAPT_amount, thAPT_staking, sthAPT_supply);

        // burn sthAPT
        let tlsd = borrow_global_mut<TLSD>(package::resource_account_address());
        coin::burn(coin, &tlsd.sthAPT_burn_capability);

        // unstake thAPT
        let thAPT_unstaked = coin::extract(&mut tlsd.thAPT_staking, thAPT_amount);
        event::emit(UnstakeThalaAPTEvent {
            account: signer::address_of(account),
            thAPT_unstaked: thAPT_amount,
            sthAPT_burnt: sthAPT_amount,
        });

        thAPT_unstaked
    }

    // View functions

    #[view]
    /// Returns (thAPT_staking, sthAPT_supply) without syncing rewards.
    public fun thAPT_sthAPT_exchange_rate(): (u64, u64) acquires TLSD {
        let sthAPT_supply = sthAPT_supply();
        if (sthAPT_supply == 0) { return (1, 1) };

        (thAPT_staking(), sthAPT_supply)
    }

    #[view]
    /// Returns (thAPT_staking, sthAPT_supply) after syncing rewards.
    public fun thAPT_sthAPT_exchange_rate_synced(): (u64, u64) acquires TLSD {
        sync_rewards();
        thAPT_sthAPT_exchange_rate()
    }

    #[view]
    public fun thAPT_supply(): u64 {
        (option::extract(&mut coin::supply<ThalaAPT>()) as u64)
    }

    #[view]
    public fun sthAPT_supply(): u64 {
        (option::extract(&mut coin::supply<StakedThalaAPT>()) as u64)
    }

    #[view]
    public fun next_unstake_request_id(): u64 acquires TLSD {
        get_lsd().next_unstake_request_id
    }

    #[view]
    public fun unstake_duration_seconds(): u64 acquires TLSD {
        get_lsd().unstake_duration_seconds
    }

    #[view]
    public fun user_unstake(account_addr: address): vector<UnstakeRequest> acquires UserUnstake {
        if (!exists<UserUnstake>(account_addr)) vector::empty<UnstakeRequest>()
        else simple_map::values(&smart_table::to_simple_map(&borrow_global<UserUnstake>(account_addr).requests))
    }

    #[view]
    public fun unstake_APT_fee_bps(): u64 acquires TLSD {
        get_lsd().unstake_APT_fee_bps
    }

    #[view]
    public fun stake_thAPT_fee_bps(): u64 acquires TLSD {
        get_lsd().stake_thAPT_fee_bps
    }

    #[view]
    public fun extra_rewards_for_sthAPT_holders_bps(): u64 acquires TLSD {
        get_lsd().extra_rewards_for_sthAPT_holders_bps
    }

    #[view]
    public fun rewards_kept(): u64 acquires TLSD {
        coin::value<ThalaAPT>(&get_lsd().rewards_kept)
    }

    #[view]
    public fun thAPT_staking(): u64 acquires TLSD {
        coin::value<ThalaAPT>(&get_lsd().thAPT_staking)
    }

    #[view]
    public fun thAPT_unstaking(): u64 acquires TLSD {
        coin::value<ThalaAPT>(&get_lsd().thAPT_unstaking)
    }

    #[view]
    public fun apt_pending_withdrawal(): u64 acquires TLSD {
        coin::value<AptosCoin>(&get_lsd().apt_pending_withdrawal)
    }

    #[view]
    public fun cumulative_restake(): u128 acquires TLSD {
        get_lsd().cumulative_restake
    }

    #[view]
    public fun cumulative_deposit(): u128 acquires TLSD {
        get_lsd().cumulative_deposit
    }

    #[view]
    public fun cumulative_withdrawn(): u128 acquires TLSD {
        get_lsd().cumulative_withdrawn
    }

    #[view]
    public fun cumulative_rewards(): u128 acquires TLSD {
        get_lsd().cumulative_rewards
    }

    #[view]
    public fun total_stake(): u128 {
        let (total_active, total_inactive, total_pending_inactive) = pool_router::get_total_stakes();
        total_active + total_inactive + total_pending_inactive
    }

    // Internal functions

    /// Mint thAPT rewards and distribute to sthAPT holders and thAPT-APT LPs.
    ///
    /// thAPT rewards are minted based on:
    /// 1) cumulative_rewards = max(cumulative_rewards, total_stake + cumulative_withdrawn - cumulative_deposit - cumulative_restake),
    ///    where total_stake = total_active + total_inactive + total_pending_inactive.
    /// 2) mint_thAPT = current cumulative_rewards - last cumulative_rewards.
    ///
    /// The reason why we use max() is because
    /// total_stake + cumulative_withdrawn - cumulative_deposit - cumulative_restake could be less than cumulative_rewards,
    /// that makes mint_thAPT a negative number.
    /// For example, it is possible that cumulative_deposit=9999980753 while total_stake=9999980752 and cumulative_withdrawn=0
    /// due to rounding errors caused by shares-to-coins conversion in delegation_pool operations.
    /// With max(), we guarantee that cumulative_rewards is increment-only and mint_thAPT is always >=0.
    fun sync_rewards() acquires TLSD {
        let resource_account_address = package::resource_account_address();
        let tlsd = borrow_global_mut<TLSD>(resource_account_address);

        let (total_active, total_inactive, total_pending_inactive) = pool_router::get_total_stakes();
        let total_stake = total_active + total_inactive + total_pending_inactive;
        let prev_cumulative_rewards = tlsd.cumulative_rewards;

        if (total_stake + tlsd.cumulative_withdrawn > tlsd.cumulative_restake + tlsd.cumulative_deposit + tlsd.cumulative_rewards) {
            tlsd.cumulative_rewards = total_stake + tlsd.cumulative_withdrawn - tlsd.cumulative_restake - tlsd.cumulative_deposit;
        };

        let rewards_amount = ((tlsd.cumulative_rewards - prev_cumulative_rewards) as u64);
        let (rewards_commission, rewards_for_sthAPT_holders, rewards_kept) = if (rewards_amount == 0) {
            (0, 0, 0)
        } else {
            let rewards_commission = math64::mul_div(rewards_amount, tlsd.commission_fee_bps, BPS_BASE);
            let rewards_remaining = rewards_amount - rewards_commission;
            let rewards_for_sthAPT_holders = {
                let rewards_pro_rata = math64::mul_div(rewards_remaining, coin::value(&tlsd.thAPT_staking), thAPT_supply());
                let rewards_rest_for_sthAPT = math64::mul_div(rewards_remaining - rewards_pro_rata, tlsd.extra_rewards_for_sthAPT_holders_bps, BPS_BASE);
                rewards_pro_rata + rewards_rest_for_sthAPT
            };
            let rewards_kept = rewards_remaining - rewards_for_sthAPT_holders;

            // mint then extract should cost less gas than 3 mints since mint is a lot more complex op than extract
            let rewards_coin = coin::mint(rewards_amount, &tlsd.thAPT_mint_capability);
            coin::merge(&mut tlsd.commission_fee, coin::extract(&mut rewards_coin, rewards_commission));
            coin::merge(&mut tlsd.thAPT_staking, coin::extract(&mut rewards_coin, rewards_for_sthAPT_holders));
            coin::merge(&mut tlsd.rewards_kept, rewards_coin);

            (rewards_commission, rewards_for_sthAPT_holders, rewards_kept)
        };

        event::emit(SyncRewardsEvent {
            total_active,
            total_inactive,
            total_pending_inactive,
            cumulative_restake: tlsd.cumulative_restake,
            cumulative_deposit: tlsd.cumulative_deposit,
            cumulative_withdrawn: tlsd.cumulative_withdrawn,
            prev_cumulative_rewards,
            cumulative_rewards: tlsd.cumulative_rewards,
            rewards_amount,
            rewards_commission,
            rewards_for_sthAPT_holders,
            rewards_kept
        });
    }

    fun try_init_user_unstake(account: &signer) {
        if (!exists<UserUnstake>(signer::address_of(account))) {
            move_to(account, UserUnstake {
                requests: smart_table::new(),
            })
        };
    }

    inline fun get_lsd(): &TLSD acquires TLSD {
        borrow_global<TLSD>(package::resource_account_address())
    }

    // Test only functions

    #[test_only]
    public fun init_module_for_test() {
        init_module(&package::resource_account_signer());
    }

    #[test_only]
    public fun burn_thAPT(coin: Coin<ThalaAPT>) acquires TLSD {
        if (coin::value(&coin) == 0) coin::destroy_zero(coin)
        else coin::burn(coin, &get_lsd().thAPT_burn_capability)
    }

    #[test_only]
    public fun burn_sthAPT(coin: Coin<StakedThalaAPT>) acquires TLSD {
        if (coin::value(&coin) == 0) coin::destroy_zero(coin)
        else coin::burn(coin, &get_lsd().sthAPT_burn_capability)
    }

    #[test_only]
    public fun unstake_request_value(request: &UnstakeRequest): (address, u64, u64, u64, u64) {
        (request.account, request.request_id, request.start_sec, request.end_sec, request.amount)
    }
}