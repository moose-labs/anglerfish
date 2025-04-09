#[test_only]
module red_ocean::lending_test_suite;

use red_ocean::lending::{Lending, LendingCap};
use red_ocean::phase::PhaseInfo;
use red_ocean::pool::PoolFactory;
use red_ocean::pool_test_suite::build_pool_test_suite;
use sui::clock::Clock;
use sui::sui::SUI;
use sui::test_scenario::Scenario;

/// build_lending_test_suite
/// Test suite that deploys a lending object.
public fun build_lending_test_suite<>(
    authority: address,
): (Scenario, Clock, PhaseInfo, PoolFactory, Lending) {
    let (mut scenario, clock, phase_info, mut pool_factory) = build_pool_test_suite(authority);

    scenario.next_tx(authority);

    let mut lending = scenario.take_shared<Lending>();
    scenario.next_tx(authority);
    {
        let lending_cap = scenario.take_from_sender<LendingCap>();

        let pool_risk_2000 = pool_factory.get_pool_by_risk_ratio_mut<SUI>(2000);
        lending_cap.register_pool(&mut lending, object::id(pool_risk_2000), scenario.ctx());

        let pool_risk_5000 = pool_factory.get_pool_by_risk_ratio_mut<SUI>(5000);
        lending_cap.register_pool(&mut lending, object::id(pool_risk_5000), scenario.ctx());

        scenario.return_to_sender(lending_cap);
    };

    (scenario, clock, phase_info, pool_factory, lending)
}
