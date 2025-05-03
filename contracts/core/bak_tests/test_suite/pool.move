#[test_only]
module anglerfish::pool_test_suite;

use anglerfish::phase::{PhaseInfo, PhaseInfoCap};
use anglerfish::phase_test_suite::build_phase_test_suite;
use anglerfish::pool::{PoolCap, PoolRegistry};
use sui::clock::Clock;
use sui::sui::SUI;
use sui::test_scenario::Scenario;

const PHASE_DURATION: u64 = 60;
const TEST_POOL_1_RISK: u64 = 2000;
const TEST_POOL_2_RISK: u64 = 5000;

/// build_pool_test_suite
/// Forwards the phase info to the liquidity providing phase and initializes the pool.
/// It also sets the deposit enabled flag for the pools.
public fun build_pool_test_suite(authority: address): (Scenario, Clock, PhaseInfo, PoolRegistry) {
    let (mut scenario, mut clock, mut phase_info) = build_phase_test_suite(authority);

    let mut pool_registry = scenario.take_shared<PoolRegistry>();

    // Create and initialize pool
    scenario.next_tx(authority);
    {
        let pool_cap = scenario.take_from_sender<PoolCap>();

        pool_cap.create_pool<SUI>(
            &mut pool_registry,
            &phase_info,
            TEST_POOL_1_RISK,
            scenario.ctx(),
        );
        pool_cap.create_pool<SUI>(
            &mut pool_registry,
            &phase_info,
            TEST_POOL_2_RISK,
            scenario.ctx(),
        );

        pool_cap.set_deposit_enabled<SUI>(&mut pool_registry, TEST_POOL_1_RISK, true);
        let pool = pool_registry.get_pool_by_risk_ratio<SUI>(TEST_POOL_1_RISK);
        pool.assert_deposit_enabled();

        pool_cap.set_deposit_enabled<SUI>(&mut pool_registry, TEST_POOL_2_RISK, true);
        let pool = pool_registry.get_pool_by_risk_ratio<SUI>(TEST_POOL_2_RISK);
        pool.assert_deposit_enabled();

        scenario.return_to_sender(pool_cap);
    };

    // Settling phase to liquidity providing phase
    scenario.next_tx(authority);
    {
        let phase_info_cap = scenario.take_from_sender<PhaseInfoCap>();

        clock.increment_for_testing(PHASE_DURATION);
        phase_info_cap.next(&mut phase_info, &clock, scenario.ctx());
        phase_info.assert_liquidity_providing_phase();

        scenario.return_to_sender(phase_info_cap);
    };

    (scenario, clock, phase_info, pool_registry)
}
