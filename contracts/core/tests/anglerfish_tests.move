/// Test suite for the Anglerfish Lottery System.
#[test_only]
module anglerfish::anglerfish_tests;

use anglerfish::errors;
use anglerfish::lounge::{Self, LoungeCap, LoungeRegistry};
use anglerfish::phase::{Self, PhaseInfo, PhaseInfoCap};
use anglerfish::pool::{Self, PoolCap, PoolRegistry};
use anglerfish::prize_pool::{Self, PrizePool, PrizePoolCap};
use anglerfish::round::{Self, Round, RoundRegistry, RoundRegistryCap};
use anglerfish::ticket_calculator;
use sui::clock;
use sui::coin;
use sui::random::{Random, create_for_testing as create_random_for_testing};
use sui::test_scenario::{Self as ts, Scenario};
use sui::test_utils::assert_eq;

// Test coin type
public struct TEST_COIN has drop {}

// Test constants
const ADMIN: address = @0x1;
const USER1: address = @0x2;
const USER2: address = @0x3;
const TICKET_PRICE: u64 = 1000;
const LP_FEE_BPS: u64 = 2500;
const PROTOCOL_FEE_BPS: u64 = 500;
const LIQUIDITY_DURATION: u64 = 1000;
const TICKETING_DURATION: u64 = 1000;
const RISK_RATIO_BPS: u64 = 5000;

// Helper to set up initial state
fun setup(
    scenario: &mut Scenario,
): (PrizePoolCap, PhaseInfoCap, PoolCap, LoungeCap, RoundRegistryCap) {
    scenario.next_tx(@0x0);
    {
        create_random_for_testing(scenario.ctx());
    };

    ts::next_tx(scenario, ADMIN);
    {
        prize_pool::init_for_testing(ts::ctx(scenario));
        phase::init_for_testing(ts::ctx(scenario));
        pool::init_for_testing(ts::ctx(scenario));
        lounge::init_for_testing(ts::ctx(scenario));
        round::init_for_testing(ts::ctx(scenario));
    };

    ts::next_tx(scenario, ADMIN);
    let prize_pool_cap = ts::take_from_sender<PrizePoolCap>(scenario);
    let phase_info_cap = ts::take_from_sender<PhaseInfoCap>(scenario);
    let pool_cap = ts::take_from_sender<PoolCap>(scenario);
    let lounge_cap = ts::take_from_sender<LoungeCap>(scenario);
    let round_registry_cap = ts::take_from_sender<RoundRegistryCap>(scenario);

    (prize_pool_cap, phase_info_cap, pool_cap, lounge_cap, round_registry_cap)
}

// Helper to initialize phase and create pool
fun initialize_phase_and_pool(
    scenario: &mut Scenario,
    phase_info_cap: &PhaseInfoCap,
    pool_cap: &PoolCap,
    prize_pool_cap: &PrizePoolCap,
) {
    ts::next_tx(scenario, ADMIN);
    let mut phase_info = ts::take_shared<PhaseInfo>(scenario);
    let mut pool_registry = ts::take_shared<PoolRegistry>(scenario);
    let mut prize_pool = ts::take_shared<PrizePool>(scenario);

    phase::initialize(
        phase_info_cap,
        &mut phase_info,
        LIQUIDITY_DURATION,
        TICKETING_DURATION,
        ts::ctx(scenario),
    );

    pool::create_pool<TEST_COIN>(
        pool_cap,
        &mut pool_registry,
        &phase_info,
        RISK_RATIO_BPS,
        ts::ctx(scenario),
    );

    prize_pool::set_price_per_ticket(prize_pool_cap, &mut prize_pool, TICKET_PRICE);
    prize_pool::set_lp_fee_bps(prize_pool_cap, &mut prize_pool, LP_FEE_BPS);
    prize_pool::set_protocol_fee_bps(prize_pool_cap, &mut prize_pool, PROTOCOL_FEE_BPS);

    pool::set_deposit_enabled<TEST_COIN>(pool_cap, &mut pool_registry, RISK_RATIO_BPS, true);

    ts::return_shared(phase_info);
    ts::return_shared(pool_registry);
    ts::return_shared(prize_pool);
}

