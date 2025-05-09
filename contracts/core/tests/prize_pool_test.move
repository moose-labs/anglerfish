#[test_only]
module anglerfish::prize_pool_test;

use anglerfish::iterator::IteratorCap;
use anglerfish::lounge::Lounge;
use anglerfish::phase;
use anglerfish::pool_test_suite::{
    build_liquidity_providing_phase_pool_test_suite,
    build_ticketing_phase_no_liquidity_pool_test_suite,
    build_ticketing_phase_with_liquidity_pool_test_suite
};
use anglerfish::prize_pool::{Self, PrizePoolCap};
use anglerfish::round::{RoundRegistry, Round};
use sui::balance::create_for_testing as create_balance_for_testing;
use sui::coin::{from_balance, Coin};
use sui::random::Random;
use sui::sui::SUI;
use sui::test_scenario;
use sui::test_utils;

const AUTHORITY: address = @0xAAA;

// user scenarios
// - cannot purchase ticket outside ticketing phase
// - cannot purchase ticket while pool is reached max players
// - cannot purchase ticket with zero amount (0 value)
// - cannot purchase ticket with zero value (0 < purcahse_value < ticket_price)
// - purchase tickets should floored to ticket price
// - can purchase ticket
//     - fee reserves should increased
//     - protocol fee reserves should increased
//     - treasury reserves should increased
//     - ticket reserves should increased
//     - user tickets should increased
//     - total ticket purchased should increased
// - referrer fee should be distributed to the referrer
// - can determine winner (player win)
//     - lounge should be created with prize reserves
//     - fee reserves should be distributed to the pools
// - can determine winner (player lose)
//     - lounge should be non-existent
//     - ticket reserves should be distributed to the pools
//     - fee reserves should be distributed to the pools

const USER1: address = @0x001;
const USER2: address = @0x002;
const REFERRER: address = @0x003;
const PHASE_DURATION: u64 = 60;

