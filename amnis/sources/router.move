module amnis::router{
    public entry fun deposit_and_stake_entry(_account:&signer,_amount:u64, _address:address) {
        abort 1;
    }

    public entry fun unstake_entry(_account:&signer,_amount:u64, _address:address) {
        abort 1;
    }
}

// {
//   "address": "0xb8188ed9a1b56a11344aab853f708ead152484081c3b5ec081c38646500c42d7",
//   "name": "router",
//   "friends": [
//     "0xb8188ed9a1b56a11344aab853f708ead152484081c3b5ec081c38646500c42d7::governance"
//   ],
//   "exposed_functions": [
//     {
//       "name": "current_reward_rate",
//       "visibility": "public",
//       "is_entry": false,
//       "is_view": true,
//       "generic_type_params": [],
//       "params": [],
//       "return": [
//         "u64",
//         "u64"
//       ]
//     },
//     {
//       "name": "deposit",
//       "visibility": "public",
//       "is_entry": false,
//       "is_view": false,
//       "generic_type_params": [],
//       "params": [
//         "0x1::coin::Coin<0x1::aptos_coin::AptosCoin>"
//       ],
//       "return": [
//         "0x1::coin::Coin<0xb8188ed9a1b56a11344aab853f708ead152484081c3b5ec081c38646500c42d7::amapt_token::AmnisApt>"
//       ]
//     },
//     {
//       "name": "deposit_and_stake",
//       "visibility": "public",
//       "is_entry": false,
//       "is_view": false,
//       "generic_type_params": [],
//       "params": [
//         "0x1::coin::Coin<0x1::aptos_coin::AptosCoin>"
//       ],
//       "return": [
//         "0x1::coin::Coin<0xb8188ed9a1b56a11344aab853f708ead152484081c3b5ec081c38646500c42d7::stapt_token::StakedApt>"
//       ]
//     },
//     {
//       "name": "deposit_and_stake_entry",
//       "visibility": "public",
//       "is_entry": true,
//       "is_view": false,
//       "generic_type_params": [],
//       "params": [
//         "&signer",
//         "u64",
//         "address"
//       ],
//       "return": []
//     },
//     {
//       "name": "deposit_direct",
//       "visibility": "friend",
//       "is_entry": false,
//       "is_view": false,
//       "generic_type_params": [],
//       "params": [
//         "0x1::coin::Coin<0x1::aptos_coin::AptosCoin>",
//         "address"
//       ],
//       "return": [
//         "0x1::coin::Coin<0xb8188ed9a1b56a11344aab853f708ead152484081c3b5ec081c38646500c42d7::amapt_token::AmnisApt>"
//       ]
//     },
//     {
//       "name": "deposit_entry",
//       "visibility": "public",
//       "is_entry": true,
//       "is_view": false,
//       "generic_type_params": [],
//       "params": [
//         "&signer",
//         "u64",
//         "address"
//       ],
//       "return": []
//     },
//     {
//       "name": "initialize",
//       "visibility": "public",
//       "is_entry": true,
//       "is_view": false,
//       "generic_type_params": [],
//       "params": [],
//       "return": []
//     },
//     {
//       "name": "max_fee",
//       "visibility": "public",
//       "is_entry": false,
//       "is_view": true,
//       "generic_type_params": [],
//       "params": [],
//       "return": [
//         "u64"
//       ]
//     },
//     {
//       "name": "max_fee_for",
//       "visibility": "public",
//       "is_entry": false,
//       "is_view": true,
//       "generic_type_params": [],
//       "params": [
//         "u64"
//       ],
//       "return": [
//         "u64"
//       ]
//     },
//     {
//       "name": "request_withdraw",
//       "visibility": "public",
//       "is_entry": false,
//       "is_view": false,
//       "generic_type_params": [],
//       "params": [
//         "0x1::coin::Coin<0xb8188ed9a1b56a11344aab853f708ead152484081c3b5ec081c38646500c42d7::amapt_token::AmnisApt>",
//         "address"
//       ],
//       "return": [
//         "0x1::object::Object<0xb8188ed9a1b56a11344aab853f708ead152484081c3b5ec081c38646500c42d7::withdrawal::WithdrawalToken>"
//       ]
//     },
//     {
//       "name": "request_withdrawal_entry",
//       "visibility": "public",
//       "is_entry": true,
//       "is_view": false,
//       "generic_type_params": [],
//       "params": [
//         "&signer",
//         "u64",
//         "address"
//       ],
//       "return": []
//     },
//     {
//       "name": "router_address",
//       "visibility": "public",
//       "is_entry": false,
//       "is_view": true,
//       "generic_type_params": [],
//       "params": [],
//       "return": [
//         "address"
//       ]
//     },
//     {
//       "name": "stake",
//       "visibility": "public",
//       "is_entry": false,
//       "is_view": false,
//       "generic_type_params": [],
//       "params": [
//         "0x1::coin::Coin<0xb8188ed9a1b56a11344aab853f708ead152484081c3b5ec081c38646500c42d7::amapt_token::AmnisApt>"
//       ],
//       "return": [
//         "0x1::coin::Coin<0xb8188ed9a1b56a11344aab853f708ead152484081c3b5ec081c38646500c42d7::stapt_token::StakedApt>"
//       ]
//     },
//     {
//       "name": "stake_entry",
//       "visibility": "public",
//       "is_entry": true,
//       "is_view": false,
//       "generic_type_params": [],
//       "params": [
//         "&signer",
//         "u64",
//         "address"
//       ],
//       "return": []
//     },
//     {
//       "name": "unstake",
//       "visibility": "public",
//       "is_entry": false,
//       "is_view": false,
//       "generic_type_params": [],
//       "params": [
//         "0x1::coin::Coin<0xb8188ed9a1b56a11344aab853f708ead152484081c3b5ec081c38646500c42d7::stapt_token::StakedApt>"
//       ],
//       "return": [
//         "0x1::coin::Coin<0xb8188ed9a1b56a11344aab853f708ead152484081c3b5ec081c38646500c42d7::amapt_token::AmnisApt>"
//       ]
//     },
//     {
//       "name": "unstake_entry",
//       "visibility": "public",
//       "is_entry": true,
//       "is_view": false,
//       "generic_type_params": [],
//       "params": [
//         "&signer",
//         "u64",
//         "address"
//       ],
//       "return": []
//     },
//     {
//       "name": "withdraw",
//       "visibility": "public",
//       "is_entry": false,
//       "is_view": false,
//       "generic_type_params": [],
//       "params": [
//         "&signer",
//         "0x1::object::Object<0xb8188ed9a1b56a11344aab853f708ead152484081c3b5ec081c38646500c42d7::withdrawal::WithdrawalToken>"
//       ],
//       "return": [
//         "0x1::coin::Coin<0x1::aptos_coin::AptosCoin>"
//       ]
//     },
//     {
//       "name": "withdraw_entry",
//       "visibility": "public",
//       "is_entry": true,
//       "is_view": false,
//       "generic_type_params": [],
//       "params": [
//         "&signer",
//         "0x1::object::Object<0xb8188ed9a1b56a11344aab853f708ead152484081c3b5ec081c38646500c42d7::withdrawal::WithdrawalToken>"
//       ],
//       "return": []
//     },
//     {
//       "name": "withdraw_multi",
//       "visibility": "public",
//       "is_entry": false,
//       "is_view": false,
//       "generic_type_params": [],
//       "params": [
//         "&signer",
//         "vector<0x1::object::Object<0xb8188ed9a1b56a11344aab853f708ead152484081c3b5ec081c38646500c42d7::withdrawal::WithdrawalToken>>"
//       ],
//       "return": [
//         "0x1::coin::Coin<0x1::aptos_coin::AptosCoin>"
//       ]
//     },
//     {
//       "name": "withdraw_multi_entry",
//       "visibility": "public",
//       "is_entry": true,
//       "is_view": false,
//       "generic_type_params": [],
//       "params": [
//         "&signer",
//         "vector<0x1::object::Object<0xb8188ed9a1b56a11344aab853f708ead152484081c3b5ec081c38646500c42d7::withdrawal::WithdrawalToken>>"
//       ],
//       "return": []
//     }
//   ],
//   "structs": [
//     {
//       "name": "Events",
//       "is_native": false,
//       "abilities": [
//         "key"
//       ],
//       "generic_type_params": [],
//       "fields": [
//         {
//           "name": "mint_events",
//           "type": "0x1::event::EventHandle<0xb8188ed9a1b56a11344aab853f708ead152484081c3b5ec081c38646500c42d7::router::MintEvent>"
//         },
//         {
//           "name": "stake_events",
//           "type": "0x1::event::EventHandle<0xb8188ed9a1b56a11344aab853f708ead152484081c3b5ec081c38646500c42d7::router::StakeEvent>"
//         },
//         {
//           "name": "unstake_events",
//           "type": "0x1::event::EventHandle<0xb8188ed9a1b56a11344aab853f708ead152484081c3b5ec081c38646500c42d7::router::UnstakeEvent>"
//         },
//         {
//           "name": "withdrawal_request_event",
//           "type": "0x1::event::EventHandle<0xb8188ed9a1b56a11344aab853f708ead152484081c3b5ec081c38646500c42d7::router::WithdrawalRequestEvent>"
//         },
//         {
//           "name": "withdraw_events",
//           "type": "0x1::event::EventHandle<0xb8188ed9a1b56a11344aab853f708ead152484081c3b5ec081c38646500c42d7::router::WithdrawEvent>"
//         }
//       ]
//     },
//     {
//       "name": "MintEvent",
//       "is_native": false,
//       "abilities": [
//         "drop",
//         "store"
//       ],
//       "generic_type_params": [],
//       "fields": [
//         {
//           "name": "apt",
//           "type": "u64"
//         },
//         {
//           "name": "amapt",
//           "type": "u64"
//         }
//       ]
//     },
//     {
//       "name": "StakeEvent",
//       "is_native": false,
//       "abilities": [
//         "drop",
//         "store"
//       ],
//       "generic_type_params": [],
//       "fields": [
//         {
//           "name": "amapt",
//           "type": "u64"
//         },
//         {
//           "name": "stapt",
//           "type": "u64"
//         }
//       ]
//     },
//     {
//       "name": "UnstakeEvent",
//       "is_native": false,
//       "abilities": [
//         "drop",
//         "store"
//       ],
//       "generic_type_params": [],
//       "fields": [
//         {
//           "name": "stapt",
//           "type": "u64"
//         },
//         {
//           "name": "amapt",
//           "type": "u64"
//         }
//       ]
//     },
//     {
//       "name": "WithdrawEvent",
//       "is_native": false,
//       "abilities": [
//         "drop",
//         "store"
//       ],
//       "generic_type_params": [],
//       "fields": [
//         {
//           "name": "owner",
//           "type": "address"
//         },
//         {
//           "name": "amount",
//           "type": "u64"
//         },
//         {
//           "name": "withdrawal_token",
//           "type": "0x1::object::Object<0xb8188ed9a1b56a11344aab853f708ead152484081c3b5ec081c38646500c42d7::withdrawal::WithdrawalToken>"
//         }
//       ]
//     },
//     {
//       "name": "WithdrawalRequestEvent",
//       "is_native": false,
//       "abilities": [
//         "drop",
//         "store"
//       ],
//       "generic_type_params": [],
//       "fields": [
//         {
//           "name": "amount",
//           "type": "u64"
//         },
//         {
//           "name": "receiver",
//           "type": "address"
//         },
//         {
//           "name": "withdrawal_token",
//           "type": "0x1::object::Object<0xb8188ed9a1b56a11344aab853f708ead152484081c3b5ec081c38646500c42d7::withdrawal::WithdrawalToken>"
//         }
//       ]
//     }
//   ]
// }