// Test errors.move
#[test]
fun test_error_codes() {
    assert_eq(errors::e_uninitialized(), 1);
    assert_eq(errors::e_unauthorized(), 1001);
    assert_eq(errors::e_invalid_fees(), 2001);
    assert_eq(errors::e_zero_ticket_count(), 3001);
    assert_eq(errors::e_too_small_to_mint(), 4001);
    assert_eq(errors::e_purchase_amount_too_low(), 5001);
}

// Test ticket_calculator.move
#[test]
fun test_calculate_total_ticket_with_fees() {
    let ticket_amount = 100;
    let total_fees_bps = 3000; // 30%
    let result = ticket_calculator::calculate_total_ticket_with_fees(ticket_amount, total_fees_bps);
    assert_eq(result, 142); // 100 * 10000 / (10000 - 3000) ≈ 142

    let total_fees_bps = 0;
    let result = ticket_calculator::calculate_total_ticket_with_fees(ticket_amount, total_fees_bps);
    assert_eq(result, 100);
}

#[test]
#[expected_failure(abort_code = anglerfish::ticket_calculator::ErrorInvalidFees)]
fun test_calculate_total_ticket_with_fees_invalid() {
    ticket_calculator::calculate_total_ticket_with_fees(100, 10000);
}

// Test lounge.move
#[test]
fun test_lounge_create_and_claim() {
    let mut scenario = ts::begin(ADMIN);
    let (prize_pool_cap, phase_info_cap, pool_cap, lounge_cap, round_registry_cap) = setup(
        &mut scenario,
    );

    ts::next_tx(&mut scenario, ADMIN);
    let mut lounge_registry = ts::take_shared<LoungeRegistry>(&scenario);
    let lounge_number = lounge::create_lounge<TEST_COIN>(
        &lounge_cap,
        &mut lounge_registry,
        1,
        USER1,
        ts::ctx(&mut scenario),
    );
    assert_eq(lounge_number, 1);
    assert!(lounge::is_lounge_available(&lounge_registry, 1), 0);

    let coin = coin::mint_for_testing<TEST_COIN>(1000, ts::ctx(&mut scenario));
    lounge::add_reserves(&mut lounge_registry, lounge_number, coin);

    ts::next_tx(&mut scenario, USER1);
    let claimed_coin = lounge::claim<TEST_COIN>(
        &mut lounge_registry,
        lounge_number,
        ts::ctx(&mut scenario),
    );
    assert_eq(claimed_coin.value(), 1000);

    ts::next_tx(&mut scenario, ADMIN);
    ts::return_shared(lounge_registry);
    ts::return_to_sender(&scenario, prize_pool_cap);
    ts::return_to_sender(&scenario, phase_info_cap);
    ts::return_to_sender(&scenario, pool_cap);
    ts::return_to_sender(&scenario, lounge_cap);
    ts::return_to_sender(&scenario, round_registry_cap);
    coin::burn_for_testing(claimed_coin);
    ts::end(scenario);
}

#[test]
#[expected_failure(abort_code = anglerfish::lounge::ErrorUnauthorized)]
fun test_lounge_claim_unauthorized() {
    let mut scenario = ts::begin(ADMIN);
    let (prize_pool_cap, phase_info_cap, pool_cap, lounge_cap, round_registry_cap) = setup(
        &mut scenario,
    );

    ts::next_tx(&mut scenario, ADMIN);
    let mut lounge_registry = ts::take_shared<LoungeRegistry>(&scenario);
    lounge::create_lounge<TEST_COIN>(
        &lounge_cap,
        &mut lounge_registry,
        1,
        USER1,
        ts::ctx(&mut scenario),
    );
    let coin = coin::mint_for_testing<TEST_COIN>(1000, ts::ctx(&mut scenario));
    lounge::add_reserves(&mut lounge_registry, 1, coin);

    ts::next_tx(&mut scenario, USER2);
    let claim_coin = lounge::claim<TEST_COIN>(&mut lounge_registry, 1, ts::ctx(&mut scenario));
    assert_eq(claim_coin.value(), 1000);

    ts::return_shared(lounge_registry);
    ts::return_to_sender(&scenario, claim_coin);
    ts::return_to_sender(&scenario, prize_pool_cap);
    ts::return_to_sender(&scenario, phase_info_cap);
    ts::return_to_sender(&scenario, pool_cap);
    ts::return_to_sender(&scenario, lounge_cap);
    ts::return_to_sender(&scenario, round_registry_cap);
    ts::end(scenario);
}

