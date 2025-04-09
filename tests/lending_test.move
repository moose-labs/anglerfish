#[test_only]
module red_ocean::lending_test;

use red_ocean::lending_test_suite::build_lending_test_suite;
use red_ocean::suilend_test_suite::build_suilend_test_suite;
use sui::balance::{Self, create_for_testing as create_balance_for_testing};
use sui::coin;
use sui::sui::SUI;
use sui::test_scenario;
use suilend::lending_market_tests::LENDING_MARKET;

const AUTHORITY: address = @0xAAA;
const USER1: address = @0x001;

#[test]
fun test_simple() {
    let (mut scenario, clock, phase_info, mut pool_factory, mut lending) = build_lending_test_suite(
        AUTHORITY,
    );

    let mut suilend_lending_market = build_suilend_test_suite(&mut scenario, AUTHORITY);

    scenario.next_tx(USER1);
    {
        let mut user_balance = create_balance_for_testing<SUI>(100);
        let pool_risk_2000 = pool_factory.get_pool_by_risk_ratio_mut<SUI>(2000);
        let pool_id = object::id(pool_risk_2000);

        lending.add_reserves<SUI, LENDING_MARKET>(
            &phase_info,
            &mut suilend_lending_market,
            pool_id,
            &clock,
            coin::take<SUI>(&mut user_balance, 1, scenario.ctx()),
            scenario.ctx(),
        );

        balance::destroy_for_testing(user_balance);
    };

    test_scenario::return_shared(suilend_lending_market);
    test_scenario::return_shared(phase_info);
    test_scenario::return_shared(lending);
    test_scenario::return_shared(pool_factory);
    clock.destroy_for_testing();
    scenario.end();
}
