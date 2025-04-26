#[test_only]
module red_ocean::prize_pool_test;

use red_ocean::base_test_suite::build_base_test_suite;
use red_ocean::lounge::LoungeCap;
use red_ocean::phase::{Self, PhaseInfoCap};
use red_ocean::pool::PoolCap;
use red_ocean::prize_pool::{Self, PrizePoolCap};
use red_ocean::prize_pool_test_suite::{
    build_prize_pool_test_suite,
    build_initialized_prize_pool_test_suite
};
use sui::balance::create_for_testing as create_balance_for_testing;
use sui::coin::from_balance;
use sui::random::Random;
use sui::sui::SUI;
use sui::test_scenario;

const AUTHORITY: address = @0xAAA;
const UNAUTHORIZED: address = @0xFFF;

/// Capability cases
/// - capability cannot be taken by an unauthorized user
/// - can set pool factory
/// - can set lounge factory
/// - can set max players
/// - can set price per ticket
/// - can set protocol fee
/// - can claim protocol fee
///
/// User scenarios
/// - cannot purchase ticket outside ticketing phase
/// - cannot purchase ticket while pool is reached max players
/// - cannot purchase ticket with zero amount (0 value)
/// - cannot purchase ticket with zero value (0 < purcahse_value < ticket_price)
/// - can purchase ticket
///     - fee reserves should increased
///     - protocol fee reserves should increased
///     - ticket reserves should increased
///     - user tickets should increased
///     - total ticket purchased should increased
/// - can determine winner (player win)
///     - lounge should be created with prize reserves
///     - fee reserves should be distributed to the pools
/// - can determine winner (player lose)
///     - lounge should be non-existent
///     - ticket reserves should be distributed to the pools
///     - fee reserves should be distributed to the pools
///

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
fun test_set_initialize_parameters() {
    let (
        mut scenario,
        clock,
        phase_info,
        pool_factory,
        lounge_factory,
        mut prize_pool,
    ) = build_prize_pool_test_suite(
        AUTHORITY,
    );

    // Set pool registry
    scenario.next_tx(AUTHORITY);
    {
        let pool_cap = scenario.take_from_sender<PrizePoolCap>();

        assert!(prize_pool.get_pool_registry().is_none());
        pool_cap.set_pool_registry(&mut prize_pool, object::id(&pool_factory), scenario.ctx());
        assert!(prize_pool.get_pool_registry().borrow() == object::id(&pool_factory));

        scenario.return_to_sender(pool_cap);
    };

    // Set lounge factory
    scenario.next_tx(AUTHORITY);
    {
        let pool_cap = scenario.take_from_sender<PrizePoolCap>();

        let lounge_id = object::id_from_address(@0x100);
        assert!(prize_pool.get_lounge_factory().is_none());
        pool_cap.set_lounge_factory(
            &mut prize_pool,
            lounge_id,
            scenario.ctx(),
        );
        assert!(prize_pool.get_lounge_factory().borrow() == lounge_id);

        scenario.return_to_sender(pool_cap);
    };

    // Set max players
    scenario.next_tx(AUTHORITY);
    {
        let pool_cap = scenario.take_from_sender<PrizePoolCap>();

        assert!(prize_pool.get_max_players() == 0);
        pool_cap.set_max_players(
            &mut prize_pool,
            2,
            scenario.ctx(),
        );
        assert!(prize_pool.get_max_players() == 2);

        scenario.return_to_sender(pool_cap);
    };

    // Set price per ticket
    scenario.next_tx(AUTHORITY);
    {
        let pool_cap = scenario.take_from_sender<PrizePoolCap>();

        assert!(prize_pool.get_price_per_ticket() == 0);
        pool_cap.set_price_per_ticket(
            &mut prize_pool,
            100,
            scenario.ctx(),
        );
        assert!(prize_pool.get_price_per_ticket() == 100);

        scenario.return_to_sender(pool_cap);
    };

    // Set fee bps
    scenario.next_tx(AUTHORITY);
    {
        let pool_cap = scenario.take_from_sender<PrizePoolCap>();

        assert!(prize_pool.get_fee_bps() == 2500); // default value
        pool_cap.set_fee_bps(
            &mut prize_pool,
            5000,
            scenario.ctx(),
        );
        assert!(prize_pool.get_fee_bps() == 5000);

        scenario.return_to_sender(pool_cap);
    };

    // Set protocol fee bps
    scenario.next_tx(AUTHORITY);
    {
        let pool_cap = scenario.take_from_sender<PrizePoolCap>();

        assert!(prize_pool.get_protocol_fee_bps() == 500); // default value
        pool_cap.set_protocol_fee_bps(
            &mut prize_pool,
            1000,
            scenario.ctx(),
        );
        assert!(prize_pool.get_protocol_fee_bps() == 1000);

        scenario.return_to_sender(pool_cap);
    };

    test_scenario::return_shared(phase_info);
    test_scenario::return_shared(pool_factory);
    test_scenario::return_shared(lounge_factory);
    test_scenario::return_shared(prize_pool);
    clock.destroy_for_testing();
    scenario.end();
}

