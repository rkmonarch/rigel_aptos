module rigel::liquidity_pool {

    use std::signer;
    use aptos_std::event;
    use aptos_framework::account::{Self, SignerCapability};
    use aptos_framework::coin::{Self, Coin};
    use aptos_framework::timestamp;

     struct LiquidityPool<phantom X> has key {
        pool_manager: address,
        deposit_token: Coin<X>,
        fee: u64
    }

    struct PoolAccountCapability has key { signer_cap: SignerCapability }

    public entry fun initialize() {}

    public fun deploy_pool<X>(acc: &signer) acquires PoolAccountCapability{}

    public fun get_pool_details() {}

    public fun mint() {}


}