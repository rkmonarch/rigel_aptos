module rigel::liquidity_pool {

    use std::signer;
    use aptos_std::event;
    use aptos_framework::account::{Self, SignerCapability};
    use aptos_framework::coin::{Self, Coin};
    use aptos_framework::timestamp;

     struct LiquidityPool<phantom X, phantom Y, phantom Curve> has key {
        coin_x_reserve: Coin<X>,
        coin_y_reserve: Coin<Y>,
        fee: u64
    }

    struct PoolAccountCapability has key { signer_cap: SignerCapability }

    public entry fun initialize() {}

    public fun deploy_pool<X, Y, Curve>(acc: &signer) acquires PoolAccountCapability{}

    public fun get_pool_details() {}

    public fun mint() {}


}