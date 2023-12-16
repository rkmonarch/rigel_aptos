module rigel::liquidity_pool {

    use std::signer;
    use aptos_std::event;
    use aptos_framework::account::{Self, SignerCapability};
    use aptos_framework::coin::{Self, Coin};
    use aptos_framework::timestamp;

    const APP_SIGNER_CAPABILITY_SEED: vector<u8> = b"APP_SIGNER_CAPABILITY";

    struct UserPools has key {
        pool_address: address,
        total_deposit: u64,
    }

    struct LiquidityPool has key, store {
        deposit_token: BasicTokens,
        fee: u64
    }

    struct PoolAccountCapability has key { signer_cap: SignerCapability }

    fun init_module(account: &signer){
            let (pool_resource, pool_signer_cap) = account::create_resource_account(
            account,
            APP_SIGNER_CAPABILITY_SEED,
        );

         move_to(account, PoolAccountCapability {
            signer_cap: pool_signer_cap,
        });
    }

    public entry fun initialize() {}

    public entry fun deploy_pool<BasicTokens>(acc: &signer, fee:u64, ) acquires PoolAccountCapability{
        //Manager will register liquidity pool
        let signer_address = signer::address_of(acc);
        let pool_cap = borrow_global<PoolAccountCapability>(@rigel);
        let pool_account = account::create_signer_with_capability(&pool_cap.signer_cap);
        
        let pool = LiquidityPool {
            deposit_token: BasicTokens::new,
            fee: fee,
        };
       move_to(&pool_account, pool);
    }

    // public fun get_pool_details<X>(acc: &signer):LiquidityPool<X> acquires LiquidityPool {
        // let pool = borrow_global<LiquidityPool<X>>(@rigel);
        // let pool_details = LiquidityPool<X> {
        //     deposit_token: pool.deposit_token,
        //     fee: pool.fee,
        // };
        // pool_details
    // }

    public fun deposit(acc:&signer, poolAddress: address, amount:u64) {
        let signer_address = signer::address_of(acc);
        let pool = borrow_global<LiquidityPool>(poolAddress);
        let balance = Coin::balance_of(signer_address);
    }

    public fun withdraw() {}

    public fun whitelist_users() {}

    public fun delist_users() {}

    public fun open_position_vault() {}

    public fun close_position_vault() {}

}