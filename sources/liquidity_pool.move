module rigel::liquidity_pool {

    use std::signer;
    use aptos_std::event;
    use aptos_framework::account::{Self, SignerCapability};
    use aptos_framework::coin::{Self, Coin};
    use aptos_framework::timestamp;

    struct UserPools has key {
        pool: LiquidityPool,
        total_deposit: u64
    }

    struct LiquidityPool<phantom X> has key, store {
        pool_id: u64,
        pool_manager: address,
        deposit_token: Coin<X>,
        fee: u64
    }

    struct PoolAccountCapability has key { signer_cap: SignerCapability }

    public entry fun initialize() {}

    public fun deploy_pool<X>(acc: &signer) acquires PoolAccountCapability{
        //Manager will register liquidity pool
    }

    public fun get_pool_details() {}

    public fun mint() {}

    public fun deposit() {}

    public fun withdraw() {}

    public fun whitelist_users() {}

    public fun delist_users() {}

    public fun open_position_vault() {}

    public fun close_position_vault() {}

}