// user scenarios
// - cannot purchase ticket outside ticketing phase
// - cannot purchase ticket while pool is reached max players
// - cannot purchase ticket with zero amount (0 value)
// - cannot purchase ticket with zero value (0 < purcahse_value < ticket_price)
// - purchase tickets should floored to ticket price
// - can purchase ticket
//     - fee reserves should increased
//     - protocol fee reserves should increased
//     - ticket reserves should increased
//     - user tickets should increased
//     - total ticket purchased should increased
// - can determine winner (player win)
//     - lounge should be created with prize reserves
//     - fee reserves should be distributed to the pools
// - can determine winner (player lose)
//     - lounge should be non-existent
//     - ticket reserves should be distributed to the pools
//     - fee reserves should be distributed to the pools

const USER1: address = @0x001;
const USER2: address = @0x002;
const PHASE_DURATION: u64 = 60;

#[test]
#[expected_failure(abort_code = phase::ErrorNotTicketingPhase)]
fun test_cannot_purchase_ticket_outside_ticketing_phase() {
    let (
        mut scenario,
        mut clock,
        mut phase_info,
        pool_factory,
        lounge_factory,
        mut prize_pool,
    ) = build_initialized_prize_pool_test_suite(
        AUTHORITY,
    );

    phase_info.assert_ticketing_phase();

    // Forward phase to drawing phase to test
    scenario.next_tx(AUTHORITY);
    {
        let phase_info_cap = scenario.take_from_sender<PhaseInfoCap>();
        clock.increment_for_testing(PHASE_DURATION);
        phase_info_cap.next(&mut phase_info, &clock, scenario.ctx());
        scenario.return_to_sender(phase_info_cap);
    };

    scenario.next_tx(USER1);
    {
        let coin = from_balance(create_balance_for_testing<SUI>(100), scenario.ctx());
        prize_pool.purchase_ticket<SUI>(&phase_info, coin, scenario.ctx());
    };

    test_scenario::return_shared(phase_info);
    test_scenario::return_shared(pool_factory);
    test_scenario::return_shared(lounge_factory);
    test_scenario::return_shared(prize_pool);
    clock.destroy_for_testing();
    scenario.end();
}

