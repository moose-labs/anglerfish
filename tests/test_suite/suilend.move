#[test_only]
module red_ocean::suilend_test_suite;

use sui::bag;
use sui::test_scenario::Scenario;
use sui::test_utils;
use suilend::lending_market::LendingMarket;
use suilend::lending_market_tests::{setup as setup_suilend_for_testing, LENDING_MARKET};

/// build_suilend_test_suite
/// Test suite that deploys a lending object.
public fun build_suilend_test_suite(
    scenario: &mut Scenario,
    authority: address,
): (LendingMarket<LENDING_MARKET>) {
    let bag = bag::new(scenario.ctx());

    scenario.next_tx(authority);

    let suilend_state = setup_suilend_for_testing(bag, scenario);

    let (clock, owner_cap, lending_market, prices, type_to_index) = suilend_state.destruct_state();
    test_utils::destroy(type_to_index);
    test_utils::destroy(owner_cap);
    test_utils::destroy(prices);
    test_utils::destroy(clock);

    lending_market
}
