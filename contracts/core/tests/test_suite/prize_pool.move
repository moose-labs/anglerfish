#[test_only]
module anglerfish::prize_pool_test_suite;

use anglerfish::phase::PhaseInfo;
use anglerfish::phase_test_suite::build_phase_test_suite;
use anglerfish::prize_pool::{PrizePool, PrizePoolCap};
use sui::clock::Clock;
use sui::test_scenario::Scenario;

const PRIZE_POOL_PRICE_PER_TICKET: u64 = 100;
const PRIZE_POOL_LP_FEE_BPS: u64 = 2500;
const PRIZE_POOL_PROTOCOL_FEE_BPS: u64 = 500;
const PRIZE_POOL_REFERRER_FEE_BPS: u64 = 1000;

/// build_prize_pool_test_suite
public fun build_prize_pool_test_suite(
    authority: address,
): (Scenario, Clock, PhaseInfo, PrizePool) {
    let (scenario, clock, phase_info) = build_phase_test_suite(authority);

    let prize_pool = scenario.take_shared<PrizePool>();

    (scenario, clock, phase_info, prize_pool)
}

/// build_initialized_prize_pool_test_suite
public fun build_initialized_prize_pool_test_suite(
    authority: address,
): (Scenario, Clock, PhaseInfo, PrizePool) {
    let (mut scenario, clock, phase_info, mut prize_pool) = build_prize_pool_test_suite(
        authority,
    );

    // Initilize parameters for prize pool
    scenario.next_tx(authority);
    {
        let prize_pool_cap = scenario.take_from_sender<PrizePoolCap>();

        prize_pool_cap.set_price_per_ticket(
            &mut prize_pool,
            &phase_info,
            PRIZE_POOL_PRICE_PER_TICKET,
        );

        prize_pool_cap.set_lp_fee_bps(&mut prize_pool, &phase_info, PRIZE_POOL_LP_FEE_BPS);

        prize_pool_cap.set_protocol_fee_bps(
            &mut prize_pool,
            &phase_info,
            PRIZE_POOL_PROTOCOL_FEE_BPS,
        );

        prize_pool_cap.set_referrer_fee_bps(
            &mut prize_pool,
            &phase_info,
            PRIZE_POOL_REFERRER_FEE_BPS,
        );

        scenario.return_to_sender(prize_pool_cap);
    };

    (scenario, clock, phase_info, prize_pool)
}