#[test]
#[expected_failure(abort_code = phase::ErrorNotTicketingPhase)]
fun test_cannot_purchase_ticket_outside_ticketing_phase() {
    let (
        mut scenario,
        mut clock,
        mut phase_info,
        mut prize_pool,
        lounge_registry,
        pool_registry,
    ) = build_liquidity_providing_phase_pool_test_suite(
        AUTHORITY,
    );

    phase_info.assert_ticketing_phase();

    // Forward phase to drawing phase to test
    scenario.next_tx(AUTHORITY);
    {
        let iter_cap = scenario.take_from_sender<IteratorCap>();
        clock.increment_for_testing(PHASE_DURATION);
        phase::next(&iter_cap, &mut phase_info, &clock, scenario.ctx());
        scenario.return_to_sender(iter_cap);
    };

    scenario.next_tx(USER1);
    {
        let coin = from_balance(create_balance_for_testing<SUI>(100), scenario.ctx());
        let round_number = phase_info.get_current_round_number();
        let round_registry = scenario.take_shared<RoundRegistry>();
        let round_id = round_registry.get_round_id(round_number).extract();
        let mut round = scenario.take_shared_by_id<Round>(round_id);
        let refund_coin = prize_pool.purchase_ticket<SUI>(
            &round_registry,
            &mut round,
            &phase_info,
            coin,
            option::none(),
            scenario.ctx(),
        );

        assert!(refund_coin.value() == 50);
        refund_coin.burn_for_testing();

        test_scenario::return_shared(round);
        test_scenario::return_shared(round_registry);
    };

    test_scenario::return_shared(phase_info);
    test_scenario::return_shared(pool_registry);
    test_scenario::return_shared(lounge_registry);
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
        mut prize_pool,
        lounge_registry,
        pool_registry,
    ) = build_ticketing_phase_no_liquidity_pool_test_suite(
        AUTHORITY,
    );

    scenario.next_tx(USER1);
    {
        let coin = from_balance(create_balance_for_testing<SUI>(0), scenario.ctx());
        let round_number = phase_info.get_current_round_number();
        let round_registry = scenario.take_shared<RoundRegistry>();
        let round_id = round_registry.get_round_id(round_number).extract();
        let mut round = scenario.take_shared_by_id<Round>(round_id);
        let refund_coin = prize_pool.purchase_ticket<SUI>(
            &round_registry,
            &mut round,
            &phase_info,
            coin,
            option::none(),
            scenario.ctx(),
        );

        assert!(refund_coin.value() == 0);
        refund_coin.burn_for_testing();

        test_scenario::return_shared(round);
        test_scenario::return_shared(round_registry);
    };

    test_scenario::return_shared(phase_info);
    test_scenario::return_shared(pool_registry);
    test_scenario::return_shared(lounge_registry);
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
        mut prize_pool,
        lounge_registry,
        pool_registry,
    ) = build_ticketing_phase_no_liquidity_pool_test_suite(
        AUTHORITY,
    );

    assert!(prize_pool.get_price_per_ticket() == 100);

    scenario.next_tx(USER1);
    {
        let coin = from_balance(create_balance_for_testing<SUI>(50), scenario.ctx());
        let round_number = phase_info.get_current_round_number();
        let round_registry = scenario.take_shared<RoundRegistry>();
        let round_id = round_registry.get_round_id(round_number).extract();
        let mut round = scenario.take_shared_by_id<Round>(round_id);
        let refund_coin = prize_pool.purchase_ticket<SUI>(
            &round_registry,
            &mut round,
            &phase_info,
            coin,
            option::none(),
            scenario.ctx(),
        );

        assert!(refund_coin.value() == 50);
        refund_coin.burn_for_testing();

        test_scenario::return_shared(round);
        test_scenario::return_shared(round_registry);
    };

    test_scenario::return_shared(phase_info);
    test_scenario::return_shared(pool_registry);
    test_scenario::return_shared(lounge_registry);
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
        mut prize_pool,
        lounge_registry,
        pool_registry,
    ) = build_ticketing_phase_no_liquidity_pool_test_suite(
        AUTHORITY,
    );

    assert!(prize_pool.get_price_per_ticket() == 100);
    scenario.next_tx(USER1);
    {
        let coin = from_balance(create_balance_for_testing<SUI>(250), scenario.ctx());
        let round_number = phase_info.get_current_round_number();
        let round_registry = scenario.take_shared<RoundRegistry>();
        let round_id = round_registry.get_round_id(round_number).extract();
        let mut round = scenario.take_shared_by_id<Round>(round_id);

        assert!(round.get_player_tickets(USER1) == 0);

        let refund_coin = prize_pool.purchase_ticket<SUI>(
            &round_registry,
            &mut round,
            &phase_info,
            coin,
            option::none(),
            scenario.ctx(),
        );

        assert!(round.get_player_tickets(USER1) == 2);
        assert!(round.total_tickets() == 2);
        assert!(refund_coin.value() == 50); // change 50
        refund_coin.burn_for_testing();

        test_scenario::return_shared(round);
        test_scenario::return_shared(round_registry);
    };

    test_scenario::return_shared(phase_info);
    test_scenario::return_shared(pool_registry);
    test_scenario::return_shared(lounge_registry);
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
        mut prize_pool,
        lounge_registry,
        pool_registry,
    ) = build_ticketing_phase_no_liquidity_pool_test_suite(
        AUTHORITY,
    );

    assert!(prize_pool.get_price_per_ticket() == 100);

    scenario.next_tx(USER1);
    {
        let coin = from_balance(create_balance_for_testing<SUI>(1000), scenario.ctx());
        let round_number = phase_info.get_current_round_number();
        let round_registry = scenario.take_shared<RoundRegistry>();
        let round_id = round_registry.get_round_id(round_number).extract();
        let mut round = scenario.take_shared_by_id<Round>(round_id);
        let refund_coin = prize_pool.purchase_ticket<SUI>(
            &round_registry,
            &mut round,
            &phase_info,
            coin,
            option::none(),
            scenario.ctx(),
        );

        assert!(round.get_player_tickets(USER1) == 10);
        assert!(round.total_tickets() == 10);

        assert!(prize_pool.get_lp_fee_reserves_value<SUI>() == 350); // 25% of 1000 + 100 (+ 10% no referrer)
        assert!(prize_pool.get_protocol_fee_reserves_value<SUI>() == 50); // 5% of 1000
        assert!(prize_pool.get_treasury_reserves_value<SUI>() == 1000 - 250 - 50 - 100); // 1000 - 25% lp fee - 5% protocol fee - 10% referrer fee

        assert!(refund_coin.value() == 0);
        refund_coin.burn_for_testing();
        test_scenario::return_shared(round);
        test_scenario::return_shared(round_registry);
    };

    scenario.next_tx(USER2);
    {
        let coin = from_balance(create_balance_for_testing<SUI>(1000), scenario.ctx());
        let round_number = phase_info.get_current_round_number();
        let round_registry = scenario.take_shared<RoundRegistry>();
        let round_id = round_registry.get_round_id(round_number).extract();
        let mut round = scenario.take_shared_by_id<Round>(round_id);
        let refund_coin = prize_pool.purchase_ticket<SUI>(
            &round_registry,
            &mut round,
            &phase_info,
            coin,
            option::none(),
            scenario.ctx(),
        );

        assert!(round.get_player_tickets(USER2) == 10);
        assert!(round.total_tickets() == 20);

        assert!(prize_pool.get_lp_fee_reserves_value<SUI>() == 700); // 25% of 2000 + 200 (+ 10% no referrer)
        assert!(prize_pool.get_protocol_fee_reserves_value<SUI>() == 100); // 5% of 2000
        assert!(prize_pool.get_treasury_reserves_value<SUI>() == 2000 - 500 - 100 - 200); // 2000 - 25% lp fee - 5% protocol fee - 10% referrer fee

        assert!(refund_coin.value() == 0);
        refund_coin.burn_for_testing();
        test_scenario::return_shared(round);
        test_scenario::return_shared(round_registry);
    };

    test_scenario::return_shared(phase_info);
    test_scenario::return_shared(pool_registry);
    test_scenario::return_shared(lounge_registry);
    test_scenario::return_shared(prize_pool);
    clock.destroy_for_testing();
    scenario.end();
}

