#[test_only]
module red_ocean::prize_pool_test;

use red_ocean::test_suite::build_prize_pool_test_suite;
use sui::sui::SUI;
use sui::test_scenario;

const AUTHORITY: address = @0xAAA;

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
        let total_prize_pool = prize_pool.get_total_prize_pool<SUI>(&pool_factory);
        assert!(total_prize_pool == 2400000);
    };

    clock.destroy_for_testing();
    test_scenario::return_shared(phase_info);
    test_scenario::return_shared(pool_factory);
    test_scenario::return_shared(prize_pool);
    scenario.end();
}
