#[test_only]
module red_ocean::prize_pool_test;

use red_ocean::prize_pool::PrizePoolCap;
use red_ocean::test_suite::{build_prize_pool_test_suite, build_base_test_suite};
use sui::sui::SUI;
use sui::test_scenario;

const AUTHORITY: address = @0xAAA;
const UNAUTHORIZED: address = @0xFFF;

#[test]
#[expected_failure(abort_code = test_scenario::EEmptyInventory)]
fun test_capability_cannot_be_taken_by_unauthorized_user() {
    let (mut scenario, clock) = build_base_test_suite(
        AUTHORITY,
    );

    scenario.next_tx(UNAUTHORIZED);
    {
        let pool_cap = scenario.take_from_sender<PrizePoolCap>();

        scenario.return_to_sender(pool_cap)
    };

    clock.destroy_for_testing();
    scenario.end();
}

#[test]
fun test_get_total_prize_pool() {
    let (mut scenario, clock, phase_info, pool_factory, prize_pool) = build_prize_pool_test_suite(
        AUTHORITY,
    );

    scenario.next_tx(AUTHORITY);
    {
        // Deposit liquidity into the pools
        // - 1m into 20% pool each (prize = 200_000 per user)
        // - 2m into 50% pool each (prize = 1_000_000 per user)
        let total_prize_pool = pool_factory.get_total_prize_reserves_value<SUI>();
        assert!(total_prize_pool == 2400000);

        let total_prize_pool = prize_pool.get_total_prize_reserves_value<SUI>(&pool_factory);
        assert!(total_prize_pool == 2400000);
    };

    test_scenario::return_shared(phase_info);
    test_scenario::return_shared(pool_factory);
    test_scenario::return_shared(prize_pool);
    clock.destroy_for_testing();
    scenario.end();
}
