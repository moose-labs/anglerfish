#[test_only]
module anglerfish::pool_test;

use anglerfish::pool;
use anglerfish::pool_test_suite::build_liquidity_providing_phase_pool_test_suite;
use sui::balance::create_for_testing as create_balance_for_testing;
use sui::sui::SUI;
use sui::test_scenario;

const AUTHORITY: address = @0xAAA;
const USER_1: address = @0x001;
const USER_2: address = @0x002;

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
    let (
        mut scenario,
        clock,
        phase_info,
        prize_pool,
        lounge_registry,
        mut pool_registry,
    ) = build_liquidity_providing_phase_pool_test_suite(
        AUTHORITY,
    );

    scenario.next_tx(USER_1);
    {
        let mut balance = create_balance_for_testing<SUI>(100);
        let deposit_coin = sui::coin::take(&mut balance, 0, scenario.ctx());

        pool_registry.deposit<SUI>(
            &phase_info,
            TEST_POOL_RISK,
            deposit_coin,
            scenario.ctx(),
        );

        balance.destroy_for_testing();
    };

    test_scenario::return_shared(pool_registry);
    test_scenario::return_shared(lounge_registry);
    test_scenario::return_shared(prize_pool);
    test_scenario::return_shared(phase_info);
    clock.destroy_for_testing();
    scenario.end();
}

#[test]
#[expected_failure(abort_code = pool::ErrorInsufficientShares)]
fun test_cannot_redeem_zero_shares_amount() {
    let (
        mut scenario,
        clock,
        phase_info,
        prize_pool,
        lounge_registry,
        mut pool_registry,
    ) = build_liquidity_providing_phase_pool_test_suite(
        AUTHORITY,
    );

    scenario.next_tx(USER_1);
    {
        let balance = create_balance_for_testing<SUI>(100);
        pool_registry.deposit<SUI>(
            &phase_info,
            TEST_POOL_RISK,
            sui::coin::from_balance(balance, scenario.ctx()),
            scenario.ctx(),
        );
    };

    scenario.next_tx(USER_1);
    {
        let coin = pool_registry.redeem<SUI>(
            &phase_info,
            TEST_POOL_RISK,
            0,
            scenario.ctx(),
        );
        coin.burn_for_testing();
    };

    test_scenario::return_shared(phase_info);
    test_scenario::return_shared(prize_pool);
    test_scenario::return_shared(lounge_registry);
    test_scenario::return_shared(pool_registry);
    clock.destroy_for_testing();
    scenario.end();
}

#[test]
#[expected_failure(abort_code = pool::ErrorTooLargeToRedeem)]
fun test_cannot_redeem_greater_than_deposit() {
    let (
        mut scenario,
        clock,
        phase_info,
        prize_pool,
        lounge_registry,
        mut pool_registry,
    ) = build_liquidity_providing_phase_pool_test_suite(
        AUTHORITY,
    );

    scenario.next_tx(USER_1);
    {
        let balance = create_balance_for_testing<SUI>(100);
        pool_registry.deposit<SUI>(
            &phase_info,
            TEST_POOL_RISK,
            sui::coin::from_balance(balance, scenario.ctx()),
            scenario.ctx(),
        );
    };

    scenario.next_tx(USER_1);
    {
        let coin = pool_registry.redeem<SUI>(
            &phase_info,
            TEST_POOL_RISK,
            200,
            scenario.ctx(),
        );
        coin.burn_for_testing();
    };

    test_scenario::return_shared(phase_info);
    test_scenario::return_shared(prize_pool);
    test_scenario::return_shared(lounge_registry);
    test_scenario::return_shared(pool_registry);
    clock.destroy_for_testing();
    scenario.end();
}