#[test]
fun test_referrer_should_received_fee() {
    let (
        mut scenario,
        clock,
        phase_info,
        mut prize_pool,
        lounge_registry,
        pool_registry,
    ) = build_ticketing_phase_no_liquidity_pool_test_suite(
        AUTHORITY,
    );

    assert!(prize_pool.get_price_per_ticket() == 100);

    scenario.next_tx(USER1);
    {
        let coin = from_balance(create_balance_for_testing<SUI>(1000), scenario.ctx());
        let round_number = phase_info.get_current_round_number();
        let round_registry = scenario.take_shared<RoundRegistry>();
        let round_id = round_registry.get_round_id(round_number).extract();
        let mut round = scenario.take_shared_by_id<Round>(round_id);

        let refund_coin = prize_pool.purchase_ticket<SUI>(
            &round_registry,
            &mut round,
            &phase_info,
            coin,
            option::some(REFERRER),
            scenario.ctx(),
        );

        refund_coin.burn_for_testing();
        test_scenario::return_shared(round);
        test_scenario::return_shared(round_registry);
    };

    scenario.next_tx(REFERRER);
    {
        let pool_coin = scenario.take_from_sender<Coin<SUI>>();
        assert!(pool_coin.value() == 100); // 10% of 1000
        pool_coin.burn_for_testing();
    };

    test_scenario::return_shared(phase_info);
    test_scenario::return_shared(pool_registry);
    test_scenario::return_shared(lounge_registry);
    test_scenario::return_shared(prize_pool);
    clock.destroy_for_testing();
    scenario.end();
}

