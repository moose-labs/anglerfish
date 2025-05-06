#[test_only]
module anglerfish::pool_test_suite;

use anglerfish::lounge::LoungeRegistry;
use anglerfish::lounge_test_suite::{build_lounge_test_suite, build_initialized_lounge_test_suite};
use anglerfish::phase::{PhaseInfo, PhaseInfoCap};
use anglerfish::pool::{PoolCap, PoolRegistry};
use anglerfish::prize_pool::{Self, PrizePoolCap, PrizePool};
use anglerfish::round::{RoundRegistryCap, RoundRegistry};
use sui::balance::create_for_testing as create_balance_for_testing;
use sui::clock::Clock;
use sui::sui::SUI;
use sui::test_scenario::{Self, Scenario};

const PHASE_DURATION: u64 = 60;
const TEST_POOL_1_RISK: u64 = 2000;
const TEST_POOL_2_RISK: u64 = 5000;

/// build_pool_test_suite
public fun build_pool_test_suite(
    authority: address,
): (Scenario, Clock, PhaseInfo, PrizePool, LoungeRegistry, PoolRegistry) {
    let (scenario, clock, phase_info, prize_pool, lounge_registry) = build_lounge_test_suite(
        authority,
    );

    let pool_registry = scenario.take_shared<PoolRegistry>();

    (scenario, clock, phase_info, prize_pool, lounge_registry, pool_registry)
}

public fun build_liquidity_providing_phase_pool_test_suite(
    authority: address,
): (Scenario, Clock, PhaseInfo, PrizePool, LoungeRegistry, PoolRegistry) {
    let (
        mut scenario,
        mut clock,
        mut phase_info,
        prize_pool,
        lounge_registry,
    ) = build_initialized_lounge_test_suite(
        authority,
    );

    let mut pool_registry = scenario.take_shared<PoolRegistry>();

    // Create and initialize pool
    scenario.next_tx(authority);
    {
        let pool_cap = scenario.take_from_sender<PoolCap>();

        pool_cap.create_pool<SUI>(
            &mut pool_registry,
            &phase_info,
            TEST_POOL_1_RISK,
            scenario.ctx(),
        );
        pool_cap.create_pool<SUI>(
            &mut pool_registry,
            &phase_info,
            TEST_POOL_2_RISK,
            scenario.ctx(),
        );

        pool_cap.set_deposit_enabled<SUI>(&mut pool_registry, TEST_POOL_1_RISK, true);
        let pool = pool_registry.get_pool_by_risk_ratio<SUI>(TEST_POOL_1_RISK);
        pool.assert_deposit_enabled();

        pool_cap.set_deposit_enabled<SUI>(&mut pool_registry, TEST_POOL_2_RISK, true);
        let pool = pool_registry.get_pool_by_risk_ratio<SUI>(TEST_POOL_2_RISK);
        pool.assert_deposit_enabled();

        scenario.return_to_sender(pool_cap);
    };

    // Phase: Settling -> Liquidity Providing
    scenario.next_tx(authority);
    {
        let prize_pool_cap = scenario.take_from_sender<PrizePoolCap>();
        let round_registry_cap = scenario.take_from_sender<RoundRegistryCap>();
        let phase_info_cap = scenario.take_from_sender<PhaseInfoCap>();
        let mut round_registry = scenario.take_shared<RoundRegistry>();

        prize_pool::start_new_round(
            &prize_pool_cap,
            &round_registry_cap,
            &phase_info_cap,
            &mut phase_info,
            &mut round_registry,
            &prize_pool,
            &clock,
            scenario.ctx(),
        );

        clock.increment_for_testing(PHASE_DURATION);
        phase_info.assert_liquidity_providing_phase();

        test_scenario::return_shared(round_registry);
        scenario.return_to_sender(phase_info_cap);
        scenario.return_to_sender(prize_pool_cap);
        scenario.return_to_sender(round_registry_cap);
    };

    (scenario, clock, phase_info, prize_pool, lounge_registry, pool_registry)
}

public fun build_ticketing_phase_with_liquidity_pool_test_suite(
    authority: address,
): (Scenario, Clock, PhaseInfo, PrizePool, LoungeRegistry, PoolRegistry) {
    let (
        mut scenario,
        mut clock,
        mut phase_info,
        prize_pool,
        lounge_registry,
        mut pool_registry,
    ) = build_liquidity_providing_phase_pool_test_suite(
        authority,
    );

    phase_info.assert_liquidity_providing_phase();

    // Deposit liquidity into the pools
    // User 1:
    // - Deposit 1_000_000 into 20% pool (prize = 200_000)
    // - Deposit 2_000_000 into 50% pool (prize = 1_000_000)
    // User 2:
    // - Deposit 1_000_000 into 20% pool (prize = 200_000)
    // - Deposit 2_000_000 into 50% pool (prize = 1_000_000)
    // = Total liquidity is 6_000_000
    // = Total prize is 2_400_000
    let user1: address = @0x001;
    let user2: address = @0x002;

    scenario.next_tx(user1);
    {
        let balance = create_balance_for_testing<SUI>(1000000);
        pool_registry.deposit<SUI>(
            &phase_info,
            TEST_POOL_1_RISK,
            sui::coin::from_balance(balance, scenario.ctx()),
            scenario.ctx(),
        );

        let balance = create_balance_for_testing<SUI>(2000000);
        pool_registry.deposit<SUI>(
            &phase_info,
            TEST_POOL_2_RISK,
            sui::coin::from_balance(balance, scenario.ctx()),
            scenario.ctx(),
        );
    };

    scenario.next_tx(user2);
    {
        let balance = create_balance_for_testing<SUI>(1000000);
        pool_registry.deposit<SUI>(
            &phase_info,
            TEST_POOL_1_RISK,
            sui::coin::from_balance(balance, scenario.ctx()),
            scenario.ctx(),
        );

        let balance = create_balance_for_testing<SUI>(2000000);
        pool_registry.deposit<SUI>(
            &phase_info,
            TEST_POOL_2_RISK,
            sui::coin::from_balance(balance, scenario.ctx()),
            scenario.ctx(),
        );
    };

    // Phase: Liquidity Providing -> Ticketing
    scenario.next_tx(authority);
    {
        let phase_info_cap = scenario.take_from_sender<PhaseInfoCap>();

        clock.increment_for_testing(PHASE_DURATION);

        phase_info_cap.next_entry(&mut phase_info, &clock, scenario.ctx());
        phase_info.assert_ticketing_phase();

        scenario.return_to_sender(phase_info_cap);
    };

    (scenario, clock, phase_info, prize_pool, lounge_registry, pool_registry)
}

public fun build_ticketing_phase_no_liquidity_pool_test_suite(
    authority: address,
): (Scenario, Clock, PhaseInfo, PrizePool, LoungeRegistry, PoolRegistry) {
    let (
        mut scenario,
        mut clock,
        mut phase_info,
        prize_pool,
        lounge_registry,
        pool_registry,
    ) = build_liquidity_providing_phase_pool_test_suite(
        authority,
    );

    phase_info.assert_liquidity_providing_phase();

    // Phase: Liquidity Providing -> Ticketing
    scenario.next_tx(authority);
    {
        let phase_info_cap = scenario.take_from_sender<PhaseInfoCap>();

        clock.increment_for_testing(PHASE_DURATION);

        phase_info_cap.next_entry(&mut phase_info, &clock, scenario.ctx());
        phase_info.assert_ticketing_phase();

        scenario.return_to_sender(phase_info_cap);
    };

    (scenario, clock, phase_info, prize_pool, lounge_registry, pool_registry)
}
