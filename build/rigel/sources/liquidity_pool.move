module rigel::liquidity_pool {

    use std::signer;
    use aptos_std::event;
    use aptos_framework::account::{Self, SignerCapability};
    use aptos_framework::timestamp;

    use aptos_framework::managed_coin;
    use aptos_framework::coin;
    use aptos_std::type_info;
    use aptos_std::simple_map::{Self, SimpleMap};

    struct UserPools has key {
        pool_address: address,
        total_deposit: u64,
    }

    struct LiquidityPool has key, store {
        resource_cap: account::SignerCapability,
        coin_type: address,
        fee: u64
    }

    struct LiquidityPoolCap  has key {
        liquidity_pool_map: SimpleMap< vector<u8>,address>,
    }


    fun coin_address<CoinType>(): address {
        let type_info = type_info::type_of<CoinType>();
        type_info::account_address(&type_info)
    }

    public entry fun deploy_pool<CoinType>(account: &signer, fee:u64, seeds: vector<u8>) acquires LiquidityPoolCap {
        let account_addr = signer::address_of(account);
        let (liquidity_pool, liquidity_pool_cap) = account::create_resource_account(account, seeds); //resource account
        let liquidity_pool_address = signer::address_of(&liquidity_pool);
        if (!exists<LiquidityPoolCap>(account_addr)) {
            move_to(account, LiquidityPoolCap {liquidity_pool_map: simple_map::create()})
        };
        let maps = borrow_global_mut<LiquidityPoolCap>(account_addr);
        simple_map::add(&mut maps.liquidity_pool_map, seeds,liquidity_pool_address);

        let pool_signer_from_cap = account::create_signer_with_capability(&liquidity_pool_cap);
        let coin_address = coin_address<CoinType>();

        move_to(&pool_signer_from_cap, LiquidityPool{resource_cap: liquidity_pool_cap, coin_type: coin_address, fee: fee});

        managed_coin::register<CoinType>(&pool_signer_from_cap); 
    }


    public fun deposit<CoinType>(account: &signer, pool_address: address, amount: u64) acquires UserPools {
        let signer_address = signer::address_of(account);

        if(!exists<UserPools>(signer_address))
        {
            let pool = UserPools {
               pool_address,
               total_deposit: amount
            };
            move_to(account,pool);
        } else {
            let pool = borrow_global_mut<UserPools>(signer_address); 
            pool.total_deposit = amount;
        };
        coin::transfer<CoinType>(account, pool_address, amount);
    }

    public fun withdraw() {}

    public fun open_position_vault() {}

    public fun close_position_vault() {}

}