#[test_only]
module anglerfish::prize_pool_initialize_test;

use anglerfish::prize_pool::PrizePoolCap;
use anglerfish::prize_pool_test_suite::build_prize_pool_test_suite;
use sui::test_scenario;

const AUTHORITY: address = @0xAAA;
const UNAUTHORIZED: address = @0xFFF;

/// Capability
/// - capability cannot be taken by an unauthorized user
/// - can set pool factory
/// - can set lounge factory
/// - can set max players
/// - can set price per ticket
/// - can set protocol fee
/// - can claim protocol fee

#[test]
#[expected_failure(abort_code = test_scenario::EEmptyInventory)]
fun test_capability_cannot_be_taken_by_unauthorized_user() {
    let (mut scenario, clock, phase_info, prize_pool) = build_prize_pool_test_suite(
        AUTHORITY,
    );

    scenario.next_tx(UNAUTHORIZED);
    {
        let pool_cap = scenario.take_from_sender<PrizePoolCap>();

        scenario.return_to_sender(pool_cap)
    };

    test_scenario::return_shared(phase_info);
    test_scenario::return_shared(prize_pool);
    clock.destroy_for_testing();
    scenario.end();
}

#[test]
fun test_set_initialize_parameters() {
    let (mut scenario, clock, phase_info, mut prize_pool) = build_prize_pool_test_suite(
        AUTHORITY,
    );

    // Set price per ticket
    scenario.next_tx(AUTHORITY);
    {
        let pool_cap = scenario.take_from_sender<PrizePoolCap>();

        assert!(prize_pool.get_price_per_ticket() == 0);
        pool_cap.set_price_per_ticket(
            &mut prize_pool,
            &phase_info,
            100,
        );
        assert!(prize_pool.get_price_per_ticket() == 100);

        scenario.return_to_sender(pool_cap);
    };

    // Set fee bps
    scenario.next_tx(AUTHORITY);
    {
        let pool_cap = scenario.take_from_sender<PrizePoolCap>();

        assert!(prize_pool.get_lp_fee_bps() == 2500); // default value
        pool_cap.set_lp_fee_bps(
            &mut prize_pool,
            &phase_info,
            5000,
        );
        assert!(prize_pool.get_lp_fee_bps() == 5000);

        scenario.return_to_sender(pool_cap);
    };

    // Set protocol fee bps
    scenario.next_tx(AUTHORITY);
    {
        let pool_cap = scenario.take_from_sender<PrizePoolCap>();

        assert!(prize_pool.get_protocol_fee_bps() == 500); // default value
        pool_cap.set_protocol_fee_bps(
            &mut prize_pool,
            &phase_info,
            1000,
        );
        assert!(prize_pool.get_protocol_fee_bps() == 1000);

        scenario.return_to_sender(pool_cap);
    };

    test_scenario::return_shared(phase_info);
    test_scenario::return_shared(prize_pool);
    clock.destroy_for_testing();
    scenario.end();
}
