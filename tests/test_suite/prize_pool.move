#[test_only]
module red_ocean::prize_pool_test_suite;

use red_ocean::lounge::LoungeFactory;
use red_ocean::lounge_test_suite::build_lounge_test_suite;
use red_ocean::phase::{PhaseInfo, PhaseInfoCap};
use red_ocean::pool::PoolFactory;
use red_ocean::prize_pool::{PrizePool, PrizePoolCap};
use sui::balance::create_for_testing as create_balance_for_testing;
use sui::clock::Clock;
use sui::sui::SUI;
use sui::test_scenario::Scenario;

const PHASE_DURATION: u64 = 60;
const TEST_POOL_1_RISK: u64 = 2000;
const TEST_POOL_2_RISK: u64 = 5000;
const PRIZE_POOL_MAX_PLAYERS: u64 = 1;
const PRIZE_POOL_PRICE_PER_TICKET: u64 = 100;
const PRIZE_POOL_FEE_BPS: u64 = 2500;
const PRIZE_POOL_PROTOCOL_FEE_BPS: u64 = 500;

/// build_prize_pool_test_suite
/// Set pool factory for prize pool and also deposit liquidity into the pools.
public fun build_prize_pool_test_suite(
    authority: address,
): (Scenario, Clock, PhaseInfo, PoolFactory, LoungeFactory, PrizePool) {
    let (
        mut scenario,
        clock,
        phase_info,
        mut pool_factory,
        lounge_factory,
    ) = build_lounge_test_suite(authority);
    (authority);

    scenario.next_tx(authority);

    let prize_pool = scenario.take_shared<PrizePool>();

    // Deposit liquidity into the pools
    // - 1m into 20% pool each (prize = 200_000 per user)
    // - 2m into 50% pool each (prize = 1_000_000 per user)
    let user1: address = @0x001;
    let user2: address = @0x002;

    scenario.next_tx(user1);
    {
        let pool = pool_factory.get_pool_by_risk_ratio_mut<SUI>(TEST_POOL_1_RISK);
        let balance = create_balance_for_testing<SUI>(1000000);
        pool.deposit<SUI>(
            &phase_info,
            sui::coin::from_balance(balance, scenario.ctx()),
            scenario.ctx(),
        );

        let pool = pool_factory.get_pool_by_risk_ratio_mut<SUI>(TEST_POOL_2_RISK);
        let balance = create_balance_for_testing<SUI>(2000000);
        pool.deposit<SUI>(
            &phase_info,
            sui::coin::from_balance(balance, scenario.ctx()),
            scenario.ctx(),
        );
    };

    scenario.next_tx(user2);
    {
        let pool = pool_factory.get_pool_by_risk_ratio_mut<SUI>(TEST_POOL_1_RISK);
        let balance = create_balance_for_testing<SUI>(1000000);
        pool.deposit<SUI>(
            &phase_info,
            sui::coin::from_balance(balance, scenario.ctx()),
            scenario.ctx(),
        );

        let pool = pool_factory.get_pool_by_risk_ratio_mut<SUI>(TEST_POOL_2_RISK);
        let balance = create_balance_for_testing<SUI>(2000000);
        pool.deposit<SUI>(
            &phase_info,
            sui::coin::from_balance(balance, scenario.ctx()),
            scenario.ctx(),
        );
    };
    (scenario, clock, phase_info, pool_factory, lounge_factory, prize_pool)
}

/// build_initialized_prize_pool_test_suite
public fun build_initialized_prize_pool_test_suite(
    authority: address,
): (Scenario, Clock, PhaseInfo, PoolFactory, LoungeFactory, PrizePool) {
    let (
        mut scenario,
        mut clock,
        mut phase_info,
        pool_factory,
        lounge_factory,
        mut prize_pool,
    ) = build_prize_pool_test_suite(authority);

    scenario.next_tx(authority);

    // Initilize parameters for prize pool
    let prize_pool_cap = scenario.take_from_sender<PrizePoolCap>();

    prize_pool_cap.new_round_table_if_needed(&mut prize_pool, &phase_info, scenario.ctx());
    prize_pool_cap.set_pool_factory(&mut prize_pool, object::id(&pool_factory), scenario.ctx());
    prize_pool_cap.set_lounge_factory(&mut prize_pool, object::id(&lounge_factory), scenario.ctx());
    prize_pool_cap.set_max_players(&mut prize_pool, PRIZE_POOL_MAX_PLAYERS, scenario.ctx());
    prize_pool_cap.set_price_per_ticket(
        &mut prize_pool,
        PRIZE_POOL_PRICE_PER_TICKET,
        scenario.ctx(),
    );
    prize_pool_cap.set_fee_bps(&mut prize_pool, PRIZE_POOL_FEE_BPS, scenario.ctx());
    prize_pool_cap.set_protocol_fee_bps(
        &mut prize_pool,
        PRIZE_POOL_PROTOCOL_FEE_BPS,
        scenario.ctx(),
    );

    // iterate phase from liquidity providing to ticketing phase
    let phase_info_cap = scenario.take_from_sender<PhaseInfoCap>();
    clock.increment_for_testing(PHASE_DURATION);
    phase_info_cap.next(&mut phase_info, &clock, scenario.ctx());
    scenario.return_to_sender(phase_info_cap);

    scenario.return_to_sender(prize_pool_cap);

    (scenario, clock, phase_info, pool_factory, lounge_factory, prize_pool)
}