#[test]
#[expected_failure(abort_code = prize_pool::ErrorMaximumNumberOfPlayersReached)]
fun test_cannot_purchase_ticket_while_pool_reached_max_players() {
    let (
        mut scenario,
        clock,
        phase_info,
        pool_factory,
        lounge_factory,
        mut prize_pool,
    ) = build_initialized_prize_pool_test_suite(
        AUTHORITY,
    );

    scenario.next_tx(AUTHORITY);
    {
        let pool_cap = scenario.take_from_sender<PrizePoolCap>();
        pool_cap.set_max_players(&mut prize_pool, 1, scenario.ctx());
        scenario.return_to_sender(pool_cap);
    };

    assert!(prize_pool.get_max_players() == 1);
    assert!(prize_pool.get_price_per_ticket() == 100);

    scenario.next_tx(USER1);
    {
        let coin = from_balance(create_balance_for_testing<SUI>(100), scenario.ctx());
        prize_pool.purchase_ticket<SUI>(&phase_info, coin, scenario.ctx());
    };

    scenario.next_tx(USER2);
    {
        let coin = from_balance(create_balance_for_testing<SUI>(100), scenario.ctx());
        prize_pool.purchase_ticket<SUI>(&phase_info, coin, scenario.ctx());
    };

    test_scenario::return_shared(phase_info);
    test_scenario::return_shared(pool_factory);
    test_scenario::return_shared(lounge_factory);
    test_scenario::return_shared(prize_pool);
    clock.destroy_for_testing();
    scenario.end();
}

#[test]
#[expected_failure(abort_code = prize_pool::ErrorPurchaseAmountTooLow)]
fun test_cannot_purchase_ticket_with_zero_value() {
    let (
        mut scenario,
        clock,
        phase_info,
        pool_factory,
        lounge_factory,
        mut prize_pool,
    ) = build_initialized_prize_pool_test_suite(
        AUTHORITY,
    );

    scenario.next_tx(USER1);
    {
        let coin = from_balance(create_balance_for_testing<SUI>(0), scenario.ctx());
        prize_pool.purchase_ticket<SUI>(&phase_info, coin, scenario.ctx());
    };

    test_scenario::return_shared(phase_info);
    test_scenario::return_shared(pool_factory);
    test_scenario::return_shared(lounge_factory);
    test_scenario::return_shared(prize_pool);
    clock.destroy_for_testing();
    scenario.end();
}

#[test]
#[expected_failure(abort_code = prize_pool::ErrorPurchaseAmountTooLow)]
fun test_cannot_purchase_ticket_with_zero_ticket() {
    let (
        mut scenario,
        clock,
        phase_info,
        pool_factory,
        lounge_factory,
        mut prize_pool,
    ) = build_initialized_prize_pool_test_suite(
        AUTHORITY,
    );

    assert!(prize_pool.get_price_per_ticket() == 100);

    scenario.next_tx(USER1);
    {
        let coin = from_balance(create_balance_for_testing<SUI>(50), scenario.ctx());
        prize_pool.purchase_ticket<SUI>(&phase_info, coin, scenario.ctx());
    };

    test_scenario::return_shared(phase_info);
    test_scenario::return_shared(pool_factory);
    test_scenario::return_shared(lounge_factory);
    test_scenario::return_shared(prize_pool);
    clock.destroy_for_testing();
    scenario.end();
}

#[test]
fun test_purchase_tickets_should_floored_to_ticket_price() {
    let (
        mut scenario,
        clock,
        phase_info,
        pool_factory,
        lounge_factory,
        mut prize_pool,
    ) = build_initialized_prize_pool_test_suite(
        AUTHORITY,
    );

    assert!(prize_pool.get_price_per_ticket() == 100);
    assert!(prize_pool.get_player_tickets(&phase_info, USER1) == 0);
    scenario.next_tx(USER1);
    {
        let coin = from_balance(create_balance_for_testing<SUI>(250), scenario.ctx());
        prize_pool.purchase_ticket<SUI>(&phase_info, coin, scenario.ctx());
        assert!(prize_pool.get_player_tickets(&phase_info, USER1) == 2); // 2 tickets purchased, not 2.5
        assert!(prize_pool.get_total_purchased_tickets(&phase_info) == 2);
    };

    test_scenario::return_shared(phase_info);
    test_scenario::return_shared(pool_factory);
    test_scenario::return_shared(lounge_factory);
    test_scenario::return_shared(prize_pool);
    clock.destroy_for_testing();
    scenario.end();
}