// Test phase.move
#[test]
fun test_phase_transitions() {
    let mut scenario = ts::begin(ADMIN);
    let (prize_pool_cap, phase_info_cap, pool_cap, lounge_cap, round_registry_cap) = setup(
        &mut scenario,
    );

    ts::next_tx(&mut scenario, ADMIN);
    let mut phase_info = ts::take_shared<PhaseInfo>(&scenario);
    let mut round_registry = ts::take_shared<RoundRegistry>(&scenario);
    phase::initialize(
        &phase_info_cap,
        &mut phase_info,
        LIQUIDITY_DURATION,
        TICKETING_DURATION,
        ts::ctx(&mut scenario),
    );
    phase_info.assert_settling_phase();

    let mut clock = clock::create_for_testing(ts::ctx(&mut scenario));
    prize_pool::start_new_round(
        &prize_pool_cap,
        &round_registry_cap,
        &phase_info_cap,
        &mut phase_info,
        &mut round_registry,
        &clock,
        ts::ctx(&mut scenario),
    );
    phase_info.assert_liquidity_providing_phase();
    assert_eq(phase::get_current_round_number(&phase_info), 1);

    clock::increment_for_testing(&mut clock, LIQUIDITY_DURATION);
    phase::next_entry(&phase_info_cap, &mut phase_info, &clock, ts::ctx(&mut scenario));
    phase_info.assert_ticketing_phase();

    clock::increment_for_testing(&mut clock, TICKETING_DURATION);
    phase::next_entry(&phase_info_cap, &mut phase_info, &clock, ts::ctx(&mut scenario));
    phase_info.assert_drawing_phase();

    clock::destroy_for_testing(clock);
    ts::return_shared(phase_info);
    ts::return_shared(round_registry);
    ts::return_to_sender(&scenario, prize_pool_cap);
    ts::return_to_sender(&scenario, phase_info_cap);
    ts::return_to_sender(&scenario, pool_cap);
    ts::return_to_sender(&scenario, lounge_cap);
    ts::return_to_sender(&scenario, round_registry_cap);
    ts::end(scenario);
}

#[test]
#[expected_failure(abort_code = anglerfish::phase::ErrorAlreadyInitialized)]
fun test_phase_initialize_twice() {
    let mut scenario = ts::begin(ADMIN);
    let (prize_pool_cap, phase_info_cap, pool_cap, lounge_cap, round_registry_cap) = setup(
        &mut scenario,
    );

    ts::next_tx(&mut scenario, ADMIN);
    let mut phase_info = ts::take_shared<PhaseInfo>(&scenario);
    phase::initialize(
        &phase_info_cap,
        &mut phase_info,
        LIQUIDITY_DURATION,
        TICKETING_DURATION,
        ts::ctx(&mut scenario),
    );
    phase::initialize(
        &phase_info_cap,
        &mut phase_info,
        LIQUIDITY_DURATION,
        TICKETING_DURATION,
        ts::ctx(&mut scenario),
    );

    ts::return_shared(phase_info);
    ts::return_to_sender(&scenario, prize_pool_cap);
    ts::return_to_sender(&scenario, phase_info_cap);
    ts::return_to_sender(&scenario, pool_cap);
    ts::return_to_sender(&scenario, lounge_cap);
    ts::return_to_sender(&scenario, round_registry_cap);
    ts::end(scenario);
}

