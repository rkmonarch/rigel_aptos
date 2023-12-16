module rigel::BasicTokens{
    use std::error;
    use std::signer;

    /// Error codes
    const ENOT_MODULE_OWNER: u64 = 0;
    const EINSUFFICIENT_BALANCE: u64 = 1;
    const EALREADY_HAS_BALANCE: u64 = 2;
    const EALREADY_INITIALIZED: u64 = 3;
    const EEQUAL_ADDR: u64 = 4;

    struct Coin has store,drop {
        value: u64
    }

    struct Balance has key {
        coin: Coin
    }

    public fun createCoin(v:u64): Coin
    {
        let coin = Coin {
            value:v
        };
        return coin
    }


    public fun publish_balance(account: &signer) {
        let empty_coin = Coin { value: 0 };
        assert!(!exists<Balance>(signer::address_of(account)), error::already_exists(EALREADY_HAS_BALANCE));
        move_to(account, Balance { coin:  empty_coin });
    }

    public fun mint<CoinType: drop>(mint_addr: address, amount: u64) acquires Balance {
        deposit(mint_addr, Coin{ value: amount });
    }

    public fun burn(burn_addr: address, amount: u64) acquires Balance {
        let Coin { value: _ } = withdraw(burn_addr, amount);
    }

    public fun balance_of(owner: address): u64 acquires Balance {
        borrow_global<Balance>(owner).coin.value
    }


    public fun transfer(from: &signer, to: address, amount: u64) acquires Balance {
        let from_addr = signer::address_of(from);
        assert!(from_addr != to, EEQUAL_ADDR);
        let check = withdraw(from_addr, amount);
        deposit(to, check);
    }

    public fun withdraw(addr: address, amount: u64) : Coin acquires Balance {
        let balance = balance_of(addr);
        assert!(balance >= amount, EINSUFFICIENT_BALANCE);
        let balance_ref = &mut borrow_global_mut<Balance>(addr).coin.value;
        *balance_ref = balance - amount;
        Coin { value: amount }
    }

    public fun deposit(addr: address, check: Coin) acquires Balance{
        let balance = balance_of(addr);
        let balance_ref = &mut borrow_global_mut<Balance>(addr).coin.value;
        let Coin { value } = check;
        *balance_ref = balance + value;
    }

}