#[test]
fun test_pool_deposit_redeem_shares() {
    let (
        mut scenario,
        clock,
        phase_info,
        prize_pool,
        lounge_registry,
        mut pool_registry,
    ) = build_liquidity_providing_phase_pool_test_suite(
        AUTHORITY,
    );

    // First user deposit, should get 1:1 share
    scenario.next_tx(USER_1);
    {
        let balance = create_balance_for_testing<SUI>(100);
        pool_registry.deposit<SUI>(
            &phase_info,
            TEST_POOL_RISK,
            sui::coin::from_balance(balance, scenario.ctx()),
            scenario.ctx(),
        );

        let pool = pool_registry.get_pool_by_risk_ratio<SUI>(TEST_POOL_RISK);
        assert!(pool.get_user_shares(USER_1) == 100);
        assert!(pool.get_reserves().value() == 100);
        assert!(pool.get_prize_reserves_value() == 50); // 50% of 100
    };

    // Add fee to pool for testing
    scenario.next_tx(AUTHORITY);
    {
        let balance = create_balance_for_testing<SUI>(100);

        let pool = pool_registry.get_pool_by_risk_ratio_mut<SUI>(TEST_POOL_RISK);
        pool.deposit_fee(sui::coin::from_balance(balance, scenario.ctx()));
        assert!(pool.get_cumulative_fees() == 100);
    };

    // Second user deposit, should get != 1:1 share
    scenario.next_tx(USER_2);
    {
        let balance = create_balance_for_testing<SUI>(100);
        pool_registry.deposit<SUI>(
            &phase_info,
            TEST_POOL_RISK,
            sui::coin::from_balance(balance, scenario.ctx()),
            scenario.ctx(),
        );

        // check user shares
        // user_share_minted = user_deposit_amount / total_reserves_value * total_shares
        let pool = pool_registry.get_pool_by_risk_ratio<SUI>(TEST_POOL_RISK);
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
        let pool = pool_registry.get_pool_by_risk_ratio_mut<SUI>(TEST_POOL_RISK);
        pool.deposit_fee(sui::coin::from_balance(balance, scenario.ctx()));
        assert!(pool.get_cumulative_fees() == 200);
    };

    // validate user shares (share should be the same since deposited)
    {
        let pool = pool_registry.get_pool_by_risk_ratio<SUI>(TEST_POOL_RISK);
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
        let pool = pool_registry.get_pool_by_risk_ratio<SUI>(TEST_POOL_RISK);
        let shares_amount = pool.get_user_shares(USER_1);

        let redeem_coin = pool_registry.redeem<SUI>(
            &phase_info,
            TEST_POOL_RISK,
            shares_amount,
            scenario.ctx(),
        );

        let pool = pool_registry.get_pool_by_risk_ratio<SUI>(TEST_POOL_RISK);
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
        let pool = pool_registry.get_pool_by_risk_ratio<SUI>(TEST_POOL_RISK);
        let shares_amount = pool.get_user_shares(USER_2);

        let redeem_coin = pool_registry.redeem<SUI>(
            &phase_info,
            TEST_POOL_RISK,
            shares_amount,
            scenario.ctx(),
        );

        let pool = pool_registry.get_pool_by_risk_ratio<SUI>(TEST_POOL_RISK);
        assert!(pool.get_user_shares(USER_2) == 0);
        assert!(redeem_coin.value() == 134);

        assert!(pool.get_reserves().value() == 0);
        assert!(pool.get_total_shares() == 0);
        assert!(pool.get_prize_reserves_value() == 0);

        redeem_coin.burn_for_testing();
    };

    test_scenario::return_shared(phase_info);
    test_scenario::return_shared(prize_pool);
    test_scenario::return_shared(lounge_registry);
    test_scenario::return_shared(pool_registry);
    clock.destroy_for_testing();
    scenario.end();
}

#[test]
fun test_get_total_reserves_value() {
    let (
        mut scenario,
        clock,
        phase_info,
        prize_pool,
        lounge_registry,
        mut pool_registry,
    ) = build_liquidity_providing_phase_pool_test_suite(
        AUTHORITY,
    );

    scenario.next_tx(USER_1);
    {
        let balance = create_balance_for_testing<SUI>(200);
        pool_registry.deposit<SUI>(
            &phase_info,
            2000,
            sui::coin::from_balance(balance, scenario.ctx()),
            scenario.ctx(),
        );

        let balance = create_balance_for_testing<SUI>(500);
        pool_registry.deposit<SUI>(
            &phase_info,
            5000,
            sui::coin::from_balance(balance, scenario.ctx()),
            scenario.ctx(),
        );
    };

    {
        assert!(pool_registry.get_total_reserves_value<SUI>() == 700);
    };

    test_scenario::return_shared(phase_info);
    test_scenario::return_shared(prize_pool);
    test_scenario::return_shared(lounge_registry);
    test_scenario::return_shared(pool_registry);
    clock.destroy_for_testing();
    scenario.end();
}