// Test round.move
#[test]
fun test_round_add_player_and_find_winner() {
    let mut scenario = ts::begin(ADMIN);
    let (prize_pool_cap, phase_info_cap, pool_cap, lounge_cap, round_registry_cap) = setup(
        &mut scenario,
    );

    ts::next_tx(&mut scenario, ADMIN);
    let mut round_registry = ts::take_shared<RoundRegistry>(&scenario);
    let round_id = round::create_round(
        &round_registry_cap,
        &mut round_registry,
        1,
        ts::ctx(&mut scenario),
    );

    ts::next_tx(&mut scenario, ADMIN);
    let mut round = ts::take_shared_by_id<Round>(&scenario, round_id);

    round::add_player_ticket(&mut round, USER1, 10);
    round::add_player_ticket(&mut round, USER2, 20);
    assert_eq(round::total_tickets(&round), 30);
    assert_eq(round::get_player_tickets(&round, USER1), 10);
    assert_eq(round::get_player_tickets(&round, USER2), 20);

    let clock = clock::create_for_testing(ts::ctx(&mut scenario));
    let winner = round::find_ticket_winner_address(&round, 15);
    assert!(winner.is_some() && *option::borrow(&winner) == USER2, 0);

    round::record_drawing_result(&mut round, &clock, winner, 1000);

    assert_eq(round::get_prize_amount(&round), 1000);
    assert_eq(round::get_winner(&round).extract(), USER2);

    clock::destroy_for_testing(clock);
    ts::return_shared(round_registry);
    ts::return_shared(round);
    ts::return_to_sender(&scenario, prize_pool_cap);
    ts::return_to_sender(&scenario, phase_info_cap);
    ts::return_to_sender(&scenario, pool_cap);
    ts::return_to_sender(&scenario, lounge_cap);
    ts::return_to_sender(&scenario, round_registry_cap);
    ts::end(scenario);
}

#[test]
#[expected_failure(abort_code = anglerfish::round::ErrorZeroTicketCount)]
fun test_round_add_zero_tickets() {
    let mut scenario = ts::begin(ADMIN);
    let (prize_pool_cap, phase_info_cap, pool_cap, lounge_cap, round_registry_cap) = setup(
        &mut scenario,
    );

    ts::next_tx(&mut scenario, ADMIN);
    let mut round_registry = ts::take_shared<RoundRegistry>(&scenario);
    let round_id = round::create_round(
        &round_registry_cap,
        &mut round_registry,
        1,
        ts::ctx(&mut scenario),
    );

    ts::next_tx(&mut scenario, ADMIN);
    let mut round = ts::take_shared_by_id<Round>(&scenario, round_id);

    round::add_player_ticket(&mut round, USER1, 0);

    ts::return_shared(round_registry);
    ts::return_shared(round);
    ts::return_to_sender(&scenario, prize_pool_cap);
    ts::return_to_sender(&scenario, phase_info_cap);
    ts::return_to_sender(&scenario, pool_cap);
    ts::return_to_sender(&scenario, lounge_cap);
    ts::return_to_sender(&scenario, round_registry_cap);
    ts::end(scenario);
}

