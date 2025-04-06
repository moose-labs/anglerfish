#[test_only]
module red_ocean::lounge_test_suite;

use red_ocean::lounge::LoungeFactory;
use red_ocean::phase::PhaseInfo;
use red_ocean::pool::PoolFactory;
use red_ocean::pool_test_suite::build_pool_test_suite;
use sui::clock::Clock;
use sui::test_scenario::Scenario;

/// build_lounge_test_suite
/// Test suite that deploys a lounge object.
public fun build_lounge_test_suite(
    authority: address,
): (Scenario, Clock, PhaseInfo, PoolFactory, LoungeFactory) {
    let (mut scenario, clock, phase_info, pool_factory) = build_pool_test_suite(authority);

    scenario.next_tx(authority);

    let lounge_factory = scenario.take_shared<LoungeFactory>();

    (scenario, clock, phase_info, pool_factory, lounge_factory)
}
