#[test_only]
module red_ocean::base_test_suite;

use red_ocean::lending::init_for_testing as init_lending_for_testing;
use red_ocean::lounge::init_for_testing as init_lounge_for_testing;
use red_ocean::phase::init_for_testing as init_phase_info_for_testing;
use red_ocean::pool::init_for_testing as init_pool_for_testing;
use red_ocean::prize_pool::init_for_testing as init_prize_for_testing;
use sui::clock::{create_for_testing as create_clock_for_testing, Clock};
use sui::random::create_for_testing as create_random_for_testing;
use sui::test_scenario::{Self, Scenario};

/// build_base_test_suite
/// Initializes the base test suite with the given authority.
public fun build_base_test_suite(authority: address): (Scenario, Clock) {
    let mut scenario = test_scenario::begin(authority);
    let clock = create_clock_for_testing(scenario.ctx());

    scenario.next_tx(@0x0);
    {
        create_random_for_testing(scenario.ctx());
    };

    scenario.next_tx(authority);
    {
        init_phase_info_for_testing(scenario.ctx());
        init_pool_for_testing(scenario.ctx());
        init_lounge_for_testing(scenario.ctx());
        init_prize_for_testing(scenario.ctx());
        init_lending_for_testing(scenario.ctx());
    };

    (scenario, clock)
}