#[test]
fun test_fee_distributions() {
    let (
        mut scenario,
        clock,
        phase_info,
        pool_factory,
        lounge_factory,
        mut prize_pool,
    ) = build_initialized_prize_pool_test_suite(
        AUTHORITY,
    );

    assert!(prize_pool.get_price_per_ticket() == 100);

    scenario.next_tx(USER1);
    {
        let coin = from_balance(create_balance_for_testing<SUI>(1000), scenario.ctx());
        prize_pool.purchase_ticket<SUI>(&phase_info, coin, scenario.ctx());

        assert!(prize_pool.get_player_tickets(&phase_info, USER1) == 10);
        assert!(prize_pool.get_total_purchased_tickets(&phase_info) == 10);

        assert!(prize_pool.get_fee_reserves_value<SUI>() == 250); // 25% of 1000
        assert!(prize_pool.get_protocol_fee_reserves_value<SUI>() == 50); // 5% of 1000
        assert!(prize_pool.get_ticket_reserves_value<SUI>() == 1000 - 250 - 50); // 1000 - fee - protocol fee
    };

    scenario.next_tx(USER2);
    {
        let coin = from_balance(create_balance_for_testing<SUI>(1000), scenario.ctx());
        prize_pool.purchase_ticket<SUI>(&phase_info, coin, scenario.ctx());

        assert!(prize_pool.get_player_tickets(&phase_info, USER2) == 10);
        assert!(prize_pool.get_total_purchased_tickets(&phase_info) == 20);

        assert!(prize_pool.get_fee_reserves_value<SUI>() == 500); // 25% of 2000
        assert!(prize_pool.get_protocol_fee_reserves_value<SUI>() == 100); // 5% of 2000
        assert!(prize_pool.get_ticket_reserves_value<SUI>() == 2000 - 500 - 100); // 2000 - fee - protocol fee
    };

    test_scenario::return_shared(phase_info);
    test_scenario::return_shared(pool_factory);
    test_scenario::return_shared(lounge_factory);
    test_scenario::return_shared(prize_pool);
    clock.destroy_for_testing();
    scenario.end();
}