// Test pool.move
#[test]
fun test_pool_deposit_and_redeem() {
    let mut scenario = ts::begin(ADMIN);
    let (prize_pool_cap, phase_info_cap, pool_cap, lounge_cap, round_registry_cap) = setup(
        &mut scenario,
    );
    initialize_phase_and_pool(&mut scenario, &phase_info_cap, &pool_cap, &prize_pool_cap);

    ts::next_tx(&mut scenario, ADMIN);
    {
        let mut phase_info = ts::take_shared<PhaseInfo>(&scenario);
        let mut round_registry = ts::take_shared<RoundRegistry>(&scenario);
        let clock = clock::create_for_testing(ts::ctx(&mut scenario));
        prize_pool::start_new_round(
            &prize_pool_cap,
            &round_registry_cap,
            &phase_info_cap,
            &mut phase_info,
            &mut round_registry,
            &clock,
            ts::ctx(&mut scenario),
        );
        ts::return_shared(phase_info);
        ts::return_shared(round_registry);
        clock::destroy_for_testing(clock);
    };

    ts::next_tx(&mut scenario, USER1);
    let mut pool_registry = ts::take_shared<PoolRegistry>(&scenario);
    let phase_info = ts::take_shared<PhaseInfo>(&scenario);
    let coin = coin::mint_for_testing<TEST_COIN>(1000, ts::ctx(&mut scenario));
    pool::deposit<TEST_COIN>(
        &mut pool_registry,
        &phase_info,
        RISK_RATIO_BPS,
        coin,
        ts::ctx(&mut scenario),
    );

    let (pool_total_shares, user_shares, reserves) = {
        let pool = pool::get_pool_by_risk_ratio<TEST_COIN>(&pool_registry, RISK_RATIO_BPS);
        (
            pool::get_total_shares(pool),
            pool::get_user_shares(pool, USER1),
            pool::get_reserves(pool).value(),
        )
    };
    assert_eq(pool_total_shares, 1000);
    assert_eq(user_shares, 1000);
    assert_eq(reserves, 1000);

    let redeemed_coin = pool::redeem<TEST_COIN>(
        &mut pool_registry,
        &phase_info,
        RISK_RATIO_BPS,
        500,
        ts::ctx(&mut scenario),
    );
    assert_eq(redeemed_coin.value(), 500);
    let (pool_total_shares, user_shares, reserves) = {
        let pool = pool::get_pool_by_risk_ratio<TEST_COIN>(&pool_registry, RISK_RATIO_BPS);
        (
            pool::get_total_shares(pool),
            pool::get_user_shares(pool, USER1),
            pool::get_reserves(pool).value(),
        )
    };
    assert_eq(pool_total_shares, 500);
    assert_eq(user_shares, 500);
    assert_eq(reserves, 500);

    ts::next_tx(&mut scenario, ADMIN);
    ts::return_shared(pool_registry);
    ts::return_shared(phase_info);
    ts::return_to_sender(&scenario, prize_pool_cap);
    ts::return_to_sender(&scenario, phase_info_cap);
    ts::return_to_sender(&scenario, pool_cap);
    ts::return_to_sender(&scenario, lounge_cap);
    ts::return_to_sender(&scenario, round_registry_cap);
    coin::burn_for_testing(redeemed_coin);
    ts::end(scenario);
}

#[test]
#[expected_failure(abort_code = anglerfish::pool::ErrorTooLargeToRedeem)]
fun test_pool_redeem_too_large() {
    let mut scenario = ts::begin(ADMIN);
    let (prize_pool_cap, phase_info_cap, pool_cap, lounge_cap, round_registry_cap) = setup(
        &mut scenario,
    );
    initialize_phase_and_pool(&mut scenario, &phase_info_cap, &pool_cap, &prize_pool_cap);

    ts::next_tx(&mut scenario, ADMIN);
    {
        let mut phase_info = ts::take_shared<PhaseInfo>(&scenario);
        let mut round_registry = ts::take_shared<RoundRegistry>(&scenario);
        let clock = clock::create_for_testing(ts::ctx(&mut scenario));
        prize_pool::start_new_round(
            &prize_pool_cap,
            &round_registry_cap,
            &phase_info_cap,
            &mut phase_info,
            &mut round_registry,
            &clock,
            ts::ctx(&mut scenario),
        );
        ts::return_shared(phase_info);
        ts::return_shared(round_registry);
        clock::destroy_for_testing(clock);
    };

    ts::next_tx(&mut scenario, USER1);
    let mut pool_registry = ts::take_shared<PoolRegistry>(&scenario);
    let phase_info = ts::take_shared<PhaseInfo>(&scenario);
    let coin = coin::mint_for_testing<TEST_COIN>(1000, ts::ctx(&mut scenario));
    pool::deposit<TEST_COIN>(
        &mut pool_registry,
        &phase_info,
        RISK_RATIO_BPS,
        coin,
        ts::ctx(&mut scenario),
    );

    let redeemed_coin = pool::redeem<TEST_COIN>(
        &mut pool_registry,
        &phase_info,
        RISK_RATIO_BPS,
        2000,
        ts::ctx(&mut scenario),
    );
    assert_eq(redeemed_coin.value(), 1000);

    ts::return_shared(pool_registry);
    ts::return_shared(phase_info);
    ts::return_to_sender(&scenario, prize_pool_cap);
    ts::return_to_sender(&scenario, phase_info_cap);
    ts::return_to_sender(&scenario, pool_cap);
    ts::return_to_sender(&scenario, lounge_cap);
    ts::return_to_sender(&scenario, round_registry_cap);
    ts::return_to_sender(&scenario, redeemed_coin);
    ts::end(scenario);
}

