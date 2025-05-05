#[test_only]
module anglerfish::phase_test_suite;

use anglerfish::base_test_suite::build_base_test_suite;
use anglerfish::phase::{PhaseInfo, PhaseInfoCap};
use sui::clock::Clock;
use sui::test_scenario::Scenario;

const PHASE_DURATION: u64 = 60;

/// build_phase_test_suite
/// Initializes phase info for the test suite with the given authority.
public fun build_phase_test_suite(authority: address): (Scenario, Clock, PhaseInfo) {
    let (mut scenario, clock) = build_base_test_suite(authority);

    scenario.next_tx(authority);

    let mut phase_info = scenario.take_shared<PhaseInfo>();

    {
        let phase_info_cap = scenario.take_from_sender<PhaseInfoCap>();
        phase_info_cap.initialize(
            &mut phase_info,
            PHASE_DURATION,
            PHASE_DURATION,
            scenario.ctx(),
        );
        scenario.return_to_sender(phase_info_cap);
    };

    (scenario, clock, phase_info)
}
