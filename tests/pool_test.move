#[test_only]
module red_ocean::pool_test;

use red_ocean::base_test_suite::build_base_test_suite;
use red_ocean::phase::PhaseInfo;
use red_ocean::phase_test_suite::build_phase_test_suite;
use red_ocean::pool::{Self, PoolCap, PoolFactory};
use red_ocean::pool_test_suite::build_pool_test_suite;
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
// cannot create pool with same risk ratio (duplicate pool)

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
        let phase_info = scenario.take_shared<PhaseInfo>();
        let pool_cap = scenario.take_from_sender<PoolCap>();

        pool_cap.create_pool<Coin<SUI>>(
            &mut pool_factory,
            &phase_info,
            10001,
            scenario.ctx(),
        );

        scenario.return_to_sender(pool_cap);
        test_scenario::return_shared(phase_info);
        test_scenario::return_shared(pool_factory);
    };

    clock.destroy_for_testing();
    scenario.end();
}

#[test]
fun test_pool_can_only_created_by_authority() {
    let (mut scenario, clock, phase_info) = build_phase_test_suite(AUTHORITY);

    scenario.next_tx(AUTHORITY);
    {
        let mut pool_factory = scenario.take_shared<PoolFactory>();
        let pool_cap = scenario.take_from_sender<PoolCap>();

        pool_cap.create_pool<SUI>(&mut pool_factory, &phase_info, 5000, scenario.ctx());
        pool_cap.create_pool<SUI>(&mut pool_factory, &phase_info, 10000, scenario.ctx());

        // Pool 5000
        {
            let pool = pool_factory.get_pool_by_risk_ratio<SUI>(5000);
            assert!(pool.get_deposit_enabled() == false);
        };

        {
            // try enable depositing
            pool_cap.set_deposit_enabled<SUI>(&mut pool_factory, 5000, true);
            let pool = pool_factory.get_pool_by_risk_ratio<SUI>(5000);
            assert!(pool.get_deposit_enabled());
        };

        // Pool factory getter
        {
            let pool_risk_ratios = pool_factory.get_pool_risk_ratios();
            assert!(pool_risk_ratios.length() == 2);

            let total_risk_ratio_bps = pool_factory.get_total_risk_ratio_bps();
            assert!(total_risk_ratio_bps == 15000);
        };

        scenario.return_to_sender(pool_cap);
        test_scenario::return_shared(pool_factory);
    };

    clock.destroy_for_testing();
    test_scenario::return_shared(phase_info);
    scenario.end();
}