#[test]
fun test_draw_on_no_liquidity() {
    let (
        mut scenario,
        mut clock,
        mut phase_info,
        mut prize_pool,
        mut lounge_registry,
        mut pool_registry,
    ) = build_ticketing_phase_no_liquidity_pool_test_suite(
        AUTHORITY,
    );

    // Validate the prize is empty
    {
        assert!(prize_pool.get_total_prize_reserves_value<SUI>(&pool_registry) == 0);
    };

    scenario.next_tx(USER1);
    {
        let coin = from_balance(create_balance_for_testing<SUI>(1000000), scenario.ctx());
        let round_number = phase_info.get_current_round_number();
        let round_registry = scenario.take_shared<RoundRegistry>();
        let round_id = round_registry.get_round_id(round_number).extract();
        let mut round = scenario.take_shared_by_id<Round>(round_id);
        let refund_coin = prize_pool.purchase_ticket<SUI>(
            &round_registry,
            &mut round,
            &phase_info,
            coin,
            option::none(),
            scenario.ctx(),
        );

        assert!(round.get_player_tickets(USER1) == 10000);
        assert!(refund_coin.value() == 0);

        refund_coin.burn_for_testing();
        test_scenario::return_shared(round);
        test_scenario::return_shared(round_registry);
    };

    // iterate to Drawing
    scenario.next_tx(AUTHORITY);
    {
        let iter_cap = scenario.take_from_sender<IteratorCap>();

        clock.increment_for_testing(PHASE_DURATION);
        phase::next(&iter_cap, &mut phase_info, &clock, scenario.ctx());

        scenario.return_to_sender(iter_cap);
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
        let iter_cap = scenario.take_from_sender<IteratorCap>();
        let round_number = phase_info.get_current_round_number();
        let round_registry = scenario.take_shared<RoundRegistry>();
        let round_id = round_registry.get_round_id(round_number).extract();
        let mut round = scenario.take_shared_by_id<Round>(round_id);

        prize_pool::draw<SUI>(
            &iter_cap,
            &prize_pool,
            &mut phase_info,
            &pool_registry,
            &round_registry,
            &mut round,
            &random,
            &clock,
            scenario.ctx(),
        );

        // should automatically move from Drawing to Distributing phase
        phase_info.assert_distributing_phase();

        let prize_reserves = prize_pool.get_total_prize_reserves_value<SUI>(&pool_registry);
        assert!(round.get_winner().is_some());
        assert!(prize_reserves == 0); // proof of no liquidity

        prize_pool::distribute<SUI>(
            &iter_cap,
            &mut phase_info,
            &mut prize_pool,
            &mut pool_registry,
            &mut lounge_registry,
            &round_registry,
            &mut round,
            &clock,
            scenario.ctx(),
        );

        // should automatically move from Distributing phase to Settling phase
        phase_info.assert_settling_phase();

        scenario.return_to_sender(iter_cap);
        test_scenario::return_shared(round);
        test_scenario::return_shared(round_registry);
        test_scenario::return_shared(random);
    };

    // Check winner record still the same
    scenario.next_tx(AUTHORITY);
    {
        let round_number = phase_info.get_current_round_number();
        let round_registry = scenario.take_shared<RoundRegistry>();
        let round_id = round_registry.get_round_id(round_number).extract();
        let round = scenario.take_shared_by_id<Round>(round_id);
        assert!(round.get_winner() == option::some(USER1));
        assert!(round.get_prize_amount() == 0);

        test_scenario::return_shared(round);
        test_scenario::return_shared(round_registry);
    };

    // Check the lounge not created
    {
        let round_number = phase_info.get_current_round_number();
        let lounge_id = lounge_registry.get_lounge_id(round_number).extract();
        let lounge = scenario.take_shared_by_id<Lounge<SUI>>(lounge_id);

        assert!(lounge.get_recipient() == USER1);
        assert!(lounge.get_prize_reserves_value() == 0);
        test_scenario::return_shared(lounge);
    };

    // Check the fee distribution
    scenario.next_tx(AUTHORITY);
    {
        let prize_pool_cap = scenario.take_from_sender<PrizePoolCap>();
        let protocol_fee_coin = prize_pool_cap.claim_protocol_fee<SUI>(
            &mut prize_pool,
            scenario.ctx(),
        );
        assert!(protocol_fee_coin.value() == 50000); // 5% of 1000000

        let treasury_fee_coin = prize_pool_cap.claim_treasury_reserve<SUI>(
            &mut prize_pool,
            scenario.ctx(),
        );
        assert!(treasury_fee_coin.value() == 600000); // 1000000 - 25% lp fee - 5% protocol fee - 10% referrer fee

        test_utils::destroy(protocol_fee_coin);
        test_utils::destroy(treasury_fee_coin);
        scenario.return_to_sender(prize_pool_cap);
    };

    test_scenario::return_shared(phase_info);
    test_scenario::return_shared(pool_registry);
    test_scenario::return_shared(lounge_registry);
    test_scenario::return_shared(prize_pool);
    clock.destroy_for_testing();
    scenario.end();
}

