#[test_only]
module anglerfish::pool_large_deposit_test;

use anglerfish::pool_test_suite::build_pool_test_suite;
use sui::balance::create_for_testing as create_balance_for_testing;
use sui::sui::SUI;
use sui::test_scenario;

const AUTHORITY: address = @0xAAA;
const USER_1: address = @0x001;
const TEST_POOL_RISK: u64 = 5000;

fun sui(amt: u64): u64 {
    amt * 1_000_000_000
}

#[test]
fun test_pool_deposit_redeem_shares() {
    let (mut scenario, clock, phase_info, mut pool_registry) = build_pool_test_suite(
        AUTHORITY,
    );

    scenario.next_tx(USER_1);
    {
        let balance = create_balance_for_testing<SUI>(sui(1_000_000_000));
        pool_registry.deposit<SUI>(
            &phase_info,
            TEST_POOL_RISK,
            sui::coin::from_balance(balance, scenario.ctx()),
            scenario.ctx(),
        );

        let pool = pool_registry.get_pool_by_risk_ratio<SUI>(TEST_POOL_RISK);
        assert!(pool.get_user_shares(USER_1) == sui(1_000_000_000));
        assert!(pool.get_reserves().value() == sui(1_000_000_000));
        assert!(pool.get_prize_reserves_value() == sui(500_000_000));
    };

    scenario.next_tx(USER_1);
    {
        let balance = create_balance_for_testing<SUI>(sui(10_000_000_000));
        pool_registry.deposit<SUI>(
            &phase_info,
            TEST_POOL_RISK,
            sui::coin::from_balance(balance, scenario.ctx()),
            scenario.ctx(),
        );

        let pool = pool_registry.get_pool_by_risk_ratio<SUI>(TEST_POOL_RISK);
        assert!(pool.get_user_shares(USER_1) == sui(11_000_000_000));
        assert!(pool.get_reserves().value() == sui(11_000_000_000));
        assert!(pool.get_prize_reserves_value() == sui(5_500_000_000));
    };

    test_scenario::return_shared(phase_info);
    test_scenario::return_shared(pool_registry);
    clock.destroy_for_testing();
    scenario.end();
}
