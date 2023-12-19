module thala_lsd::scripts {
    use std::signer;
    use aptos_framework::aptos_coin::AptosCoin;
    use aptos_framework::coin;
    use thala_lsd::staking::{Self, ThalaAPT, StakedThalaAPT};

    public entry fun stake_APT(account: &signer, amount_APT: u64) {
        let thAPT = staking::stake_APT(account, coin::withdraw<AptosCoin>(account, amount_APT));
        coin::register<ThalaAPT>(account);
        coin::deposit(signer::address_of(account), thAPT);
    }

    public entry fun request_unstake_APT(account: &signer, amount_thAPT: u64) {
        staking::request_unstake_APT(account, coin::withdraw<ThalaAPT>(account, amount_thAPT));
    }

    public entry fun complete_unstake_APT(account: &signer, request_id: u64) {
        coin::deposit(signer::address_of(account), staking::complete_unstake_APT(account, request_id));
    }

    public entry fun stake_thAPT(account: &signer, amount_thAPT: u64) {
        let sthAPT = staking::stake_thAPT(account, coin::withdraw<ThalaAPT>(account, amount_thAPT));
        coin::register<StakedThalaAPT>(account);
        coin::deposit(signer::address_of(account), sthAPT);
    }

    public entry fun unstake_thAPT(account: &signer, amount_sthAPT: u64) {
        let thAPT = staking::unstake_thAPT(account, coin::withdraw<StakedThalaAPT>(account, amount_sthAPT));
        coin::register<ThalaAPT>(account);
        coin::deposit(signer::address_of(account), thAPT);
    }

    public entry fun transfer_commission(account: &signer, to: address) {
        let thAPT = staking::extract_commission_fee(account);
        coin::deposit(to, thAPT);
    }

    public entry fun transfer_rewards_kept(account: &signer, to: address) {
        let thAPT = staking::extract_rewards_kept(account);
        coin::deposit(to, thAPT);
    }
}
