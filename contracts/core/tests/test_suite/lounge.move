#[test_only]
module anglerfish::lounge_test_suite;

use anglerfish::lounge::LoungeRegistry;
use anglerfish::phase::PhaseInfo;
use anglerfish::pool::PoolRegistry;
use anglerfish::pool_test_suite::build_pool_test_suite;
use sui::clock::Clock;
use sui::test_scenario::Scenario;

/// build_lounge_test_suite
/// Test suite that deploys a lounge object.
public fun build_lounge_test_suite(
    authority: address,
): (Scenario, Clock, PhaseInfo, PoolRegistry, LoungeRegistry) {
    let (mut scenario, clock, phase_info, pool_registry) = build_pool_test_suite(authority);

    scenario.next_tx(authority);

    let lounge_registry = scenario.take_shared<LoungeRegistry>();

    (scenario, clock, phase_info, pool_registry, lounge_registry)
}
