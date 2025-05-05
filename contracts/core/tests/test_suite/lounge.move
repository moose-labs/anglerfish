#[test_only]
module anglerfish::lounge_test_suite;

use anglerfish::lounge::LoungeRegistry;
use anglerfish::phase::PhaseInfo;
use anglerfish::prize_pool::PrizePool;
use anglerfish::prize_pool_test_suite::{
    build_prize_pool_test_suite,
    build_initialized_prize_pool_test_suite
};
use sui::clock::Clock;
use sui::test_scenario::Scenario;

public fun build_lounge_test_suite(
    authority: address,
): (Scenario, Clock, PhaseInfo, PrizePool, LoungeRegistry) {
    let (mut scenario, clock, phase_info, prize_pool) = build_prize_pool_test_suite(
        authority,
    );

    scenario.next_tx(authority);

    let lounge_registry = scenario.take_shared<LoungeRegistry>();

    (scenario, clock, phase_info, prize_pool, lounge_registry)
}

public fun build_initialized_lounge_test_suite(
    authority: address,
): (Scenario, Clock, PhaseInfo, PrizePool, LoungeRegistry) {
    let (mut scenario, clock, phase_info, prize_pool) = build_initialized_prize_pool_test_suite(
        authority,
    );

    scenario.next_tx(authority);

    let lounge_registry = scenario.take_shared<LoungeRegistry>();

    (scenario, clock, phase_info, prize_pool, lounge_registry)
}