#[test]
fun test_player_win_scenario() {
    let (
        mut scenario,
        mut clock,
        mut phase_info,
        mut pool_factory,
        mut lounge_factory,
        mut prize_pool,
    ) = build_initialized_prize_pool_test_suite(
        AUTHORITY,
    );

    assert!(prize_pool.get_price_per_ticket() == 100);
    assert!(pool_factory.get_total_reserves_value<SUI>() == 6000000);
    assert!(pool_factory.get_total_prize_reserves_value<SUI>() == 2400000);

    scenario.next_tx(USER1);
    {
        let coin = from_balance(create_balance_for_testing<SUI>(1000000), scenario.ctx());
        prize_pool.purchase_ticket<SUI>(&phase_info, coin, scenario.ctx());
        assert!(prize_pool.get_player_tickets(&phase_info, USER1) == 10000);

        assert!(prize_pool.get_fee_reserves_value<SUI>() == 250000);
        assert!(prize_pool.get_protocol_fee_reserves_value<SUI>() == 50000);
        assert!(prize_pool.get_ticket_reserves_value<SUI>() == 1000000 - 250000 - 50000);
    };

    // Forward phase to drawing
    scenario.next_tx(AUTHORITY);
    {
        let phase_info_cap = scenario.take_from_sender<PhaseInfoCap>();
        clock.increment_for_testing(PHASE_DURATION);
        phase_info_cap.next(&mut phase_info, &clock, scenario.ctx());
        scenario.return_to_sender(phase_info_cap);
    };

    // Update randomness state
    scenario.next_tx(@0x0);
    {
        let mut random = scenario.take_shared<Random>();
        random.update_randomness_state_for_testing(
            0,
            x"3F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F", // will return ticket number 8982
            scenario.ctx(),
        );
        test_scenario::return_shared(random);
    };

    // Draw the winner & settle the prize pool to the winner lounge
    scenario.next_tx(AUTHORITY);
    {
        let random = scenario.take_shared<Random>();
        let prize_pool_cap = scenario.take_from_sender<PrizePoolCap>();
        let phase_info_cap = scenario.take_from_sender<PhaseInfoCap>();
        prize_pool_cap.draw<SUI>(
            &phase_info_cap,
            &mut phase_info,
            &mut prize_pool,
            &pool_factory,
            &random,
            &clock,
            scenario.ctx(),
        );
        scenario.return_to_sender(phase_info_cap);

        let pool_cap = scenario.take_from_sender<PoolCap>();
        let lounge_cap = scenario.take_from_sender<LoungeCap>();
        prize_pool_cap.settle<SUI>(
            &pool_cap,
            &lounge_cap,
            &phase_info,
            &mut prize_pool,
            &mut pool_factory,
            &mut lounge_factory,
            scenario.ctx(),
        );

        // should still in settling phase
        phase_info.assert_settling_phase();

        scenario.return_to_sender(pool_cap);
        scenario.return_to_sender(lounge_cap);

        scenario.return_to_sender(prize_pool_cap);
        test_scenario::return_shared(random);
    };

    // Check winner record still the same
    scenario.next_tx(AUTHORITY);
    {
        assert!(prize_pool.get_round(1).get_winner() == option::some(USER1));
    };

    // Check the lounge created
    scenario.next_tx(USER1);
    {
        let lounge = lounge_factory.get_lounge_number_mut<SUI>(1);
        assert!(lounge.get_recipient() == USER1);
        assert!(lounge.get_prize_reserves_value<SUI>() == 2400000);

        let prize_coin = lounge.claim<SUI>(scenario.ctx());
        assert!(prize_coin.value() == 2400000);
        prize_coin.destroy_for_testing();
    };

    // TVL should decrease and prize reserves changes
    {
        // Liquidity on the pools before settling
        // - 2m with 20% risk (prize = 200_000 per user)
        // - 4m with 50% risk (prize = 1_000_000 per user)
        // Total liquidity is 6_000_000
        // Total prize is 2_400_000

        // Total fee = 250_000
        // Distributed to the pools
        // 20% pool get = 71428 (20/(20+50)*250_000)
        // 50% pool get = 178571 (50/(20+50)*250_000)
        assert!(pool_factory.get_total_reserves_value<SUI>() == 3600000 + 71428 + 178571);

        // New prize reserves
        // 20% pool reserves = 1_671_428 * 20% = 334_285
        // 50% pool reserves = 2_178_571 * 50% = 1_089_285
        // Total prize reserves = 334_285 + 1_089_285 = 1423570
        assert!(pool_factory.get_total_prize_reserves_value<SUI>() == 1423570);
    };

    test_scenario::return_shared(phase_info);
    test_scenario::return_shared(pool_factory);
    test_scenario::return_shared(lounge_factory);
    test_scenario::return_shared(prize_pool);
    clock.destroy_for_testing();
    scenario.end();
}