// Test prize_pool.move
#[test]
fun test_purchase_ticket() {
    let mut scenario = ts::begin(ADMIN);
    let (prize_pool_cap, phase_info_cap, pool_cap, lounge_cap, round_registry_cap) = setup(
        &mut scenario,
    );
    initialize_phase_and_pool(&mut scenario, &phase_info_cap, &pool_cap, &prize_pool_cap);

    ts::next_tx(&mut scenario, ADMIN);
    let mut phase_info = ts::take_shared<PhaseInfo>(&scenario);
    let mut round_registry = ts::take_shared<RoundRegistry>(&scenario);
    let mut clock = clock::create_for_testing(ts::ctx(&mut scenario));
    prize_pool::start_new_round(
        &prize_pool_cap,
        &round_registry_cap,
        &phase_info_cap,
        &mut phase_info,
        &mut round_registry,
        &clock,
        ts::ctx(&mut scenario),
    );

    clock::increment_for_testing(&mut clock, LIQUIDITY_DURATION);
    phase::next_entry(&phase_info_cap, &mut phase_info, &clock, ts::ctx(&mut scenario));

    ts::next_tx(&mut scenario, USER1);
    let mut prize_pool = ts::take_shared<PrizePool>(&scenario);
    let round_id = round::get_round_id(&round_registry, 1).extract();
    let mut round = ts::take_shared_by_id<Round>(&scenario, round_id);
    let coin = coin::mint_for_testing<TEST_COIN>(3000, ts::ctx(&mut scenario));
    let remaining_coin = prize_pool::purchase_ticket<TEST_COIN>(
        &mut prize_pool,
        &round_registry,
        &mut round,
        &phase_info,
        coin,
        ts::ctx(&mut scenario),
    );
    assert_eq(remaining_coin.value(), 0); // 3 tickets * 1000 = 3000
    assert_eq(round::get_player_tickets(&round, USER1), 3);
    assert_eq(prize_pool::get_treasury_reserves_value<TEST_COIN>(&prize_pool), 2100); // 3000 * (10000 - 2500 - 500) / 10000
    assert_eq(prize_pool::get_lp_fee_reserves_value<TEST_COIN>(&prize_pool), 750); // 3000 * 2500 / 10000
    assert_eq(prize_pool::get_protocol_fee_reserves_value<TEST_COIN>(&prize_pool), 150); // 3000 * 500 / 10000

    ts::next_tx(&mut scenario, ADMIN);
    clock::destroy_for_testing(clock);
    ts::return_shared(prize_pool);
    ts::return_shared(round);
    ts::return_shared(phase_info);
    ts::return_shared(round_registry);
    ts::return_to_sender(&scenario, prize_pool_cap);
    ts::return_to_sender(&scenario, phase_info_cap);
    ts::return_to_sender(&scenario, pool_cap);
    ts::return_to_sender(&scenario, lounge_cap);
    ts::return_to_sender(&scenario, round_registry_cap);
    coin::burn_for_testing(remaining_coin);
    ts::end(scenario);
}

