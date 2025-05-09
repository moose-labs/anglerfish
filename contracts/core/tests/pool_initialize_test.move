#[test_only]
module anglerfish::pool_initialize_test;

use anglerfish::pool::{Self, PoolCap};
use anglerfish::pool_test_suite::build_pool_test_suite;
use sui::coin::Coin;
use sui::sui::SUI;
use sui::test_scenario;

const AUTHORITY: address = @0xAAA;
const UNAUTHORIZED: address = @0xFFF;

// Creator Scenarios
//
// capability cannot be taken by unauthorized user
// cannot create pool with risk ratio greater than 100%
// can only created by pool capability
// cannot create pool with same risk ratio (duplicate pool)

#[test]
#[expected_failure(abort_code = test_scenario::EEmptyInventory)]
fun test_capability_cannot_be_taken_by_unauthorized_user() {
    let (
        mut scenario,
        clock,
        phase_info,
        prize_pool,
        lounge_registry,
        pool_registry,
    ) = build_pool_test_suite(
        AUTHORITY,
    );

    scenario.next_tx(UNAUTHORIZED);
    {
        let pool_cap = scenario.take_from_sender<PoolCap>();

        scenario.return_to_sender(pool_cap)
    };

    test_scenario::return_shared(phase_info);
    test_scenario::return_shared(prize_pool);
    test_scenario::return_shared(lounge_registry);
    test_scenario::return_shared(pool_registry);
    clock.destroy_for_testing();
    scenario.end();
}

#[test]
#[expected_failure(abort_code = pool::ErrorPoolRiskRatioTooHigh)]
fun test_cannot_create_pool_with_risk_ratio_greater_than_100_percent() {
    let (
        mut scenario,
        clock,
        phase_info,
        prize_pool,
        lounge_registry,
        mut pool_registry,
    ) = build_pool_test_suite(
        AUTHORITY,
    );

    scenario.next_tx(AUTHORITY);
    {
        let pool_cap = scenario.take_from_sender<PoolCap>();

        pool_cap.create_pool<Coin<SUI>>(
            &mut pool_registry,
            &phase_info,
            10001,
            scenario.ctx(),
        );

        scenario.return_to_sender(pool_cap);
    };

    test_scenario::return_shared(phase_info);
    test_scenario::return_shared(prize_pool);
    test_scenario::return_shared(lounge_registry);
    test_scenario::return_shared(pool_registry);
    clock.destroy_for_testing();
    scenario.end();
}

#[test]
fun test_pool_can_only_created_by_authority() {
    let (
        mut scenario,
        clock,
        phase_info,
        prize_pool,
        lounge_registry,
        mut pool_registry,
    ) = build_pool_test_suite(
        AUTHORITY,
    );

    scenario.next_tx(AUTHORITY);
    {
        let pool_cap = scenario.take_from_sender<PoolCap>();

        pool_cap.create_pool<SUI>(&mut pool_registry, &phase_info, 5000, scenario.ctx());
        pool_cap.create_pool<SUI>(&mut pool_registry, &phase_info, 10000, scenario.ctx());

        // Pool 5000
        {
            let pool = pool_registry.get_pool_by_risk_ratio<SUI>(5000);
            assert!(pool.get_deposit_enabled() == false);
        };

        {
            // try enable depositing
            pool_cap.set_deposit_enabled<SUI>(&mut pool_registry, 5000, true);
            let pool = pool_registry.get_pool_by_risk_ratio<SUI>(5000);
            assert!(pool.get_deposit_enabled());
        };

        // Pool factory getter
        {
            let pool_risk_ratios = pool_registry.get_pool_risk_ratios();
            assert!(pool_risk_ratios.length() == 2);

            let total_risk_ratio_bps = pool_registry.get_nonzero_shares_total_risk_ratio_bps<SUI>();
            assert!(total_risk_ratio_bps == 0); // No shares yet
        };

        scenario.return_to_sender(pool_cap);
    };

    test_scenario::return_shared(phase_info);
    test_scenario::return_shared(prize_pool);
    test_scenario::return_shared(lounge_registry);
    test_scenario::return_shared(pool_registry);
    clock.destroy_for_testing();
    scenario.end();
}

#[test]
#[expected_failure(abort_code = pool::ErrorPoolAlreadyCreated)]
fun test_cannot_create_pool_with_same_risk() {
    let (
        mut scenario,
        clock,
        phase_info,
        prize_pool,
        lounge_registry,
        mut pool_registry,
    ) = build_pool_test_suite(
        AUTHORITY,
    );

    scenario.next_tx(AUTHORITY);
    {
        let pool_cap = scenario.take_from_sender<PoolCap>();

        pool_cap.create_pool<SUI>(&mut pool_registry, &phase_info, 5000, scenario.ctx());
        pool_cap.create_pool<SUI>(&mut pool_registry, &phase_info, 5000, scenario.ctx());

        scenario.return_to_sender(pool_cap);
    };

    test_scenario::return_shared(phase_info);
    test_scenario::return_shared(prize_pool);
    test_scenario::return_shared(lounge_registry);
    test_scenario::return_shared(pool_registry);
    clock.destroy_for_testing();
    scenario.end();
}