#[test]
fun test_lp_win_scenario() {
    let (
        mut scenario,
        mut clock,
        mut phase_info,
        mut pool_factory,
        mut lounge_factory,
        mut prize_pool,
    ) = build_initialized_prize_pool_test_suite(
        AUTHORITY,
    );

    assert!(prize_pool.get_price_per_ticket() == 100);
    assert!(pool_factory.get_total_reserves_value<SUI>() == 6000000);
    assert!(pool_factory.get_total_prize_reserves_value<SUI>() == 2400000);

    scenario.next_tx(USER1);
    {
        let coin = from_balance(create_balance_for_testing<SUI>(1000000), scenario.ctx());
        prize_pool.purchase_ticket<SUI>(&phase_info, coin, scenario.ctx());
        assert!(prize_pool.get_player_tickets(&phase_info, USER1) == 10000);

        assert!(prize_pool.get_fee_reserves_value<SUI>() == 250000);
        assert!(prize_pool.get_protocol_fee_reserves_value<SUI>() == 50000);
        assert!(prize_pool.get_ticket_reserves_value<SUI>() == 1000000 - 250000 - 50000);
    };

    // Forward phase to drawing
    scenario.next_tx(AUTHORITY);
    {
        let phase_info_cap = scenario.take_from_sender<PhaseInfoCap>();
        clock.increment_for_testing(PHASE_DURATION);
        phase_info_cap.next(&mut phase_info, &clock, scenario.ctx());
        scenario.return_to_sender(phase_info_cap);
    };

    // Update randomness state
    scenario.next_tx(@0x0);
    {
        let mut random = scenario.take_shared<Random>();
        random.update_randomness_state_for_testing(
            0,
            x"111F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F", // will return ticket number 19836
            scenario.ctx(),
        );
        test_scenario::return_shared(random);
    };

    // Draw the winner & settle the prize pool to the winner lounge
    scenario.next_tx(AUTHORITY);
    {
        let random = scenario.take_shared<Random>();
        let prize_pool_cap = scenario.take_from_sender<PrizePoolCap>();
        let phase_info_cap = scenario.take_from_sender<PhaseInfoCap>();
        prize_pool_cap.draw<SUI>(
            &phase_info_cap,
            &mut phase_info,
            &mut prize_pool,
            &pool_factory,
            &random,
            &clock,
            scenario.ctx(),
        );
        scenario.return_to_sender(phase_info_cap);

        let pool_cap = scenario.take_from_sender<PoolCap>();
        let lounge_cap = scenario.take_from_sender<LoungeCap>();
        prize_pool_cap.settle<SUI>(
            &pool_cap,
            &lounge_cap,
            &phase_info,
            &mut prize_pool,
            &mut pool_factory,
            &mut lounge_factory,
            scenario.ctx(),
        );

        phase_info.assert_settling_phase();

        scenario.return_to_sender(pool_cap);
        scenario.return_to_sender(lounge_cap);

        scenario.return_to_sender(prize_pool_cap);
        test_scenario::return_shared(random);
    };

    // Check winner record still the same
    scenario.next_tx(AUTHORITY);
    {
        assert!(prize_pool.get_round(1).get_winner() == option::none());
    };

    // Check the lounge created
    scenario.next_tx(USER1);
    {
        assert!(lounge_factory.is_lounge_available(1) == false);
    };

    // TVL should increase and prize reserves changes
    {
        // Liquidity on the pools before settling
        // - 2m with 20% risk (prize = 200_000 per user)
        // - 4m with 50% risk (prize = 1_000_000 per user)
        // Total liquidity is 6_000_000
        // Total prize is 2_400_000

        // Total fee = 250_000
        // Distributed to the pools
        // 20% pool get = 71428 (20/(20+50)*250_000)
        // 50% pool get = 178571 (50/(20+50)*250_000)

        // Total ticket fee = 700_000
        // Distributed to the pools
        // 20% pool get = 200000 (20/(20+50)*700_000)
        // 50% pool get = 500000 (50/(20+50)*700_000)
        assert!(
            pool_factory.get_total_reserves_value<SUI>() == 6000000 + 71428 + 178571 + 200000 + 500000,
        );

        // New prize reserves
        // 20% pool reserves = (2_000_000 + 71428 + 200_000) * 20% = 454_285
        // 50% pool reserves = (4_000_000 + 178571 + 500_000) * 50% = 2_339_285
        // Total prize reserves = 454_285 + 2_339_285 = 2793570
        assert!(pool_factory.get_total_prize_reserves_value<SUI>() == 2793570);
    };

    test_scenario::return_shared(phase_info);
    test_scenario::return_shared(pool_factory);
    test_scenario::return_shared(lounge_factory);
    test_scenario::return_shared(prize_pool);
    clock.destroy_for_testing();
    scenario.end();
}
