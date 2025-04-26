#[test_only]
module red_ocean::lounge_pool_test;

use red_ocean::lounge::{Self, LoungeCap};
use red_ocean::lounge_test_suite::build_lounge_test_suite;
use sui::balance::create_for_testing as create_balance_for_testing;
use sui::coin::from_balance;
use sui::sui::SUI;
use sui::test_scenario;
use sui::test_utils;

const AUTHORITY: address = @0xAAA;
const UNAUTHORIZED: address = @0xFFF;

/// Capability cases
///
/// - capability cannot be taken by an unauthorized user
/// - cannot create lounge with 0x0 recipient
/// - can create lounge with valid recipient
///
/// User scenarios
///
/// - cannot claim lounge by unauthorized user
/// - can claim lounge by authorized user

#[test]
#[expected_failure(abort_code = test_scenario::EEmptyInventory)]
fun test_capability_cannot_be_taken_by_unauthorized_user() {
    let (mut scenario, clock, phase_info, pool_registry, lounge_registry) = build_lounge_test_suite(
        AUTHORITY,
    );

    scenario.next_tx(UNAUTHORIZED);
    {
        let cap = scenario.take_from_sender<LoungeCap>();

        scenario.return_to_sender(cap)
    };

    test_scenario::return_shared(phase_info);
    test_scenario::return_shared(pool_registry);
    test_scenario::return_shared(lounge_registry);
    clock.destroy_for_testing();
    scenario.end();
}

#[test]
#[expected_failure(abort_code = lounge::ErrorRecipientCannotBeZero)]
fun test_cannot_create_lounge_with_0x0_recipient() {
    let (
        mut scenario,
        clock,
        phase_info,
        pool_registry,
        mut lounge_registry,
    ) = build_lounge_test_suite(
        AUTHORITY,
    );

    scenario.next_tx(AUTHORITY);
    {
        let lounge_cap = scenario.take_from_sender<LoungeCap>();
        let _ = lounge_cap.create_lounge<SUI>(&mut lounge_registry, 0, @0x0, scenario.ctx());
        scenario.return_to_sender(lounge_cap);
    };

    test_scenario::return_shared(phase_info);
    test_scenario::return_shared(pool_registry);
    test_scenario::return_shared(lounge_registry);
    clock.destroy_for_testing();
    scenario.end();
}

#[test]
fun test_create_lounge_by_capability() {
    let (
        mut scenario,
        clock,
        phase_info,
        pool_registry,
        mut lounge_registry,
    ) = build_lounge_test_suite(
        AUTHORITY,
    );

    scenario.next_tx(AUTHORITY);
    {
        let lounge_cap = scenario.take_from_sender<LoungeCap>();
        let _ = lounge_cap.create_lounge<SUI>(&mut lounge_registry, 0, @0x1, scenario.ctx());
        scenario.return_to_sender(lounge_cap);
    };

    test_scenario::return_shared(phase_info);
    test_scenario::return_shared(pool_registry);
    test_scenario::return_shared(lounge_registry);
    clock.destroy_for_testing();
    scenario.end();
}

/// User scenarios
///
/// - cannot claim lounge by unauthorized user
/// - can claim lounge by authorized user
///

#[test]
#[expected_failure(abort_code = lounge::ErrorUnauthorized)]
fun test_lounge_cannot_claim_by_unauthorized() {
    let (
        mut scenario,
        clock,
        phase_info,
        pool_registry,
        mut lounge_registry,
    ) = build_lounge_test_suite(
        AUTHORITY,
    );

    let recipient = @0x1;
    let unauthorized_recipient = @0x2;

    scenario.next_tx(AUTHORITY);
    {
        let lounge_cap = scenario.take_from_sender<LoungeCap>();
        let _ = lounge_cap.create_lounge<SUI>(
            &mut lounge_registry,
            0,
            recipient,
            scenario.ctx(),
        );
        scenario.return_to_sender(lounge_cap);
    };

    scenario.next_tx(unauthorized_recipient);
    {
        // Even though the lounge is transferred to unauthorized recipient, it should claimable by the original recipient
        let claimed_coin = lounge_registry.claim<SUI>(0, scenario.ctx());
        test_utils::destroy(claimed_coin);
    };

    test_scenario::return_shared(phase_info);
    test_scenario::return_shared(pool_registry);
    test_scenario::return_shared(lounge_registry);
    clock.destroy_for_testing();
    scenario.end();
}

#[test]
fun test_lounge_can_claim_by_recipient() {
    let (
        mut scenario,
        clock,
        phase_info,
        pool_registry,
        mut lounge_registry,
    ) = build_lounge_test_suite(
        AUTHORITY,
    );

    let recipient = @0x1;
    let claim_value = 100;

    scenario.next_tx(AUTHORITY);
    {
        let lounge_cap = scenario.take_from_sender<LoungeCap>();
        let _ = lounge_cap.create_lounge<SUI>(
            &mut lounge_registry,
            0,
            recipient,
            scenario.ctx(),
        );
        scenario.return_to_sender(lounge_cap);
    };

    scenario.next_tx(recipient);
    {
        let balance = create_balance_for_testing<SUI>(claim_value);
        lounge_registry.add_reserves(0, from_balance(balance, scenario.ctx()));
    };

    scenario.next_tx(recipient);
    {
        let claimed_coin = lounge_registry.claim<SUI>(0, scenario.ctx());
        assert!(claimed_coin.value() == claim_value);
        test_utils::destroy(claimed_coin);
    };

    test_scenario::return_shared(phase_info);
    test_scenario::return_shared(pool_registry);
    test_scenario::return_shared(lounge_registry);
    clock.destroy_for_testing();
    scenario.end();
}
