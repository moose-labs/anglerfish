#[test_only]
module red_ocean::lending_test;

use red_ocean::lending::{Self, LendingCap, AllocationCap};
use red_ocean::lending_test_suite::build_lending_test_suite;
use red_ocean::suilend_test_suite::build_suilend_test_suite;
use sui::balance::{Self, create_for_testing as create_balance_for_testing};
use sui::coin;
use sui::sui::SUI;
use sui::test_scenario;
use sui::test_utils;
use suilend::lending_market_tests::LENDING_MARKET;

const AUTHORITY: address = @0xAAA;
const ALLOCATOR: address = @0xBBB;
const USER1: address = @0x001;

// Capability
// should init with sender capability
// should able to mint new allocation capability
// cannot register pool twice
// should reject invalid weights
// should able to update weights
// should able to add liquidity
// [hack] add suilend reserve
// should able to remove liquidity

#[test]
fun test_init_with_sender_capability() {
    let (mut scenario, clock, phase_info, pool_factory, lending) = build_lending_test_suite(
        AUTHORITY,
    );

    scenario.next_tx(AUTHORITY);
    {
        let lending_cap = scenario.take_from_sender<LendingCap>();
        scenario.return_to_sender(lending_cap);
    };

    test_scenario::return_shared(phase_info);
    test_scenario::return_shared(lending);
    test_scenario::return_shared(pool_factory);
    clock.destroy_for_testing();
    scenario.end();
}

#[test]
fun test_able_to_mint_allocation_capability() {
    let (mut scenario, clock, phase_info, pool_factory, lending) = build_lending_test_suite(
        AUTHORITY,
    );

    scenario.next_tx(AUTHORITY);
    {
        let lending_cap = scenario.take_from_sender<LendingCap>();
        lending_cap.new_allocation_cap(ALLOCATOR, scenario.ctx());
        scenario.return_to_sender(lending_cap);
    };

    scenario.next_tx(ALLOCATOR);
    {
        let allocation_cap = scenario.take_from_sender<AllocationCap>();
        scenario.return_to_sender(allocation_cap);
    };

    test_scenario::return_shared(phase_info);
    test_scenario::return_shared(lending);
    test_scenario::return_shared(pool_factory);
    clock.destroy_for_testing();
    scenario.end();
}

#[test]
#[expected_failure(abort_code = lending::ErrorPoolAlreadyRegistered)]
fun test_cannot_register_pool_twice() {
    let (mut scenario, clock, phase_info, pool_factory, mut lending) = build_lending_test_suite(
        AUTHORITY,
    );

    scenario.next_tx(AUTHORITY);
    {
        let pool = pool_factory.get_pool_by_risk_ratio<SUI>(2000);
        let lending_cap = scenario.take_from_sender<LendingCap>();
        lending_cap.register_pool(&mut lending, object::id(pool), scenario.ctx());
        scenario.return_to_sender(lending_cap);
    };

    test_scenario::return_shared(phase_info);
    test_scenario::return_shared(lending);
    test_scenario::return_shared(pool_factory);
    clock.destroy_for_testing();
    scenario.end();
}

#[test]
#[expected_failure(abort_code = lending::ErrorInvalidWeights)]
fun test_should_check_weights() {
    let (mut scenario, clock, phase_info, pool_factory, mut lending) = build_lending_test_suite(
        AUTHORITY,
    );

    scenario.next_tx(AUTHORITY);
    {
        let lending_cap = scenario.take_from_sender<LendingCap>();
        lending_cap.update_suilend_weights(
            &mut lending,
            0,
            scenario.ctx(),
        );
        scenario.return_to_sender(lending_cap);
    };

    test_scenario::return_shared(phase_info);
    test_scenario::return_shared(lending);
    test_scenario::return_shared(pool_factory);
    clock.destroy_for_testing();
    scenario.end();
}

#[test]
fun test_add_remove_liquidity() {
    let (mut scenario, clock, phase_info, mut pool_factory, mut lending) = build_lending_test_suite(
        AUTHORITY,
    );

    let mut suilend_lending_market = build_suilend_test_suite(&mut scenario, AUTHORITY);

    scenario.next_tx(USER1);
    {
        let mut user_balance = create_balance_for_testing<SUI>(10000);
        let pool_risk_2000 = pool_factory.get_pool_by_risk_ratio_mut<SUI>(2000);
        let pool_id = object::id(pool_risk_2000);

        lending.add_liquidity<SUI, LENDING_MARKET>(
            &phase_info,
            &mut suilend_lending_market,
            pool_id,
            &clock,
            coin::take<SUI>(&mut user_balance, 10000, scenario.ctx()),
            scenario.ctx(),
        );

        balance::destroy_for_testing(user_balance);
    };

    {
        let pool_risk_2000 = pool_factory.get_pool_by_risk_ratio_mut<SUI>(2000);
        let pool_id = object::id(pool_risk_2000);

        let redeemed_coin = lending.remove_liquidity<SUI, LENDING_MARKET>(
            &phase_info,
            &mut suilend_lending_market,
            pool_id,
            100,
            &clock,
            scenario.ctx(),
        );
        assert!(redeemed_coin.value() == 100);
        redeemed_coin.burn_for_testing();
    };

    test_utils::destroy(suilend_lending_market);
    test_scenario::return_shared(phase_info);
    test_scenario::return_shared(lending);
    test_scenario::return_shared(pool_factory);
    clock.destroy_for_testing();
    scenario.end();
}
