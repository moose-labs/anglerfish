#[test_only]
module red_ocean::lounge_test_suite;

use red_ocean::lounge::LoungeRegistry;
use red_ocean::phase::PhaseInfo;
use red_ocean::pool::PoolRegistry;
use red_ocean::pool_test_suite::build_pool_test_suite;
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
