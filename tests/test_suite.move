#[test_only]
module red_ocean::test_suite;

use red_ocean::phase::{init_for_testing as init_phase_info_for_testing, PhaseInfo, PhaseInfoCap};
use red_ocean::pool::{init_for_testing as init_pool_for_testing, PoolCap, PoolFactory};
use red_ocean::prize_pool::{init_for_testing as init_prize_for_testing, PrizePool, PrizePoolCap};
use sui::balance::create_for_testing as create_balance_for_testing;
use sui::clock::{create_for_testing as create_clock_for_testing, Clock};
use sui::sui::SUI;
use sui::test_scenario::{Self, Scenario};

const PHASE_DURATION: u64 = 60;
const TEST_POOL_1_RISK: u64 = 2000;
const TEST_POOL_2_RISK: u64 = 5000;

// Test Suite for Red Ocean

/// build_base_test_suite
/// Initializes the base test suite with the given authority.
public fun build_base_test_suite(authority: address): (Scenario, Clock) {
    let mut scenario = test_scenario::begin(authority);
    let clock = create_clock_for_testing(scenario.ctx());

    init_phase_info_for_testing(scenario.ctx());
    init_pool_for_testing(scenario.ctx());
    init_prize_for_testing(scenario.ctx());

    (scenario, clock)
}

/// build_phase_test_suite
/// Initializes phase info for the test suite with the given authority.
public fun build_phase_test_suite(authority: address): (Scenario, Clock, PhaseInfo) {
    let (mut scenario, clock) = build_base_test_suite(authority);

    scenario.next_tx(authority);

    // Prepare liquidity providing phase
    let phase_info_cap = scenario.take_from_sender<PhaseInfoCap>();
    let mut phase_info = scenario.take_shared<PhaseInfo>();
    phase_info_cap.initialize(
        &mut phase_info,
        PHASE_DURATION,
        PHASE_DURATION,
        PHASE_DURATION,
        scenario.ctx(),
    );
    scenario.return_to_sender(phase_info_cap);

    (scenario, clock, phase_info)
}

/// build_pool_test_suite
/// Forwards the phase info to the liquidity providing phase and initializes the pool.
/// It also sets the deposit enabled flag for the pools.
public fun build_pool_test_suite(authority: address): (Scenario, Clock, PhaseInfo, PoolFactory) {
    let (mut scenario, mut clock, mut phase_info) = build_phase_test_suite(authority);

    scenario.next_tx(authority);

    // Settling phase to liquidity providing phase
    let phase_info_cap = scenario.take_from_sender<PhaseInfoCap>();

    clock.increment_for_testing(PHASE_DURATION);
    phase_info_cap.next(&mut phase_info, &clock, scenario.ctx());
    phase_info.assert_liquidity_providing_phase();

    scenario.return_to_sender(phase_info_cap);

    // Create and initialize pool
    let pool_cap = scenario.take_from_sender<PoolCap>();
    let mut pool_factory = scenario.take_shared<PoolFactory>();

    pool_cap.create_pool<SUI>(&mut pool_factory, TEST_POOL_1_RISK, scenario.ctx());
    pool_cap.create_pool<SUI>(&mut pool_factory, TEST_POOL_2_RISK, scenario.ctx());

    let pool = pool_factory.get_pool_by_risk_ratio_mut<SUI>(TEST_POOL_1_RISK);
    pool_cap.set_deposit_enabled<SUI>(pool, true);
    pool.assert_deposit_enabled();

    let pool = pool_factory.get_pool_by_risk_ratio_mut<SUI>(TEST_POOL_2_RISK);
    pool_cap.set_deposit_enabled<SUI>(pool, true);
    pool.assert_deposit_enabled();

    scenario.return_to_sender(pool_cap);

    (scenario, clock, phase_info, pool_factory)
}

/// build_prize_pool_test_suite
/// Set pool factory for prize pool and also deposit liquidity into the pools.
public fun build_prize_pool_test_suite(
    authority: address,
): (Scenario, Clock, PhaseInfo, PoolFactory, PrizePool) {
    let (mut scenario, clock, phase_info, mut pool_factory) = build_pool_test_suite(authority);

    scenario.next_tx(authority);

    // Initilize prize pool
    let prize_pool_cap = scenario.take_from_sender<PrizePoolCap>();
    let mut prize_pool = scenario.take_shared<PrizePool>();
    prize_pool_cap.set_pool_factory(&mut prize_pool, object::id(&pool_factory), scenario.ctx());

    scenario.return_to_sender(prize_pool_cap);

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
    (scenario, clock, phase_info, pool_factory, prize_pool)
}
