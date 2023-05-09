module aptos_launch::alt_slt_bond_v3 {
    use std::signer;
    use aptos_framework::coin;
    use aptos_framework::account;
    use aptos_framework::managed_coin;
    use aptos_framework::timestamp;
    // use aptos_std::debug;
    use aptos_std::type_info;
    use aptos_std::table_with_length;

    const EPOOL_NOT_INITIALIZED: u64 = 0;
    const EINVALID_DEDICATED_INITIALIZER: u64 = 4;
    const EINVALID_OWNER: u64 = 5;
    const ENO_RECORD_FOUND: u64 = 1;
    const EINSUFFICIENT_BALANCE: u64 = 2;
    const EINVALID_VALUE: u64 = 3;
    const EINVALID_COIN: u64 = 6;
    const ENOT_YET_START: u64 = 7;
    const EENDED: u64 = 8;
    const EMUST_BE_AFTER_CURRENT_TIME: u64 = 9;
    const EINVALID_TIME: u64 = 10;
    const EINVALID_PRECISION: u64 = 11;
    const EINVALID_BALANCE: u64 = 12;
    const EINVALID_FEE_RATE: u64 = 13;
    const EINVALID_UPDATE_RATE_OWNER: u64 = 14;
    const EPOOL_PAUSED: u64 = 15;
    const EEXCEED_BOND_IN_REMAINING: u64 = 16;
    const EALREADY_HAS_INVESTOR_TABLE: u64 = 17;
    const FEE_PRECISION: u128 = 10000;
    const COLLECT_ADDRESS: address = @collect_address;

    struct BondInfo has key, store, drop {
        amount_remaining: u64,
        amount_per_epoch: u64,
        epoch_remaining: u64,
        last_update: u64,
        amount_distributed: u64
    }

    struct PoolInfo has key, store {
        total_bond_in_amount: u128,
        distributed_reward: u128,
        start_time: u64,
        conversion_rate: u64,
        conversion_precision: u64,
        bonus_rate: u64,
        bonus_precision: u64,
        end_time: u64,
        lock_epoch: u64,
        epoch_time: u64,
        fee_rate: u64, 
        total_fee: u128, 
        new_conversion_rate: u64,
        new_conversion_precision: u64,
        new_bonus_rate: u64,
        new_bonus_precision: u64,
        new_lock_epoch: u64,
        new_epoch_time: u64,
        new_conversion_rate_start_time: u64,
        bond_in_status: bool,
        bond_in_remaining: u64,
        reward_coin_address: address,
        reward_coin_module_name: vector<u8>,
        reward_coin_struct_name: vector<u8>,
        stake_coin_address: address,
        stake_coin_module_name: vector<u8>,
        stake_coin_struct_name: vector<u8>,
        resource_cap: account::SignerCapability
    }

    struct OwnerCapability has key, store, drop {
        owner_addr: address
    }

    struct OwnerCapabilityTransferInfo has key, store, drop {
        new_owner_addr: address
    }

    struct UpdateRateCapability has key, store, drop {
        owner_addr: address
    }

    struct UpdateRateCapabilityTransferInfo has key, store, drop {
        new_owner_addr: address
    }

    struct Investors<phantom K: copy + drop, phantom V: drop> has store, key{
        t: table_with_length::TableWithLength<K, V>,
    }

    fun create_investor_table(pool: &signer){
        let pool_addr = signer::address_of(pool);
        assert!(!exists<Investors<u64, address>>(pool_addr), EALREADY_HAS_INVESTOR_TABLE);
        let t = table_with_length::new<u64, address>();
        move_to(pool, Investors { t });      
    }

    public entry fun initialize<CoinType1, CoinType2>(initializer: &signer, seeds: vector<u8>, start_time: u64, conversion_rate: u64, conversion_precision: u64, bonus_rate: u64, bonus_precision: u64,end_time: u64, lock_epoch: u64, epoch_time: u64, fee_rate: u64, bond_in_status: bool, bond_in_remaining: u64,) {
        let owner_addr = signer::address_of(initializer);
        assert!(owner_addr == @aptos_launch, EINVALID_DEDICATED_INITIALIZER);
        move_to<OwnerCapability>(initializer, OwnerCapability { owner_addr });
        move_to<UpdateRateCapability>(initializer, UpdateRateCapability { owner_addr });
        let (pool, pool_signer_cap) = account::create_resource_account(initializer, seeds);
        let stake_coin_address = type_info::account_address(&type_info::type_of<CoinType1>());
        let stake_coin_module_name = type_info::module_name(&type_info::type_of<CoinType1>());
        let stake_coin_struct_name = type_info::struct_name(&type_info::type_of<CoinType1>());
        let reward_coin_address = type_info::account_address(&type_info::type_of<CoinType2>());
        let reward_coin_module_name = type_info::module_name(&type_info::type_of<CoinType2>());
        let reward_coin_struct_name = type_info::struct_name(&type_info::type_of<CoinType2>());

        move_to<PoolInfo>(&pool, PoolInfo {
            total_bond_in_amount: 0,
            distributed_reward: 0,
            start_time,
            conversion_rate,
            conversion_precision,
            bonus_rate: bonus_rate,
            bonus_precision: bonus_precision,
            new_conversion_rate: conversion_rate,
            new_conversion_precision: conversion_precision,
            new_bonus_rate: bonus_rate,
            new_bonus_precision: bonus_precision,
            new_conversion_rate_start_time: 0,
            resource_cap: pool_signer_cap,
            end_time,
            fee_rate,
            total_fee: 0,
            lock_epoch,
            epoch_time,
            new_epoch_time: epoch_time,
            new_lock_epoch: lock_epoch,
            bond_in_status,
            bond_in_remaining,
            reward_coin_address,
            reward_coin_module_name,
            reward_coin_struct_name,
            stake_coin_address,
            stake_coin_module_name,
            stake_coin_struct_name
        });
        coin::register<CoinType1>(&pool);
        create_investor_table(&pool)
    }

    public entry fun transfer_ownership(current_owner: &signer, new_owner_addr: address) acquires OwnerCapabilityTransferInfo {
        let current_owner_addr = signer::address_of(current_owner);
        assert!(exists<OwnerCapability>(current_owner_addr), EINVALID_OWNER);
        
        if (exists<OwnerCapabilityTransferInfo>(current_owner_addr)) {
            let transferInfo = borrow_global_mut<OwnerCapabilityTransferInfo>(current_owner_addr);
            transferInfo.new_owner_addr = new_owner_addr;
        } else {
            move_to<OwnerCapabilityTransferInfo>(current_owner, OwnerCapabilityTransferInfo { new_owner_addr });
        }
    }

    public entry fun get_ownership(new_owner: &signer, current_owner_addr: address) acquires OwnerCapability, OwnerCapabilityTransferInfo {
        assert!(exists<OwnerCapability>(current_owner_addr), EINVALID_VALUE);
        assert!(exists<OwnerCapabilityTransferInfo>(current_owner_addr), EINVALID_VALUE);

        let new_owner_addr = signer::address_of(new_owner);

        let transferInfo = borrow_global<OwnerCapabilityTransferInfo>(current_owner_addr);
        assert!(transferInfo.new_owner_addr == new_owner_addr, EINVALID_VALUE);

        move_from<OwnerCapabilityTransferInfo>(current_owner_addr);
        move_from<OwnerCapability>(current_owner_addr);

        move_to<OwnerCapability>(new_owner, OwnerCapability { owner_addr: new_owner_addr });
        move_to<OwnerCapabilityTransferInfo>(new_owner, OwnerCapabilityTransferInfo { new_owner_addr });
    }

    public entry fun transfer_change_rate(current_owner: &signer, new_owner_addr: address) acquires UpdateRateCapabilityTransferInfo {
        let current_owner_addr = signer::address_of(current_owner);
        assert!(exists<UpdateRateCapability>(current_owner_addr), EINVALID_OWNER);
        
        if (exists<UpdateRateCapabilityTransferInfo>(current_owner_addr)) {
            let transferInfo = borrow_global_mut<UpdateRateCapabilityTransferInfo>(current_owner_addr);
            transferInfo.new_owner_addr = new_owner_addr;
        } else {
            move_to<UpdateRateCapabilityTransferInfo>(current_owner, UpdateRateCapabilityTransferInfo { new_owner_addr });
        }
    }

    public entry fun get_change_rate(new_owner: &signer, current_owner_addr: address) acquires UpdateRateCapability, UpdateRateCapabilityTransferInfo {
        assert!(exists<UpdateRateCapability>(current_owner_addr), EINVALID_VALUE);
        assert!(exists<UpdateRateCapabilityTransferInfo>(current_owner_addr), EINVALID_VALUE);

        let new_owner_addr = signer::address_of(new_owner);

        let transferInfo = borrow_global<UpdateRateCapabilityTransferInfo>(current_owner_addr);
        assert!(transferInfo.new_owner_addr == new_owner_addr, EINVALID_VALUE);

        move_from<UpdateRateCapabilityTransferInfo>(current_owner_addr);
        move_from<UpdateRateCapability>(current_owner_addr);

        move_to<UpdateRateCapability>(new_owner, UpdateRateCapability { owner_addr: new_owner_addr });
        move_to<UpdateRateCapabilityTransferInfo>(new_owner, UpdateRateCapabilityTransferInfo { new_owner_addr });
    }

    public entry fun purchase_bond<CoinType>(buyer: &signer, amount: u64, pool_addr: address) acquires PoolInfo, BondInfo, Investors {
        assert!(exists<PoolInfo>(pool_addr), EPOOL_NOT_INITIALIZED);
        check_bond_coin_type<CoinType>(pool_addr);

        let pool_info = borrow_global_mut<PoolInfo>(pool_addr);
        assert!(pool_info.bond_in_status == true, EPOOL_PAUSED);
        assert!(pool_info.bond_in_remaining >= amount, EEXCEED_BOND_IN_REMAINING);
        update_conversion_rate(pool_info);
        let buyer_addr = signer::address_of(buyer);
        let current_time = timestamp::now_seconds();
        assert!(current_time >= pool_info.start_time, ENOT_YET_START);
        assert!(current_time <= pool_info.end_time, EENDED);

        
        if (!exists<BondInfo>(buyer_addr)) {
            let t = borrow_global_mut<Investors<u64, address>>(pool_addr);
            let key = table_with_length::length(&t.t);
            table_with_length::add(&mut t.t, key, buyer_addr);
            // let pending_amount = (amount as u128) * (pool_info.conversion_rate as u128) / (pool_info.conversion_precision as u128);
            let pending_amount = ((amount as u128) * (pool_info.conversion_rate as u128) / (pool_info.conversion_precision as u128)) * (pool_info.bonus_rate as u128) / (pool_info.bonus_precision as u128);
            let fee = pending_amount * (pool_info.fee_rate as u128) / FEE_PRECISION;
            let amount_remaining = pending_amount - fee;
            let amount_per_epoch = amount_remaining / (pool_info.lock_epoch as u128);
            pool_info.total_fee = pool_info.total_fee + fee;
            move_to<BondInfo>(buyer, BondInfo {      
                amount_remaining: (amount_remaining as u64),
                amount_per_epoch: (amount_per_epoch as u64),
                epoch_remaining: pool_info.lock_epoch,
                last_update: current_time,
                amount_distributed: 0,
            });
        } else {
            let bond_info = borrow_global_mut<BondInfo>(buyer_addr);
            
            let previous_amount = (bond_info.amount_remaining as u128);
            let pending_amount = ((amount as u128) * (pool_info.conversion_rate as u128) / (pool_info.conversion_precision as u128)) * (pool_info.bonus_rate as u128) / (pool_info.bonus_precision as u128);
            let fee = pending_amount * (pool_info.fee_rate as u128) / FEE_PRECISION;
            let amount_remaining = previous_amount + pending_amount - fee;
            let amount_per_epoch = amount_remaining / (pool_info.lock_epoch as u128);
            bond_info.amount_remaining = (amount_remaining as u64);
            bond_info.amount_per_epoch = (amount_per_epoch as u64);
            bond_info.epoch_remaining = pool_info.lock_epoch;
            bond_info.last_update = current_time;
            pool_info.total_fee = pool_info.total_fee + fee;
        };
        coin::transfer<CoinType>(buyer, COLLECT_ADDRESS, amount);
        // coin::transfer<CoinType>(buyer, pool_addr, amount);
        pool_info.bond_in_remaining = pool_info.bond_in_remaining - amount;
        pool_info.total_bond_in_amount = pool_info.total_bond_in_amount + (amount as u128);
    }

    public entry fun harvest<CoinType>(buyer: &signer, pool_addr: address) acquires PoolInfo, BondInfo {
        assert!(exists<PoolInfo>(pool_addr), EPOOL_NOT_INITIALIZED);
        check_reward_coin_type<CoinType>(pool_addr);
        let buyer_addr = signer::address_of(buyer);
        assert!(exists<BondInfo>(buyer_addr), ENO_RECORD_FOUND);
        if (!coin::is_account_registered<CoinType>(buyer_addr)) {
            managed_coin::register<CoinType>(buyer);
        };
        let pool_info = borrow_global_mut<PoolInfo>(pool_addr);
        let bond_info = borrow_global_mut<BondInfo>(buyer_addr); 
        assert!(bond_info.amount_remaining > 0, EINSUFFICIENT_BALANCE);
        let current_time = timestamp::now_seconds();        
        let passed_seconds = current_time - bond_info.last_update;
        let passed_epoch = passed_seconds / pool_info.epoch_time;
        let pending_reward = 0;
        if (passed_epoch >= 1){
            if (passed_epoch >= bond_info.epoch_remaining){
                pending_reward = bond_info.amount_remaining;
                bond_info.amount_remaining = 0;
                bond_info.amount_per_epoch = 0;
                bond_info.epoch_remaining = 0;
            } else {
                pending_reward = (bond_info.amount_per_epoch * passed_epoch);
                bond_info.amount_remaining = bond_info.amount_remaining - pending_reward;
                bond_info.epoch_remaining = bond_info.epoch_remaining - passed_epoch;
            };
            bond_info.last_update = bond_info.last_update + (passed_epoch * pool_info.epoch_time);
        };
        assert!(pending_reward > 0, EINSUFFICIENT_BALANCE);
        let pool_account_from_cap = account::create_signer_with_capability(&pool_info.resource_cap);
        coin::transfer<CoinType>(&pool_account_from_cap, buyer_addr, (pending_reward as u64));
        bond_info.amount_distributed = bond_info.amount_distributed + (pending_reward as u64);
        pool_info.distributed_reward = pool_info.distributed_reward + (pending_reward as u128);
        
    }

    public entry fun fund_reward<CoinType>(owner: &signer, amount: u64, pool_addr: address) acquires PoolInfo {
        assert!(exists<PoolInfo>(pool_addr), EPOOL_NOT_INITIALIZED);
        if (!coin::is_account_registered<CoinType>(pool_addr)) {
            let pool_info = borrow_global_mut<PoolInfo>(pool_addr);
            let pool_account_from_cap = account::create_signer_with_capability(&pool_info.resource_cap);
            managed_coin::register<CoinType>(&pool_account_from_cap);
        };
        coin::transfer<CoinType>(owner, pool_addr, amount);
    }

    public entry fun owner_withdraw<CoinType>(owner: &signer, amount: u64, pool_addr: address) acquires PoolInfo {
        assert!(exists<PoolInfo>(pool_addr), EPOOL_NOT_INITIALIZED);
        check_owner_address(owner);
        let pool_info = borrow_global_mut<PoolInfo>(pool_addr);        
        let pool_account_from_cap = account::create_signer_with_capability(&pool_info.resource_cap);
        coin::transfer<CoinType>(&pool_account_from_cap, signer::address_of(owner), amount);
    }

    // public entry fun withdraw_bond_coin<CoinType>(owner: &signer, amount: u64, pool_addr: address) acquires PoolInfo {
    //     assert!(exists<PoolInfo>(pool_addr), EPOOL_NOT_INITIALIZED);
    //     check_owner_address(owner);
    //     let pool_info = borrow_global_mut<PoolInfo>(pool_addr);    
    //     let pool_account_from_cap = account::create_signer_with_capability(&pool_info.resource_cap);
    //     coin::transfer<CoinType>(&pool_account_from_cap, signer::address_of(owner), amount);
    // }


    public entry fun edit_end_time(owner: &signer, new_end_time: u64, pool_addr: address) acquires PoolInfo {
        assert!(exists<PoolInfo>(pool_addr), EPOOL_NOT_INITIALIZED);
        check_owner_address(owner);
        let current_time = timestamp::now_seconds();
        let pool_info = borrow_global_mut<PoolInfo>(pool_addr);    
        assert!(new_end_time >= current_time, EMUST_BE_AFTER_CURRENT_TIME);
        pool_info.end_time = new_end_time;
        update_conversion_rate(pool_info)
    }

    public entry fun update_new_bond_info(owner: &signer, new_conversion_rate: u64, new_conversion_precision: u64, new_bonus_rate: u64, new_bonus_precision: u64, new_epoch_time: u64, new_lock_epoch: u64, new_conversion_rate_start_time: u64, pool_addr: address) acquires PoolInfo {
        // check_update_rate_address(owner);
        check_owner_address(owner);
        let current_time = timestamp::now_seconds();
        assert!(exists<PoolInfo>(pool_addr), EPOOL_NOT_INITIALIZED);
        assert!(new_conversion_rate_start_time >= current_time, EINVALID_TIME);
        assert!(new_conversion_rate >= new_conversion_precision, EINVALID_PRECISION);
        let pool_info = borrow_global_mut<PoolInfo>(pool_addr);
        update_conversion_rate(pool_info);
        pool_info.new_conversion_rate = new_conversion_rate;
        pool_info.new_conversion_precision = new_conversion_precision;
        pool_info.new_bonus_rate = new_bonus_rate;
        pool_info.new_bonus_precision = new_bonus_precision;
        pool_info.new_epoch_time = new_epoch_time;
        pool_info.new_lock_epoch = new_lock_epoch;
        pool_info.new_conversion_rate_start_time = new_conversion_rate_start_time;
        update_conversion_rate(pool_info)
    }

    fun update_conversion_rate(pool_info: &mut PoolInfo) {
        let current_time = timestamp::now_seconds();
        if(pool_info.new_conversion_rate_start_time >= current_time){
            pool_info.conversion_rate = pool_info.new_conversion_rate;
            pool_info.conversion_precision = pool_info.new_conversion_precision;
            pool_info.bonus_rate = pool_info.new_bonus_rate;
            pool_info.bonus_precision = pool_info.new_bonus_precision;
            pool_info.lock_epoch = pool_info.new_lock_epoch;
            pool_info.epoch_time = pool_info.new_epoch_time;
            pool_info.new_conversion_rate_start_time = 0;
        } 
    }

    public entry fun update_bond_rate(owner: &signer, new_conversion_rate: u64, new_conversion_precision: u64, new_bonus_rate: u64, new_bonus_precision: u64, new_epoch_time: u64, new_lock_epoch: u64, pool_addr: address) acquires PoolInfo {
        check_update_rate_address(owner);
        // check_owner_address(owner);
        assert!(exists<PoolInfo>(pool_addr), EPOOL_NOT_INITIALIZED);
        assert!(new_conversion_rate >= new_conversion_precision, EINVALID_PRECISION);
        let pool_info = borrow_global_mut<PoolInfo>(pool_addr);
        pool_info.conversion_rate = new_conversion_rate;
        pool_info.conversion_precision = new_conversion_precision;
        pool_info.bonus_rate = new_bonus_rate;
        pool_info.bonus_precision = new_bonus_precision;
        pool_info.lock_epoch = new_lock_epoch ;
        pool_info.epoch_time = new_epoch_time;
        pool_info.new_conversion_rate_start_time = 0;
    }

    public entry fun update_fee_rate(owner: &signer, new_fee_rate: u64, pool_addr: address) acquires PoolInfo {
        check_update_rate_address(owner);
        // check_owner_address(owner);
        assert!(exists<PoolInfo>(pool_addr), EPOOL_NOT_INITIALIZED);
        assert!((new_fee_rate as u128) <= FEE_PRECISION, EINVALID_FEE_RATE);
        let pool_info = borrow_global_mut<PoolInfo>(pool_addr);
        pool_info.fee_rate = new_fee_rate;
    }

    public entry fun update_bond_in_remaining(owner: &signer, new_bond_in_remaining: u64, pool_addr: address) acquires PoolInfo {
        let owner_addr = signer::address_of(owner);
        if (exists<OwnerCapability>(owner_addr) || exists<UpdateRateCapability>(owner_addr)){
            assert!(exists<PoolInfo>(pool_addr), EPOOL_NOT_INITIALIZED);
            let pool_info = borrow_global_mut<PoolInfo>(pool_addr);
            pool_info.bond_in_remaining = new_bond_in_remaining;
        };
    }

    public entry fun update_bond_in_status(owner: &signer, new_bond_in_status: bool, pool_addr: address) acquires PoolInfo {
        let owner_addr = signer::address_of(owner);
        if (exists<OwnerCapability>(owner_addr) || exists<UpdateRateCapability>(owner_addr)){
            assert!(exists<PoolInfo>(pool_addr), EPOOL_NOT_INITIALIZED);
            let pool_info = borrow_global_mut<PoolInfo>(pool_addr);
            pool_info.bond_in_status = new_bond_in_status;
        };
    }

    fun check_owner_address(owner: &signer) {
        let owner_addr = signer::address_of(owner);
        assert!(exists<OwnerCapability>(owner_addr), EINVALID_OWNER);
    }

    fun check_update_rate_address(owner: &signer) {
        let owner_addr = signer::address_of(owner);
        assert!(exists<UpdateRateCapability>(owner_addr), EINVALID_UPDATE_RATE_OWNER);
    }

    public entry fun check_reward_coin_type<CoinType>(pool_addr:address)acquires PoolInfo {    
        let pool_info = borrow_global_mut<PoolInfo>(pool_addr);  
        let reward_coin_address = pool_info.reward_coin_address;
        let reward_coin_module_name = pool_info.reward_coin_module_name;
        let reward_coin_struct_name = pool_info.reward_coin_struct_name;
        assert!(reward_coin_address == type_info::account_address(&type_info::type_of<CoinType>()), EINVALID_COIN);
        assert!(reward_coin_module_name == type_info::module_name(&type_info::type_of<CoinType>()), EINVALID_COIN);
        assert!(reward_coin_struct_name == type_info::struct_name(&type_info::type_of<CoinType>()), EINVALID_COIN);
    }

    public entry fun check_bond_coin_type<CoinType>(pool_addr:address)acquires PoolInfo {
        let pool_info = borrow_global_mut<PoolInfo>(pool_addr);  
        let stake_coin_address = pool_info.stake_coin_address;
        let stake_coin_module_name = pool_info.stake_coin_module_name;
        let stake_coin_struct_name = pool_info.stake_coin_struct_name;
        assert!(stake_coin_address == type_info::account_address(&type_info::type_of<CoinType>()), EINVALID_COIN);
        assert!(stake_coin_module_name == type_info::module_name(&type_info::type_of<CoinType>()), EINVALID_COIN);
        assert!(stake_coin_struct_name == type_info::struct_name(&type_info::type_of<CoinType>()), EINVALID_COIN);
    }

    // for api
    public fun balance(user: address): u64 acquires BondInfo {
        let user_remaining = borrow_global<BondInfo>(user).amount_remaining;
        let user_claimed = borrow_global<BondInfo>(user).amount_distributed;
        user_remaining + user_claimed
    }

    public fun get_investor_address_by_key(key: u64, pool_addr: address):address acquires Investors{
        let t = borrow_global<Investors<u64, address>>(pool_addr);
        *table_with_length::borrow(&t.t, key)
    }

    public fun get_investor_length(pool_addr: address):u64 acquires Investors{
        let t = borrow_global<Investors<u64, address>>(pool_addr);
        table_with_length::length(&t.t)
    }
    

    #[test_only]
    struct BondCoin {}
    struct RewardCoin {}
    // use aptos_std::debug;
    // use 0x1::string::String;

    // BondInfo PoolInfo
    #[test(alice = @0x123, bondModule = @aptos_launch, system=@0x1, newOwner = @0x3, newRate = @0x4)]
    public entry fun n2n(alice: signer, bondModule: signer, system: signer, newOwner:signer, newRate:signer) acquires PoolInfo, BondInfo, OwnerCapabilityTransferInfo, OwnerCapability, UpdateRateCapability, UpdateRateCapabilityTransferInfo, Investors{
        let alice_addr = signer::address_of(&alice);
        let bond_module_addr = signer::address_of(&bondModule);
        let new_owner_addr = signer::address_of(&newOwner);
        let new_rate_addr = signer::address_of(&newRate);
        account::create_account_for_test(alice_addr);
        account::create_account_for_test(bond_module_addr);
        account::create_account_for_test(new_owner_addr);
        account::create_account_for_test(new_rate_addr);
        timestamp::set_time_has_started_for_testing(&system);
    
        // initialize coin
        managed_coin::initialize<BondCoin>(&bondModule, b"Bond Coin", b"BC", 8, false);
        managed_coin::initialize<RewardCoin>(&bondModule, b"Reward Coin", b"RC", 8, false);

        // register coin
        managed_coin::register<BondCoin>(&alice);
        managed_coin::register<BondCoin>(&bondModule);
        managed_coin::register<BondCoin>(&newOwner);
        managed_coin::register<RewardCoin>(&bondModule);
        managed_coin::register<RewardCoin>(&newOwner);
        

        // mint coin
        managed_coin::mint<BondCoin>(&bondModule, alice_addr, 40000000000000);
        assert!(coin::balance<BondCoin>(alice_addr) == 40000000000000, EINVALID_BALANCE);
        managed_coin::mint<RewardCoin>(&bondModule, new_owner_addr, 20000000000000);
        assert!(coin::balance<RewardCoin>(new_owner_addr) == 20000000000000, EINVALID_BALANCE);

        // config
        let current_time = timestamp::now_seconds();
        let start_time = current_time + 100;
        let conversion_rate = 15;
        let conversion_precision = 10;
        let bonus_rate = 120;
        let bonus_precision = 100;
        let end_time = current_time + 500+10000;
        let lock_epoch = 10;
        let epoch_time = 5;
        let fee_rate = 100;
        let bond_in_status = true;
        // let bond_in_remaining = 100000001;
        let bond_in_remaining = 1000000000000;
        
        // init
        // initialize<CoinType1, CoinType2>(initializer: &signer, seeds: vector<u8>, start_time: u64, conversion_rate: u64, conversion_precision: u64, bonus_rate: u64, bonus_precision: u64,end_time: u64, lock_epoch: u64, epoch_time: u64, fee_rate: u64, bond_in_status: bool, bond_in_remaining: u64)
        initialize<BondCoin, RewardCoin>(&bondModule, b"bond-pool", start_time, conversion_rate, conversion_precision, bonus_rate, bonus_precision, end_time, lock_epoch, epoch_time, fee_rate, bond_in_status, bond_in_remaining);

        // transfer ownership fund, owner withdraw
        let pool_addr = account::create_resource_address(&@aptos_launch, b"bond-pool");
        transfer_ownership(&bondModule, new_owner_addr);
        get_ownership(&newOwner, bond_module_addr);
        check_owner_address(&newOwner);

        transfer_change_rate(&bondModule, new_rate_addr);
        get_change_rate(&newRate, bond_module_addr);
        check_update_rate_address(&newRate);


        fund_reward<RewardCoin>(&newOwner, 20000000000000, pool_addr);
        assert!(coin::balance<RewardCoin>(new_owner_addr) == 0, EINVALID_BALANCE);
        owner_withdraw<RewardCoin>(&newOwner, 10000000000000, pool_addr);
        assert!(coin::balance<RewardCoin>(pool_addr) == 10000000000000, EINVALID_BALANCE);

        // purchase
        timestamp::fast_forward_seconds(100);
        purchase_bond<BondCoin>(&alice, 100000000, pool_addr);
        assert!(coin::balance<BondCoin>(alice_addr) == 39999900000000, EINVALID_BALANCE);
        let alice_info = borrow_global_mut<BondInfo>(alice_addr);
        // debug::print<u64>(&alice_info.amount_remaining);
        assert!(alice_info.amount_remaining == 178200000, 0);
        assert!(alice_info.amount_per_epoch == 17820000, 1);
        assert!(alice_info.epoch_remaining == 10, 2);
        assert!(alice_info.last_update == current_time + 100, 3);
        let pool_info = borrow_global_mut<PoolInfo>(pool_addr);
        assert!(pool_info.bond_in_remaining == 1000000000000 -100000000, 99);
        assert!(pool_info.total_bond_in_amount == 100000000, 99);
        
        timestamp::fast_forward_seconds(10);
        harvest<RewardCoin>(&alice, pool_addr);
        let alice_info_10 = borrow_global_mut<BondInfo>(alice_addr);
        // // debug::print<u64>(&alice_info_10.amount_remaining);
        assert!(alice_info_10.amount_remaining == 178200000 - (17820000 * 2), 0);
        assert!(alice_info_10.amount_per_epoch == 17820000, 1);
        assert!(alice_info_10.epoch_remaining == 8, 2);
        assert!(alice_info_10.last_update == current_time + 100 + 10, 3);
        assert!(alice_info_10.amount_distributed == 17820000 * 2, 3);
        assert!(coin::balance<RewardCoin>(alice_addr) == 17820000 * 2, 4);

        //  public entry fun update_new_bond_info(owner: &signer, new_conversion_rate: u64, new_conversion_precision: u64, new_bonus_rate: u64, new_bonus_precision: u64, new_epoch_time: u64, new_lock_epoch: u64, new_conversion_rate_start_time: u64, pool_addr: address) 
        // update_new_bond_info(&newOwner, 20, 10, 130, 100, 15, 20, current_time+120, pool_addr);

        // update_bond_rate(owner: &signer, new_conversion_rate: u64, new_conversion_precision: u64, new_bonus_rate: u64, new_bonus_precision: u64, new_epoch_time: u64, new_lock_epoch: u64, pool_addr: address)
        update_bond_rate(&newRate, 20, 10, 130, 100, 15, 20, pool_addr);
        // update_fee_rate(&newOwner, 200, pool_addr);
        
        timestamp::fast_forward_seconds(30);
        // // // harvest<RewardCoin>(&alice, pool_addr);
        purchase_bond<BondCoin>(&alice, 300000000, pool_addr);
        let alice_info_30 = borrow_global_mut<BondInfo>(alice_addr);
        // debug::print<u64>(&alice_info_30.amount_remaining);
        assert!(alice_info_30.amount_remaining == 914760000, 0);
        // assert!(alice_info_30.amount_per_epoch == 45738000, 1);
        // debug::print<u64>(&alice_info_30.epoch_remaining);
        assert!(alice_info_30.epoch_remaining == 20, 2);
        assert!(alice_info_30.last_update == current_time + 100 + 40, 3);
        assert!(alice_info_30.amount_distributed == 17820000 * 2, 3);
        assert!(coin::balance<RewardCoin>(alice_addr) == 17820000 * 2, 4);
        
        timestamp::fast_forward_seconds(30);
        harvest<RewardCoin>(&alice, pool_addr);
        let alice_info_40 = borrow_global_mut<BondInfo>(alice_addr);
        // debug::print<u64>(&alice_info_40.amount_remaining);
        assert!(alice_info_40.amount_remaining == 914760000-(45738000*2), 0);
        assert!(alice_info_40.amount_per_epoch == 45738000, 1);
        assert!(alice_info_40.epoch_remaining == 18, 2);
        assert!(alice_info_40.last_update == current_time + 100 + 40 + 30, 3);
        assert!(alice_info_40.amount_distributed == 17820000 * 2 + 45738000 * 2, 3);
        assert!(coin::balance<RewardCoin>(alice_addr) == 17820000 * 2 + 45738000 * 2, 4);

        owner_withdraw<BondCoin>(&newOwner, 150000000, pool_addr);
        owner_withdraw<RewardCoin>(&newOwner, 50000000, pool_addr);
        assert!(coin::balance<BondCoin>(new_owner_addr) == 150000000, 4);
        assert!(coin::balance<BondCoin>(pool_addr) == 250000000, 4);
        assert!(coin::balance<RewardCoin>(new_owner_addr) == 10000000000000
        + 50000000, 4);
        // // let g = coin::balance<RewardCoin>(new_owner_addr);
        // //  debug::print<u64>(&g);
        assert!(coin::balance<RewardCoin>(pool_addr) == 10000000000000 - 50000000 - ((17820000 * 2)+(45738000*2)), 4);
        
        timestamp::fast_forward_seconds(500);
        harvest<RewardCoin>(&alice, pool_addr);
        let alice_info_540 = borrow_global_mut<BondInfo>(alice_addr);
        assert!(alice_info_540.amount_remaining == 0, 0);
        assert!(alice_info_540.amount_per_epoch == 0, 1);
        assert!(alice_info_540.epoch_remaining == 0, 2);
        assert!(alice_info_540.amount_distributed == 17820000 * 2 + 914760000, 2);
        assert!(coin::balance<RewardCoin>(alice_addr) == 17820000 * 2 + 914760000, 4);

        update_bond_in_remaining(&newRate, 2000, pool_addr);
        update_bond_in_status(&newRate, false, pool_addr);
        let pool_info_ur = borrow_global_mut<PoolInfo>(pool_addr);
        assert!(pool_info_ur.bond_in_remaining == 2000, 99);
        assert!(pool_info_ur.bond_in_status == false, 99);

        update_bond_in_remaining(&newOwner, 5000, pool_addr);
        update_bond_in_status(&newOwner, true, pool_addr);
        let pool_info_ow = borrow_global_mut<PoolInfo>(pool_addr);
        assert!(pool_info_ow.bond_in_remaining == 5000, 99);
        assert!(pool_info_ow.bond_in_status == true, 99);

        // let pool_info = borrow_global_mut<PoolInfo>(pool_addr);
        // assert!(pool_info.conversion_rate == 20, 0);
        // assert!(pool_info.conversion_precision == 10, 1);
        // assert!(pool_info.new_conversion_rate_start_time == 0, 2);
        // assert!(pool_info.last_update == current_time + 100 + 60, 3);
        // assert!(coin::balance<RewardCoin>(alice_addr) == 15000000 * 10, 4);
        managed_coin::mint<BondCoin>(&bondModule, bond_module_addr, 40000000000000);
        managed_coin::mint<BondCoin>(&bondModule, new_owner_addr, 40000000000000);
        
        assert!(get_investor_length(pool_addr) ==  1, 4);
        purchase_bond<BondCoin>(&alice, 1, pool_addr);
        assert!(get_investor_length(pool_addr) ==  1, 4);

        purchase_bond<BondCoin>(&bondModule, 1, pool_addr);
        assert!(get_investor_length(pool_addr) ==  2, 4);
        purchase_bond<BondCoin>(&bondModule, 1, pool_addr);
        assert!(get_investor_length(pool_addr) ==  2, 4);
        purchase_bond<BondCoin>(&alice, 1, pool_addr);
        assert!(get_investor_length(pool_addr) ==  2, 4);

        purchase_bond<BondCoin>(&newOwner, 1, pool_addr);
        assert!(get_investor_length(pool_addr) ==  3, 4);
        purchase_bond<BondCoin>(&bondModule, 1, pool_addr);
        assert!(get_investor_length(pool_addr) ==  3, 4);

        assert!(get_investor_address_by_key(0, pool_addr) ==  alice_addr, 4);
        assert!(get_investor_address_by_key(1, pool_addr) ==  bond_module_addr, 4);
        assert!(get_investor_address_by_key(2, pool_addr) ==  new_owner_addr, 4);

        
        
    }
}