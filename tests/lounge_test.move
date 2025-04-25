#[test_only]
module red_ocean::lounge_pool_test;

use red_ocean::lounge::{Self, LoungeCap};
use red_ocean::lounge_test_suite::build_lounge_test_suite;
use sui::balance::create_for_testing as create_balance_for_testing;
use sui::coin::from_balance;
use sui::sui::SUI;
use sui::test_scenario;

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
    let (mut scenario, clock, phase_info, pool_registry, lounge_factory) = build_lounge_test_suite(
        AUTHORITY,
    );

    scenario.next_tx(UNAUTHORIZED);
    {
        let cap = scenario.take_from_sender<LoungeCap>();

        scenario.return_to_sender(cap)
    };

    test_scenario::return_shared(phase_info);
    test_scenario::return_shared(pool_registry);
    test_scenario::return_shared(lounge_factory);
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
        mut lounge_factory,
    ) = build_lounge_test_suite(
        AUTHORITY,
    );

    scenario.next_tx(AUTHORITY);
    {
        let lounge_cap = scenario.take_from_sender<LoungeCap>();
        let _ = lounge_cap.create_lounge<SUI>(&mut lounge_factory, 0, @0x0, scenario.ctx());
        scenario.return_to_sender(lounge_cap);
    };

    test_scenario::return_shared(phase_info);
    test_scenario::return_shared(pool_registry);
    test_scenario::return_shared(lounge_factory);
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
        mut lounge_factory,
    ) = build_lounge_test_suite(
        AUTHORITY,
    );

    scenario.next_tx(AUTHORITY);
    {
        let lounge_cap = scenario.take_from_sender<LoungeCap>();
        let _ = lounge_cap.create_lounge<SUI>(&mut lounge_factory, 0, @0x1, scenario.ctx());
        scenario.return_to_sender(lounge_cap);
    };

    test_scenario::return_shared(phase_info);
    test_scenario::return_shared(pool_registry);
    test_scenario::return_shared(lounge_factory);
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
        mut lounge_factory,
    ) = build_lounge_test_suite(
        AUTHORITY,
    );

    let recipient = @0x1;
    let unauthorized_recipient = @0x2;

    scenario.next_tx(AUTHORITY);
    {
        let lounge_cap = scenario.take_from_sender<LoungeCap>();
        let _ = lounge_cap.create_lounge<SUI>(
            &mut lounge_factory,
            0,
            recipient,
            scenario.ctx(),
        );
        scenario.return_to_sender(lounge_cap);
    };

    scenario.next_tx(unauthorized_recipient);
    {
        let lounge = lounge_factory.get_lounge_number_mut(0);

        // Even though the lounge is transferred to unauthorized recipient, it should claimable by the original recipient
        let claimed_coin = lounge.claim<SUI>(scenario.ctx());
        claimed_coin.destroy_for_testing();
    };

    test_scenario::return_shared(phase_info);
    test_scenario::return_shared(pool_registry);
    test_scenario::return_shared(lounge_factory);
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
        mut lounge_factory,
    ) = build_lounge_test_suite(
        AUTHORITY,
    );

    let recipient = @0x1;
    let claim_value = 100;

    scenario.next_tx(AUTHORITY);
    {
        let lounge_cap = scenario.take_from_sender<LoungeCap>();
        let _ = lounge_cap.create_lounge<SUI>(
            &mut lounge_factory,
            0,
            recipient,
            scenario.ctx(),
        );
        scenario.return_to_sender(lounge_cap);
    };

    scenario.next_tx(recipient);
    {
        let balance = create_balance_for_testing<SUI>(claim_value);
        let lounge = lounge_factory.get_lounge_number_mut(0);
        lounge.add_reserves(from_balance(balance, scenario.ctx()));
    };

    scenario.next_tx(recipient);
    {
        let lounge = lounge_factory.get_lounge_number_mut(0);
        let claimed_balance = lounge.claim<SUI>(scenario.ctx());
        assert!(claimed_balance.value() == claim_value);
        claimed_balance.destroy_for_testing();
    };

    test_scenario::return_shared(phase_info);
    test_scenario::return_shared(pool_registry);
    test_scenario::return_shared(lounge_factory);
    clock.destroy_for_testing();
    scenario.end();
}