#[test]
#[expected_failure(abort_code = pool::ErrorPoolAlreadyCreated)]
fun test_cannot_create_pool_with_same_risk() {
    let (mut scenario, clock, phase_info) = build_phase_test_suite(AUTHORITY);

    scenario.next_tx(AUTHORITY);
    {
        let mut pool_factory = scenario.take_shared<PoolFactory>();
        let pool_cap = scenario.take_from_sender<PoolCap>();

        pool_cap.create_pool<SUI>(&mut pool_factory, &phase_info, 5000, scenario.ctx());
        pool_cap.create_pool<SUI>(&mut pool_factory, &phase_info, 5000, scenario.ctx());

        scenario.return_to_sender(pool_cap);
        test_scenario::return_shared(pool_factory);
    };

    clock.destroy_for_testing();
    test_scenario::return_shared(phase_info);
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

const TEST_POOL_RISK: u64 = 5000;

#[test]
#[expected_failure(abort_code = pool::ErrorTooSmallToMint)]
fun test_cannot_deposit_zero_coin() {
    let (mut scenario, clock, phase_info, mut pool_factory) = build_pool_test_suite(AUTHORITY);

    scenario.next_tx(USER_1);
    {
        let pool = pool_factory.get_pool_by_risk_ratio_mut<SUI>(TEST_POOL_RISK);

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
#[expected_failure(abort_code = pool::ErrorInsufficientShares)]
fun test_cannot_redeem_zero_shares_amount() {
    let (mut scenario, clock, phase_info, mut pool_factory) = build_pool_test_suite(
        AUTHORITY,
    );

    let pool = pool_factory.get_pool_by_risk_ratio_mut<SUI>(TEST_POOL_RISK);

    scenario.next_tx(USER_1);
    {
        let balance = create_balance_for_testing<SUI>(100);
        pool.deposit<SUI>(
            &phase_info,
            sui::coin::from_balance(balance, scenario.ctx()),
            scenario.ctx(),
        );
    };

    scenario.next_tx(USER_1);
    {
        let coin = pool.redeem<SUI>(
            &phase_info,
            0,
            scenario.ctx(),
        );
        coin.burn_for_testing();
    };

    test_scenario::return_shared(phase_info);
    test_scenario::return_shared(pool_factory);
    clock.destroy_for_testing();
    scenario.end();
}

#[test]
#[expected_failure(abort_code = pool::ErrorTooLargeToRedeem)]
fun test_cannot_redeem_greater_than_deposit() {
    let (mut scenario, clock, phase_info, mut pool_factory) = build_pool_test_suite(
        AUTHORITY,
    );

    let pool = pool_factory.get_pool_by_risk_ratio_mut<SUI>(TEST_POOL_RISK);

    scenario.next_tx(USER_1);
    {
        let balance = create_balance_for_testing<SUI>(100);
        pool.deposit<SUI>(
            &phase_info,
            sui::coin::from_balance(balance, scenario.ctx()),
            scenario.ctx(),
        );
    };

    scenario.next_tx(USER_1);
    {
        let coin = pool.redeem<SUI>(
            &phase_info,
            200,
            scenario.ctx(),
        );
        coin.burn_for_testing();
    };

    test_scenario::return_shared(phase_info);
    test_scenario::return_shared(pool_factory);
    clock.destroy_for_testing();
    scenario.end();
}

#[test]
fun test_pool_deposit_redeem_shares() {
    let (mut scenario, clock, phase_info, mut pool_factory) = build_pool_test_suite(
        AUTHORITY,
    );

    let pool = pool_factory.get_pool_by_risk_ratio_mut<SUI>(TEST_POOL_RISK);

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
        pool.deposit_fee(sui::coin::from_balance(balance, scenario.ctx()));
        assert!(pool.get_cumulative_fees() == 100);
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

    // Add fee to pool
    scenario.next_tx(AUTHORITY);
    {
        let balance = create_balance_for_testing<SUI>(100);
        pool.deposit_fee(sui::coin::from_balance(balance, scenario.ctx()));
        assert!(pool.get_cumulative_fees() == 200);
    };

    // validate user shares (share should be the same since deposited)
    {
        let shares_amount = pool.get_user_shares(USER_1);
        assert!(shares_amount == 100);

        let shares_amount = pool.get_user_shares(USER_2);
        assert!(shares_amount == 50);

        assert!(pool.get_reserves().value() == 400);
        assert!(pool.get_total_shares() == 150);
        assert!(pool.get_prize_reserves_value() == 200); // 50% of 200
    };

    // Should able to redeem back with full shares
    // underlying = redeem_shares * total_reserves (400) / total_shares (150)
    scenario.next_tx(USER_1);
    {
        let shares_amount = pool.get_user_shares(USER_1);
        let redeem_coin = pool.redeem<SUI>(&phase_info, shares_amount, scenario.ctx());

        assert!(pool.get_user_shares(USER_1) == 0);
        assert!(redeem_coin.value() == 266);

        assert!(pool.get_reserves().value() == 134);
        assert!(pool.get_total_shares() == 50);
        assert!(pool.get_prize_reserves_value() == 67); // 50% of 134

        redeem_coin.burn_for_testing();
    };

    // Should able to redeem back with full shares
    scenario.next_tx(USER_2);
    {
        let shares_amount = pool.get_user_shares(USER_2);
        let redeem_coin = pool.redeem<SUI>(&phase_info, shares_amount, scenario.ctx());

        assert!(pool.get_user_shares(USER_2) == 0);
        assert!(redeem_coin.value() == 134);

        assert!(pool.get_reserves().value() == 0);
        assert!(pool.get_total_shares() == 0);
        assert!(pool.get_prize_reserves_value() == 0);

        redeem_coin.burn_for_testing();
    };

    test_scenario::return_shared(phase_info);
    test_scenario::return_shared(pool_factory);
    clock.destroy_for_testing();
    scenario.end();
}

#[test]
fun test_get_total_reserves_value() {
    let (mut scenario, clock, phase_info, mut pool_factory) = build_pool_test_suite(
        AUTHORITY,
    );

    scenario.next_tx(USER_1);
    {
        let pool = pool_factory.get_pool_by_risk_ratio_mut<SUI>(2000);
        let balance = create_balance_for_testing<SUI>(200);
        pool.deposit<SUI>(
            &phase_info,
            sui::coin::from_balance(balance, scenario.ctx()),
            scenario.ctx(),
        );

        let pool = pool_factory.get_pool_by_risk_ratio_mut<SUI>(5000);
        let balance = create_balance_for_testing<SUI>(500);
        pool.deposit<SUI>(
            &phase_info,
            sui::coin::from_balance(balance, scenario.ctx()),
            scenario.ctx(),
        );
    };

    {
        assert!(pool_factory.get_total_reserves_value<SUI>() == 700);
    };

    test_scenario::return_shared(phase_info);
    test_scenario::return_shared(pool_factory);
    clock.destroy_for_testing();
    scenario.end();
}
