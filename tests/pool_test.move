#[test_only]
module red_ocean::pool_test;

use red_ocean::pool::{Self, PoolCap, PoolFactory};
use red_ocean::test_suite::{build_base_test_suite, build_pool_test_suite};
use sui::balance::create_for_testing as create_balance_for_testing;
use sui::coin::Coin;
use sui::sui::SUI;
use sui::test_scenario;

const AUTHORITY: address = @0xAAA;
const USER_1: address = @0x001;
const USER_2: address = @0x002;
const UNAUTHORIZED: address = @0xFFF;

// Creator Scenarios
//
// capability cannot be taken by unauthorized user
// cannot create pool with risk ratio greater than 100%
// can create by pool creator

#[test]
#[expected_failure(abort_code = test_scenario::EEmptyInventory)]
fun test_capability_cannot_be_taken_by_unauthorized_user() {
    let (mut scenario, clock) = build_base_test_suite(AUTHORITY);

    scenario.next_tx(UNAUTHORIZED);
    {
        let pool_cap = scenario.take_from_sender<PoolCap>();

        scenario.return_to_sender(pool_cap)
    };

    clock.destroy_for_testing();
    scenario.end();
}

#[test]
#[expected_failure(abort_code = pool::ErrorPoolRiskRatioTooHigh)]
fun test_cannot_create_pool_with_risk_ratio_greater_than_100_percent() {
    let (mut scenario, clock) = build_base_test_suite(AUTHORITY);

    scenario.next_tx(AUTHORITY);
    {
        let mut pool_factory = scenario.take_shared<PoolFactory>();
        let pool_cap = scenario.take_from_sender<PoolCap>();

        pool_cap.create_pool<Coin<SUI>>(&mut pool_factory, 10001, scenario.ctx());

        scenario.return_to_sender(pool_cap);
        test_scenario::return_shared(pool_factory);
    };

    clock.destroy_for_testing();
    scenario.end();
}

#[test]
fun test_pool_can_only_created_by_authority() {
    let (mut scenario, clock) = build_base_test_suite(AUTHORITY);

    scenario.next_tx(AUTHORITY);
    {
        let mut pool_factory = scenario.take_shared<PoolFactory>();
        let pool_cap = scenario.take_from_sender<PoolCap>();

        pool_cap.create_pool<SUI>(&mut pool_factory, 5000, scenario.ctx());

        // check if pool is created
        let pool = pool_factory.get_pool_by_risk_ratio_mut<SUI>(5000);
        assert!(pool.get_deposit_enabled() == false);

        // try enable depositing
        pool_cap.set_deposit_enabled<SUI>(pool, true);
        assert!(pool.get_deposit_enabled());

        // check key is added to pool factory
        let pool_risk_ratios = pool_factory.get_pool_risk_ratios();
        assert!(pool_risk_ratios.size() == 1);

        scenario.return_to_sender(pool_cap);
        test_scenario::return_shared(pool_factory);
    };

    clock.destroy_for_testing();
    scenario.end();
}

#[test]
#[expected_failure(abort_code = pool::ErrorPoolAlreadyCreated)]
fun test_cannot_create_pool_with_same_risk() {
    let (mut scenario, clock) = build_base_test_suite(AUTHORITY);

    scenario.next_tx(AUTHORITY);
    {
        let mut pool_factory = scenario.take_shared<PoolFactory>();
        let pool_cap = scenario.take_from_sender<PoolCap>();

        pool_cap.create_pool<SUI>(&mut pool_factory, 5000, scenario.ctx());
        pool_cap.create_pool<SUI>(&mut pool_factory, 5000, scenario.ctx());

        scenario.return_to_sender(pool_cap);
        test_scenario::return_shared(pool_factory);
    };

    clock.destroy_for_testing();
    scenario.end();
}

// User Scenarios
//
// cannot deposit with zero coin
// (user1) can deposited (amount = share)
// can lending_pool transfer fund directly to pool balance
// (user2) can deposited and received their share (non 1:1)
// (user1) cannot redeem with zero amount
// (user1) cannot redeem greater than shared amount
// (user1) can redeem back with full shares
// (user2) can redeem back with full shares

#[test]
#[expected_failure(abort_code = pool::ErrorTooSmallToMint)]
fun test_cannot_deposit_zero_coin() {
    let (mut scenario, clock, phase_info, mut pool_factory) = build_pool_test_suite(AUTHORITY);

    scenario.next_tx(USER_1);
    {
        let pool = pool_factory.get_pool_by_risk_ratio_mut<SUI>(5000);

        let mut balance = create_balance_for_testing<SUI>(100);
        let deposit_coin = sui::coin::take(&mut balance, 0, scenario.ctx());

        pool.deposit<SUI>(&phase_info, deposit_coin, scenario.ctx());

        balance.destroy_for_testing();
    };

    test_scenario::return_shared(pool_factory);
    test_scenario::return_shared(phase_info);
    clock.destroy_for_testing();
    scenario.end();
}

#[test]
fun test_pool_shares() {
    let (mut scenario, clock, phase_info, mut pool_factory) = build_pool_test_suite(
        AUTHORITY,
    );

    let pool = pool_factory.get_pool_by_risk_ratio_mut<SUI>(5000);

    // First user deposit, should get 1:1 share
    scenario.next_tx(USER_1);
    {
        let balance = create_balance_for_testing<SUI>(100);
        pool.deposit<SUI>(
            &phase_info,
            sui::coin::from_balance(balance, scenario.ctx()),
            scenario.ctx(),
        );

        assert!(pool.get_user_shares(USER_1) == 100);
        assert!(pool.get_reserves().value() == 100);
        assert!(pool.get_prize_reserves_value() == 50); // 50% of 100
    };

    // Add fee to pool
    scenario.next_tx(AUTHORITY);
    {
        let balance = create_balance_for_testing<SUI>(100);
        pool.deposit_fee(sui::coin::from_balance(balance, scenario.ctx()))
    };

    // Second user deposit, should get != 1:1 share
    scenario.next_tx(USER_2);
    {
        let balance = create_balance_for_testing<SUI>(100);
        pool.deposit<SUI>(
            &phase_info,
            sui::coin::from_balance(balance, scenario.ctx()),
            scenario.ctx(),
        );

        // check user shares
        // user_share_minted = user_deposit_amount / total_reserves_value * total_shares
        assert!(pool.get_user_shares(USER_1) == 100);
        assert!(pool.get_user_shares(USER_2) == 50);
        assert!(pool.get_reserves().value() == 300);
        assert!(pool.get_prize_reserves_value() == 150); // 50% of 150
        assert!(pool.get_total_shares() == 150);
    };

    test_scenario::return_shared(phase_info);
    test_scenario::return_shared(pool_factory);
    clock.destroy_for_testing();
    scenario.end();
}