#[test]
fun test_draw_on_no_ticket_purchased() {
    let (
        mut scenario,
        mut clock,
        mut phase_info,
        mut prize_pool,
        mut lounge_registry,
        mut pool_registry,
    ) = build_ticketing_phase_with_liquidity_pool_test_suite(
        AUTHORITY,
    );

    {
        let round_number = phase_info.get_current_round_number();
        let round_registry = scenario.take_shared<RoundRegistry>();
        let round_id = round_registry.get_round_id(round_number).extract();
        let round = scenario.take_shared_by_id<Round>(round_id);

        assert!(round.total_tickets() == 0);

        test_scenario::return_shared(round);
        test_scenario::return_shared(round_registry);
    };

    // Forward phase to drawing
    scenario.next_tx(AUTHORITY);
    {
        let iter_cap = scenario.take_from_sender<IteratorCap>();

        clock.increment_for_testing(PHASE_DURATION);
        phase::next(&iter_cap, &mut phase_info, &clock, scenario.ctx());

        scenario.return_to_sender(iter_cap);
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
        let iter_cap = scenario.take_from_sender<IteratorCap>();
        let round_number = phase_info.get_current_round_number();
        let round_registry = scenario.take_shared<RoundRegistry>();
        let round_id = round_registry.get_round_id(round_number).extract();
        let mut round = scenario.take_shared_by_id<Round>(round_id);

        prize_pool::draw<SUI>(
            &iter_cap,
            &prize_pool,
            &mut phase_info,
            &pool_registry,
            &round_registry,
            &mut round,
            &random,
            &clock,
            scenario.ctx(),
        );

        // should automatically move from Drawing to Distributing phase
        phase_info.assert_distributing_phase();

        prize_pool::distribute<SUI>(
            &iter_cap,
            &mut phase_info,
            &mut prize_pool,
            &mut pool_registry,
            &mut lounge_registry,
            &round_registry,
            &mut round,
            &clock,
            scenario.ctx(),
        );

        // should automatically move from Distributing phase to Settling phase
        phase_info.assert_settling_phase();

        scenario.return_to_sender(iter_cap);
        test_scenario::return_shared(random);
        test_scenario::return_shared(round);
        test_scenario::return_shared(round_registry);
    };

    // Check variables
    scenario.next_tx(AUTHORITY);
    {
        let round_number = phase_info.get_current_round_number();
        let round_registry = scenario.take_shared<RoundRegistry>();
        let round_id = round_registry.get_round_id(round_number).extract();
        let round = scenario.take_shared_by_id<Round>(round_id);

        assert!(round.get_winner() == option::none());
        assert!(round.get_prize_amount() == 2400000);
        assert!(lounge_registry.is_lounge_available(1) == false);
        assert!(prize_pool.get_lp_fee_reserves_value<SUI>() == 0);
        assert!(prize_pool.get_protocol_fee_reserves_value<SUI>() == 0);
        assert!(prize_pool.get_treasury_reserves_value<SUI>() == 0);

        test_scenario::return_shared(round);
        test_scenario::return_shared(round_registry);
    };

    test_scenario::return_shared(phase_info);
    test_scenario::return_shared(pool_registry);
    test_scenario::return_shared(lounge_registry);
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
        mut prize_pool,
        mut lounge_registry,
        mut pool_registry,
    ) = build_ticketing_phase_with_liquidity_pool_test_suite(
        AUTHORITY,
    );

    assert!(prize_pool.get_price_per_ticket() == 100);
    assert!(pool_registry.get_total_reserves_value<SUI>() == 6000000);
    assert!(pool_registry.get_total_prize_reserves_value<SUI>() == 2400000);

    scenario.next_tx(USER1);
    {
        let coin = from_balance(create_balance_for_testing<SUI>(5000000), scenario.ctx()); // 50000 ticket vs 40000 lp ticket, player win for sure
        let round_number = phase_info.get_current_round_number();
        let round_registry = scenario.take_shared<RoundRegistry>();
        let round_id = round_registry.get_round_id(round_number).extract();
        let mut round = scenario.take_shared_by_id<Round>(round_id);

        let refund_coin = prize_pool.purchase_ticket<SUI>(
            &round_registry,
            &mut round,
            &phase_info,
            coin,
            option::none(),
            scenario.ctx(),
        );

        assert!(round.get_player_tickets(USER1)== 50000);

        assert!(prize_pool.get_lp_fee_reserves_value<SUI>() == 1250000 + 500000); // 25% of 5000000 + 10% no referrer
        assert!(prize_pool.get_protocol_fee_reserves_value<SUI>() == 250000);
        assert!(
            prize_pool.get_treasury_reserves_value<SUI>() == 5000000 - 1250000 - 250000 - 500000,
        ); // ticket_cost - 25% lp fee - 5% protocol fee - 10% referrer fee

        assert!(refund_coin.value() == 0);
        refund_coin.burn_for_testing();
        test_scenario::return_shared(round);
        test_scenario::return_shared(round_registry);
    };

    // Forward phase to drawing
    scenario.next_tx(AUTHORITY);
    {
        let iter_cap = scenario.take_from_sender<IteratorCap>();
        clock.increment_for_testing(PHASE_DURATION);
        phase::next(&iter_cap, &mut phase_info, &clock, scenario.ctx());
        scenario.return_to_sender(iter_cap);
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
        let iter_cap = scenario.take_from_sender<IteratorCap>();
        let round_number = phase_info.get_current_round_number();
        let round_registry = scenario.take_shared<RoundRegistry>();
        let round_id = round_registry.get_round_id(round_number).extract();
        let mut round = scenario.take_shared_by_id<Round>(round_id);

        prize_pool::draw<SUI>(
            &iter_cap,
            &prize_pool,
            &mut phase_info,
            &pool_registry,
            &round_registry,
            &mut round,
            &random,
            &clock,
            scenario.ctx(),
        );
        // should automatically move from Drawing to Distributing phase
        phase_info.assert_distributing_phase();

        let prize_reserves = prize_pool.get_total_prize_reserves_value<SUI>(&pool_registry);
        assert!(prize_reserves == 2400000);
        assert!(round.get_winner().is_some());

        prize_pool::distribute<SUI>(
            &iter_cap,
            &mut phase_info,
            &mut prize_pool,
            &mut pool_registry,
            &mut lounge_registry,
            &round_registry,
            &mut round,
            &clock,
            scenario.ctx(),
        );

        // should automatically move from Distributing phase to Settling phase
        phase_info.assert_settling_phase();

        scenario.return_to_sender(iter_cap);
        test_scenario::return_shared(random);
        test_scenario::return_shared(round);
        test_scenario::return_shared(round_registry);
    };

    // Check winner record still the same
    scenario.next_tx(AUTHORITY);
    {
        let round_number = phase_info.get_current_round_number();
        let round_registry = scenario.take_shared<RoundRegistry>();
        let round_id = round_registry.get_round_id(round_number).extract();
        let round = scenario.take_shared_by_id<Round>(round_id);

        assert!(round.get_winner() == option::some(USER1));
        assert!(round.get_prize_amount() == 2400000);

        test_scenario::return_shared(round);
        test_scenario::return_shared(round_registry);
    };

    // Check the lounge created
    scenario.next_tx(USER1);
    {
        let round_number = phase_info.get_current_round_number();
        let lounge_id = lounge_registry.get_lounge_id(round_number).extract();
        let mut lounge = scenario.take_shared_by_id<Lounge<SUI>>(lounge_id);

        assert!(lounge.get_recipient() == USER1);
        assert!(lounge.get_prize_reserves_value<SUI>() == 2400000);

        let prize_coin = lounge_registry.claim<SUI>(&mut lounge, scenario.ctx());
        assert!(prize_coin.value() == 2400000);

        test_utils::destroy(prize_coin);
        test_scenario::return_shared(lounge);
    };

    // Check the fee distribution
    scenario.next_tx(AUTHORITY);
    {
        let prize_pool_cap = scenario.take_from_sender<PrizePoolCap>();
        let protocol_fee_coin = prize_pool_cap.claim_protocol_fee<SUI>(
            &mut prize_pool,
            scenario.ctx(),
        );

        assert!(protocol_fee_coin.value() == 250000);

        let treasury_fee_coin = prize_pool_cap.claim_treasury_reserve<SUI>(
            &mut prize_pool,
            scenario.ctx(),
        );

        assert!(treasury_fee_coin.value() == 3000000); // 5000000 - 25% lp fee - 5% protocol fee - 10% referrer fee

        test_utils::destroy(protocol_fee_coin);
        test_utils::destroy(treasury_fee_coin);
        scenario.return_to_sender(prize_pool_cap);
    };

    // Check reserves and prize after settled
    {
        // Liquidity on the pools before settling
        // - 2m with 20% risk (prize = 200_000 per user = 400_000 total)
        // - 4m with 50% risk (prize = 1_000_000 per user = 2_000_000 total)
        // Total liquidity is 6_000_000
        // Total prize is 2_400_000

        // Pool loss
        // 20% pool loss = 2_000_000 - 400_000 = 1_600_000
        // 50% pool loss = 4_000_000 - 2_000_000 = 2_000_000
        // New pool reserves = 1_600_000 + 2_000_000 = 3_600_000

        // Total fee = 1_250_000 + 500_000 (+10% no referrer)
        // Distributed to the pools
        // 20% pool get = (20/(20+50) * 1_750_000) = 500_000
        // 50% pool get = (50/(20+50) * 1_750_000) = 1_250_000
        assert!(pool_registry.get_total_reserves_value<SUI>() == 3_600_000 + 500_000 + 1_250_000);

        // New prize reserves
        // 20% pool reserves = (1_600_000 + 500_000) * 20% = 420_000
        // 50% pool reserves = (2_000_000 + 1_250_000) * 50% = 1_625_000
        // Total prize reserves = 420_000 + 1_625_000 = 2045000
        assert!(pool_registry.get_total_prize_reserves_value<SUI>() == 2045000);
    };

    test_scenario::return_shared(phase_info);
    test_scenario::return_shared(pool_registry);
    test_scenario::return_shared(lounge_registry);
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
        mut prize_pool,
        mut lounge_registry,
        mut pool_registry,
    ) = build_ticketing_phase_with_liquidity_pool_test_suite(
        AUTHORITY,
    );

    assert!(prize_pool.get_price_per_ticket() == 100);
    assert!(pool_registry.get_total_reserves_value<SUI>() == 6000000);
    assert!(pool_registry.get_total_prize_reserves_value<SUI>() == 2400000);

    scenario.next_tx(USER1);
    {
        let coin = from_balance(create_balance_for_testing<SUI>(100), scenario.ctx()); // 1 ticket
        let round_number = phase_info.get_current_round_number();
        let round_registry = scenario.take_shared<RoundRegistry>();
        let round_id = round_registry.get_round_id(round_number).extract();
        let mut round = scenario.take_shared_by_id<Round>(round_id);
        let refund_coin = prize_pool.purchase_ticket<SUI>(
            &round_registry,
            &mut round,
            &phase_info,
            coin,
            option::none(),
            scenario.ctx(),
        );

        assert!(round.get_player_tickets(USER1) == 1);

        assert!(prize_pool.get_lp_fee_reserves_value<SUI>() == 35); // 25% of 100 + 10% no referrer
        assert!(prize_pool.get_protocol_fee_reserves_value<SUI>() == 5);
        assert!(prize_pool.get_treasury_reserves_value<SUI>() == 100 - 25 - 5 - 10); // 100 - 25% lp fee - 5% protocol fee - 10% referrer fee

        assert!(refund_coin.value() == 0);
        refund_coin.burn_for_testing();
        test_scenario::return_shared(round);
        test_scenario::return_shared(round_registry);
    };

    // Forward phase to drawing
    scenario.next_tx(AUTHORITY);
    {
        let iter_cap = scenario.take_from_sender<IteratorCap>();
        clock.increment_for_testing(PHASE_DURATION);
        phase::next(&iter_cap, &mut phase_info, &clock, scenario.ctx());
        scenario.return_to_sender(iter_cap);
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
        let iter_cap = scenario.take_from_sender<IteratorCap>();
        let round_number = phase_info.get_current_round_number();
        let round_registry = scenario.take_shared<RoundRegistry>();
        let round_id = round_registry.get_round_id(round_number).extract();
        let mut round = scenario.take_shared_by_id<Round>(round_id);

        prize_pool::draw<SUI>(
            &iter_cap,
            &prize_pool,
            &mut phase_info,
            &pool_registry,
            &round_registry,
            &mut round,
            &random,
            &clock,
            scenario.ctx(),
        );
        // should automatically move from Drawing to Distributing phase
        phase_info.assert_distributing_phase();

        let prize_reserves = prize_pool.get_total_prize_reserves_value<SUI>(&pool_registry);
        assert!(round.get_winner().is_none());
        assert!(prize_reserves > 0); // proof of no liquidity

        prize_pool::distribute<SUI>(
            &iter_cap,
            &mut phase_info,
            &mut prize_pool,
            &mut pool_registry,
            &mut lounge_registry,
            &round_registry,
            &mut round,
            &clock,
            scenario.ctx(),
        );

        // should automatically move from Distributing phase to Settling phase
        phase_info.assert_settling_phase();

        scenario.return_to_sender(iter_cap);
        test_scenario::return_shared(random);
        test_scenario::return_shared(round);
        test_scenario::return_shared(round_registry);
    };

    // Check winner record still the same
    scenario.next_tx(AUTHORITY);
    {
        let round_number = phase_info.get_current_round_number();
        let round_registry = scenario.take_shared<RoundRegistry>();
        let round_id = round_registry.get_round_id(round_number).extract();
        let round = scenario.take_shared_by_id<Round>(round_id);

        assert!(round.get_winner() == option::none());
        assert!(round.get_prize_amount() == 2400000);

        test_scenario::return_shared(round);
        test_scenario::return_shared(round_registry);
    };

    // Check the lounge created
    scenario.next_tx(AUTHORITY);
    {
        assert!(lounge_registry.is_lounge_available(1) == false);
    };

    // Check the fee distribution
    scenario.next_tx(AUTHORITY);
    {
        let prize_pool_cap = scenario.take_from_sender<PrizePoolCap>();
        let protocol_fee_coin = prize_pool_cap.claim_protocol_fee<SUI>(
            &mut prize_pool,
            scenario.ctx(),
        );
        assert!(protocol_fee_coin.value() == 5);

        let treasury_fee_coin = prize_pool_cap.claim_treasury_reserve<SUI>(
            &mut prize_pool,
            scenario.ctx(),
        );
        assert!(treasury_fee_coin.value() == 60);
        test_utils::destroy(protocol_fee_coin);
        test_utils::destroy(treasury_fee_coin);
        scenario.return_to_sender(prize_pool_cap);
    };

    // TVL should increase and prize reserves changes
    {
        // Liquidity on the pools before settling
        // - 2m with 20% risk (prize = 200_000 per user, = 400_000 total)
        // - 4m with 50% risk (prize = 1_000_000 per user, = 2_000_000 total)
        // Total liquidity is 6_000_000
        // Total prize is 2_400_000

        // Total fee = 250_000
        // Distributed to the pools
        // 20% pool get = (20 / (20 + 50) * 35) = 10
        // 50% pool get = (50 / (20 + 50) * 35) = 25
        assert!(pool_registry.get_total_reserves_value<SUI>() == 6000000 + 10 + 25);

        // New prize reserves
        // 20% pool reserves = (2_000_000 + 10) * 20% = 400_002
        // 50% pool reserves = (4_000_000 + 25) * 50% = 2_000_012
        // Total prize reserves = 400_002 + 2_000_012 = 2_400_009
        assert!(pool_registry.get_total_prize_reserves_value<SUI>() == 2400014);
    };

    test_scenario::return_shared(phase_info);
    test_scenario::return_shared(pool_registry);
    test_scenario::return_shared(lounge_registry);
    test_scenario::return_shared(prize_pool);
    clock.destroy_for_testing();
    scenario.end();
}