#[test]
#[expected_failure(abort_code = anglerfish::prize_pool::ErrorPurchaseAmountTooLow)]
fun test_purchase_ticket_zero() {
    let mut scenario = ts::begin(ADMIN);
    let (prize_pool_cap, phase_info_cap, pool_cap, lounge_cap, round_registry_cap) = setup(
        &mut scenario,
    );
    initialize_phase_and_pool(&mut scenario, &phase_info_cap, &pool_cap, &prize_pool_cap);

    ts::next_tx(&mut scenario, ADMIN);
    let mut phase_info = ts::take_shared<PhaseInfo>(&scenario);
    let mut round_registry = ts::take_shared<RoundRegistry>(&scenario);
    let mut clock = clock::create_for_testing(ts::ctx(&mut scenario));
    prize_pool::start_new_round(
        &prize_pool_cap,
        &round_registry_cap,
        &phase_info_cap,
        &mut phase_info,
        &mut round_registry,
        &clock,
        ts::ctx(&mut scenario),
    );

    clock::increment_for_testing(&mut clock, LIQUIDITY_DURATION);
    phase::next_entry(&phase_info_cap, &mut phase_info, &clock, ts::ctx(&mut scenario));

    ts::next_tx(&mut scenario, USER1);
    let mut prize_pool = ts::take_shared<PrizePool>(&scenario);
    let round_id = round::get_round_id(&round_registry, 1).extract();
    let mut round = ts::take_shared_by_id<Round>(&scenario, round_id);
    let coin = coin::mint_for_testing<TEST_COIN>(0, ts::ctx(&mut scenario));
    let change_coin = prize_pool::purchase_ticket<TEST_COIN>(
        &mut prize_pool,
        &round_registry,
        &mut round,
        &phase_info,
        coin,
        ts::ctx(&mut scenario),
    );

    clock::destroy_for_testing(clock);
    ts::return_shared(prize_pool);
    ts::return_shared(round);
    ts::return_shared(phase_info);
    ts::return_shared(round_registry);
    ts::return_to_sender(&scenario, prize_pool_cap);
    ts::return_to_sender(&scenario, phase_info_cap);
    ts::return_to_sender(&scenario, pool_cap);
    ts::return_to_sender(&scenario, lounge_cap);
    ts::return_to_sender(&scenario, round_registry_cap);
    ts::return_to_sender(&scenario, change_coin);
    ts::end(scenario);
}

