#[test_only]
module anglerfish::iterator_test_suite;

use anglerfish::base_test_suite::build_base_test_suite;
use anglerfish::iterator::IteratorCreatorCap;
use sui::clock::Clock;
use sui::test_scenario::Scenario;

public fun build_iterator_test_suite(authority: address): (Scenario, Clock) {
    let (mut scenario, clock) = build_base_test_suite(
        authority,
    );

    scenario.next_tx(authority);
    {
        let iter_creator_cap = scenario.take_from_sender<IteratorCreatorCap>();
        scenario.return_to_sender(iter_creator_cap);
    };
    (scenario, clock)
}
