#[test_only]
module anglerfish::phase_test;

use anglerfish::base_test_suite::build_base_test_suite;
use anglerfish::phase::{Self, PhaseInfo, PhaseInfoCap};
use sui::test_scenario;

const DURATION: u64 = 60;
const DURATION_MS: u64 = DURATION * 1000;
const AUTHORITY: address = @0xAAA;
const UNAUTHORIZED: address = @0xFFF;

// Initializing Scenarios
//
// capability cannot be taken by unauthorized user
// cannot change phase when not initialized
// cannot initialize with zero duration(s)
// can initialize with valid duration(s)
// initial phase must be Settling
// cannot initialize again

#[test]
#[expected_failure(abort_code = test_scenario::EEmptyInventory)]
fun test_capability_cannot_be_taken_by_unauthorized_user() {
    let (mut scenario, clock) = build_base_test_suite(AUTHORITY);

    scenario.next_tx(UNAUTHORIZED);
    {
        let cap = scenario.take_from_sender<PhaseInfoCap>();

        scenario.return_to_sender(cap)
    };

    clock.destroy_for_testing();
    scenario.end();
}

#[test]
#[expected_failure(abort_code = phase::ErrorUninitialized)]
fun test_cannot_next_phase_when_not_initialized() {
    let (mut scenario, clock) = build_base_test_suite(AUTHORITY);

    scenario.next_tx(AUTHORITY);
    {
        let mut phase_info = scenario.take_shared<PhaseInfo>();
        let phase_info_cap = scenario.take_from_sender<PhaseInfoCap>();

        phase_info_cap.next(&mut phase_info, &clock, scenario.ctx());

        test_scenario::return_shared(phase_info);
        scenario.return_to_sender(phase_info_cap)
    };

    clock.destroy_for_testing();
    scenario.end();
}

#[test]
#[expected_failure(abort_code = phase::ErrorDurationTooShort)]
fun test_cannot_initialize_with_zero_durations() {
    let (mut scenario, clock) = build_base_test_suite(AUTHORITY);

    scenario.next_tx(AUTHORITY);
    {
        let mut phase_info = scenario.take_shared<PhaseInfo>();
        let phase_info_cap = scenario.take_from_sender<PhaseInfoCap>();

        phase_info_cap.initialize(&mut phase_info, 0, DURATION, scenario.ctx());

        test_scenario::return_shared(phase_info);
        scenario.return_to_sender(phase_info_cap);
    };

    clock.destroy_for_testing();
    scenario.end();
}

#[test]
fun test_initialize_with_durations_and_settled() {
    let (mut scenario, clock) = build_base_test_suite(AUTHORITY);

    scenario.next_tx(AUTHORITY);
    {
        let mut phase_info = scenario.take_shared<PhaseInfo>();
        let phase_info_cap = scenario.take_from_sender<PhaseInfoCap>();

        phase_info_cap.initialize(&mut phase_info, DURATION, DURATION, scenario.ctx());
        phase_info.assert_initialized();

        // initialize phase must be Settling
        phase_info.assert_settling_phase();

        test_scenario::return_shared(phase_info);
        scenario.return_to_sender(phase_info_cap);
    };

    clock.destroy_for_testing();
    scenario.end();
}

#[test]
#[expected_failure(abort_code = phase::ErrorAlreadyInitialized)]
fun test_cannot_initialize_twice() {
    let (mut scenario, clock) = build_base_test_suite(AUTHORITY);

    scenario.next_tx(AUTHORITY);
    {
        let mut phase_info = scenario.take_shared<PhaseInfo>();
        let phase_info_cap = scenario.take_from_sender<PhaseInfoCap>();

        phase_info_cap.initialize(&mut phase_info, DURATION, DURATION, scenario.ctx());
        phase_info_cap.initialize(&mut phase_info, DURATION, DURATION, scenario.ctx());

        test_scenario::return_shared(phase_info);
        scenario.return_to_sender(phase_info_cap);
    };

    clock.destroy_for_testing();
    scenario.end();
}

// Phase Changing Scenarios
//
// cannot change a phase that hasn't come yet. (Settling -> LiquidityProviding)
// [hack] fast forward time
// can change phase (Settling -> LiquidityProviding)
// cannot change a phase that hasn't come yet. (LiquidityProviding -> Ticketing)
// [hack] fast forward time
// can change phase (LiquidityProviding -> Ticketing)
// cannot change a phase that hasn't come yet. (Ticketing -> Drawing)
// [hack] fast forward time
// can change phase (Ticketing -> Drawing)
// can instantly change phase on drawed phase (Drawing -> Settling)

#[test]
#[expected_failure(abort_code = phase::ErrorCurrentPhaseIsNotAllowedIterateFromEntry)]
fun test_change_phase_until_no_entry() {
    let (mut scenario, mut clock) = build_base_test_suite(AUTHORITY);

    scenario.next_tx(AUTHORITY);
    {
        let mut phase_info = scenario.take_shared<PhaseInfo>();
        let phase_info_cap = scenario.take_from_sender<PhaseInfoCap>();

        phase_info_cap.initialize(&mut phase_info, DURATION, DURATION, scenario.ctx());
        phase_info.assert_settling_phase();
        assert!(phase_info.get_current_round() == 0);
        assert!(phase_info.is_current_phase_completed(&clock));

        // can change phase (Settling -> LiquidityProviding)
        phase_info_cap.next_entry(&mut phase_info, &clock, scenario.ctx());
        phase_info.assert_liquidity_providing_phase();

        // should bump round on liquidity providing phase
        assert!(phase_info.get_current_round() == 1);

        // cannot change a phase that hasn't come yet. (LiquidityProviding -> Ticketing)
        assert!(phase_info.is_current_phase_completed(&clock) == false);

        // [hack] fast forward time
        clock.increment_for_testing(DURATION_MS);

        // can change phase (LiquidityProviding -> Ticketing)
        phase_info_cap.next_entry(&mut phase_info, &clock, scenario.ctx());
        phase_info.assert_ticketing_phase();
        assert!(phase_info.get_current_round() == 1);

        // cannot change a phase that hasn't come yet. (Ticketing -> Drawing)
        assert!(!phase_info.is_current_phase_completed(&clock));

        // [hack] fast forward time
        clock.increment_for_testing(DURATION_MS);

        // can change phase (Ticketing -> Drawing)
        phase_info_cap.next_entry(&mut phase_info, &clock, scenario.ctx());
        phase_info.assert_drawing_phase();
        assert!(phase_info.get_current_round() == 1);

        // This should revert with ErrorCurrentPhaseIsNotAllowedIterateFromEntry
        // can instantly change phase on drawed phase (Drawing -> Distributing)
        phase_info_cap.next_entry(&mut phase_info, &clock, scenario.ctx());

        test_scenario::return_shared(phase_info);
        scenario.return_to_sender(phase_info_cap);
    };

    clock.destroy_for_testing();
    scenario.end();
}