// Integration test: Full lottery cycle
#[test]
fun test_full_lottery_cycle() {
    let mut scenario = ts::begin(ADMIN);
    let (prize_pool_cap, phase_info_cap, pool_cap, lounge_cap, round_registry_cap) = setup(
        &mut scenario,
    );
    initialize_phase_and_pool(&mut scenario, &phase_info_cap, &pool_cap, &prize_pool_cap);

    ts::next_tx(&mut scenario, ADMIN);
    {
        let mut phase_info = ts::take_shared<PhaseInfo>(&scenario);
        let mut round_registry = ts::take_shared<RoundRegistry>(&scenario);
        let clock = clock::create_for_testing(ts::ctx(&mut scenario));

        prize_pool_cap.start_new_round(
            &round_registry_cap,
            &phase_info_cap,
            &mut phase_info,
            &mut round_registry,
            &clock,
            ts::ctx(&mut scenario),
        );

        ts::return_shared(phase_info);
        ts::return_shared(round_registry);
        clock::destroy_for_testing(clock);
    };

    // Deposit to pool
    ts::next_tx(&mut scenario, USER1);
    let mut pool_registry = ts::take_shared<PoolRegistry>(&scenario);
    let mut phase_info = ts::take_shared<PhaseInfo>(&scenario);
    let deposit_coin = coin::mint_for_testing<TEST_COIN>(10000, ts::ctx(&mut scenario));
    pool::deposit<TEST_COIN>(
        &mut pool_registry,
        &phase_info,
        RISK_RATIO_BPS,
        deposit_coin,
        ts::ctx(&mut scenario),
    );

    // Start move to next phase
    ts::next_tx(&mut scenario, USER1);
    let round_registry = ts::take_shared<RoundRegistry>(&scenario);
    let mut prize_pool = ts::take_shared<PrizePool>(&scenario);
    let mut clock = clock::create_for_testing(ts::ctx(&mut scenario));
    clock::increment_for_testing(&mut clock, LIQUIDITY_DURATION);
    phase::next_entry(&phase_info_cap, &mut phase_info, &clock, ts::ctx(&mut scenario));

    // Purchase tickets
    ts::next_tx(&mut scenario, USER1);
    let round_id = round::get_round_id(&round_registry, 1).extract();
    let mut round = ts::take_shared_by_id<Round>(&scenario, round_id);
    let purchase_coin = coin::mint_for_testing<TEST_COIN>(3000, ts::ctx(&mut scenario));
    let change_coin = prize_pool::purchase_ticket<TEST_COIN>(
        &mut prize_pool,
        &round_registry,
        &mut round,
        &phase_info,
        purchase_coin,
        ts::ctx(&mut scenario),
    );
    assert_eq(change_coin.value(), 0);
    coin::burn_for_testing(change_coin);

    // Draw winner
    clock::increment_for_testing(&mut clock, TICKETING_DURATION);
    phase::next_entry(&phase_info_cap, &mut phase_info, &clock, ts::ctx(&mut scenario));
    ts::next_tx(&mut scenario, ADMIN);

    let rand = scenario.take_shared<Random>();
    prize_pool::draw<TEST_COIN>(
        &prize_pool_cap,
        &phase_info_cap,
        &prize_pool,
        &mut phase_info,
        &pool_registry,
        &round_registry,
        &mut round,
        &rand,
        &clock,
        ts::ctx(&mut scenario),
    );
    assert_eq(
        round::get_prize_amount(&round),
        pool_registry.get_total_prize_reserves_value<TEST_COIN>(),
    );

    // Distribute prizes and fees
    ts::next_tx(&mut scenario, ADMIN);
    let total_reserves = pool_registry.get_total_prize_reserves_value<TEST_COIN>();
    let mut lounge_registry = ts::take_shared<LoungeRegistry>(&scenario);
    prize_pool::distribute<TEST_COIN>(
        &prize_pool_cap,
        &pool_cap,
        &lounge_cap,
        &phase_info_cap,
        &mut phase_info,
        &mut prize_pool,
        &mut pool_registry,
        &mut lounge_registry,
        &round_registry,
        &mut round,
        &clock,
        ts::ctx(&mut scenario),
    );

    // Claim prize
    ts::next_tx(&mut scenario, USER1);
    let claimed_coin = lounge::claim<TEST_COIN>(&mut lounge_registry, 1, ts::ctx(&mut scenario));
    assert_eq(claimed_coin.value(), total_reserves);

    // Claim protocol fee
    ts::next_tx(&mut scenario, ADMIN);
    let protocol_fee = prize_pool::claim_protocol_fee<TEST_COIN>(
        &prize_pool_cap,
        &mut prize_pool,
        ts::ctx(&mut scenario),
    );
    assert_eq(protocol_fee.value(), 150); // 3000 * 500 / 10000

    clock::destroy_for_testing(clock);
    ts::return_shared(rand);
    ts::return_shared(prize_pool);
    ts::return_shared(phase_info);
    ts::return_shared(pool_registry);
    ts::return_shared(round_registry);
    ts::return_shared(round);
    ts::return_shared(lounge_registry);
    ts::return_to_sender(&scenario, prize_pool_cap);
    ts::return_to_sender(&scenario, phase_info_cap);
    ts::return_to_sender(&scenario, pool_cap);
    ts::return_to_sender(&scenario, lounge_cap);
    ts::return_to_sender(&scenario, round_registry_cap);
    coin::burn_for_testing(claimed_coin);
    coin::burn_for_testing(protocol_fee);
    ts::end(scenario);
}
