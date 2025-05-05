/// Manages lottery ticket purchases, prize draws, and distributions.
module anglerfish::prize_pool;

use anglerfish::lounge::{LoungeCap, LoungeRegistry};
use anglerfish::phase::{PhaseInfo, PhaseInfoCap};
use anglerfish::pool::{PoolRegistry, PoolCap};
use anglerfish::round::{Round, RoundRegistry, RoundRegistryCap};
use anglerfish::ticket_calculator::calculate_total_ticket_with_fees;
use sui::bag::{Self, Bag};
use sui::balance::{Self, Balance};
use sui::clock::Clock;
use sui::coin::{Self, Coin, from_balance};
use sui::event::emit;
use sui::random::{Random, new_generator};

// Error codes
const ErrorNotOneTimeWitness: u64 = 5001;
const ErrorPurchaseAmountTooLow: u64 = 5002;
const ErrorLpFeeAmountTooHigh: u64 = 5003;
const ErrorProtocolFeeAmountTooHigh: u64 = 5004;
const ErrorExcessiveFeeCharged: u64 = 5005;
const ErrorInvalidRoundNumberSequence: u64 = 5006;

const TREASURY_RESERVES_KEY: vector<u8> = b"treasury_reserves";
const LP_FEE_RESERVES_KEY: vector<u8> = b"lp_fee_reserves";
const PROTOCOL_FEE_RESERVES_KEY: vector<u8> = b"protocol_fee_reserves";

/// PRIZE_POOL a OneTimeWitness struct
public struct PRIZE_POOL has drop {}

/// Capability for authorized PrizePool operations.
public struct PrizePoolCap has key, store {
    id: UID,
}

public struct PrizePoolCapCreated has copy, drop {
    cap_id: ID,
}

/// Shared object storing lottery configuration and state.
public struct PrizePool has key {
    /// Object Id
    id: UID,
    /// The ticket price based on unit of the pool
    price_per_ticket: u64,
    /// The prize provider fees in basis points
    lp_fee_bps: u64,
    /// The protocol fee in basis points
    protocol_fee_bps: u64,
    /// The reserves bag that hold the purchased tickets, fees, and protocol fees
    reserves: Bag,
}

/// Initializes PrizePool and PrizePoolCap with OneTimeWitness.
fun init(witness: PRIZE_POOL, ctx: &mut TxContext) {
    assert!(sui::types::is_one_time_witness(&witness), ErrorNotOneTimeWitness);

    let authority = ctx.sender();

    let authority_cap = PrizePoolCap {
        id: object::new(ctx),
    };

    let prize_pool = PrizePool {
        id: object::new(ctx),
        price_per_ticket: 0,
        lp_fee_bps: 2500,
        protocol_fee_bps: 500,
        reserves: bag::new(ctx),
    };

    emit(PrizePoolCapCreated { cap_id: object::id(&authority_cap) });

    transfer::share_object(prize_pool);
    transfer::transfer(authority_cap, authority);
}

/// Sets the price per ticket.
public fun set_price_per_ticket(
    _self: &PrizePoolCap,
    prize_pool: &mut PrizePool,
    phase_info: &PhaseInfo,
    price_per_ticket: u64,
) {
    phase_info.assert_settling_phase();
    prize_pool.price_per_ticket = price_per_ticket;
}

/// Sets the liquidity provider fee in basis points.
public fun set_lp_fee_bps(
    _self: &PrizePoolCap,
    prize_pool: &mut PrizePool,
    phase_info: &PhaseInfo,
    lp_fee_bps: u64,
) {
    phase_info.assert_settling_phase();
    assert!(lp_fee_bps < 6000, ErrorLpFeeAmountTooHigh);
    prize_pool.lp_fee_bps = lp_fee_bps;
}

/// Sets the protocol fee in basis points.
public fun set_protocol_fee_bps(
    _self: &PrizePoolCap,
    prize_pool: &mut PrizePool,
    phase_info: &PhaseInfo,
    protocol_fee_bps: u64,
) {
    phase_info.assert_settling_phase();
    assert!(protocol_fee_bps < 3000, ErrorProtocolFeeAmountTooHigh);
    prize_pool.protocol_fee_bps = protocol_fee_bps;
}

/// Starts a new round in Settling phase, advancing to LiquidityProviding.
public fun start_new_round(
    _self: &PrizePoolCap,
    round_registry_cap: &RoundRegistryCap,
    phase_info_cap: &PhaseInfoCap,
    phase_info: &mut PhaseInfo,
    round_registry: &mut RoundRegistry,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    // Must be in Settling phase
    phase_info.assert_settling_phase();

    let prev_round_number = phase_info.get_current_round_number();

    // forward to next phase
    phase_info_cap.next(phase_info, clock, ctx);

    let current_round_number = phase_info.get_current_round_number();

    // Capability for authorized PrizePool operations.
    assert!(current_round_number == prev_round_number + 1, ErrorInvalidRoundNumberSequence);

    // Create a new round in RoundRegistry
    round_registry_cap.create_round(round_registry, current_round_number, ctx);
}

/// Claims all protocol fee reserves.
public fun claim_protocol_fee<T>(
    _self: &PrizePoolCap,
    prize_pool: &mut PrizePool,
    ctx: &mut TxContext,
): Coin<T> {
    let protocol_fee_reserves = prize_pool.inner_get_protocol_fee_reserves_balance_mut<T>();
    let fee_coin = from_balance(protocol_fee_reserves.withdraw_all(), ctx);
    fee_coin
}

/// Claims all treasury reserves.
public fun claim_treasury_reserve<T>(
    _self: &PrizePoolCap,
    prize_pool: &mut PrizePool,
    ctx: &mut TxContext,
): Coin<T> {
    let reserves = prize_pool.inner_get_treasury_reserves_balance_mut<T>();
    let fee_coin = from_balance(reserves.withdraw_all(), ctx);
    fee_coin
}

public fun get_price_per_ticket(self: &PrizePool): u64 {
    self.price_per_ticket
}

public fun get_lp_fee_bps(self: &PrizePool): u64 {
    self.lp_fee_bps
}

public fun get_protocol_fee_bps(self: &PrizePool): u64 {
    self.protocol_fee_bps
}

/// Public views & functions

/// Gets the total prize reserves value from the pool registry.
public fun get_total_prize_reserves_value<T>(_self: &PrizePool, pool_registry: &PoolRegistry): u64 {
    pool_registry.get_total_prize_reserves_value<T>()
}

/// Gets the value of treasury reserves.
public fun get_treasury_reserves_value<T>(self: &PrizePool): u64 {
    self.inner_get_treasury_reserves_balance_value<T>()
}

/// Gets the value of liquidity provider fee reserves.
public fun get_lp_fee_reserves_value<T>(self: &PrizePool): u64 {
    self.inner_get_lp_fee_reserves_balance_value<T>()
}

/// Gets the value of protocol fee reserves.
public fun get_protocol_fee_reserves_value<T>(self: &PrizePool): u64 {
    self.inner_get_protocol_fee_reserves_balance_value<T>()
}

/// Purchases tickets, allocating fees and adding tickets to the round.
public fun purchase_ticket<T>(
    self: &mut PrizePool,
    round_registry: &RoundRegistry,
    round: &mut Round,
    phase_info: &PhaseInfo,
    purchase_coin: Coin<T>,
    ctx: &mut TxContext,
): Coin<T> {
    phase_info.assert_ticketing_phase();
    phase_info.assert_current_round_number(round.get_round_number());
    round_registry.assert_round(round);

    let purchase_value = purchase_coin.value();
    assert!(purchase_value > 0, ErrorPurchaseAmountTooLow);

    let ticket_amount = purchase_value / self.price_per_ticket;
    assert!(ticket_amount > 0, ErrorPurchaseAmountTooLow);

    // Calculate exact ticket cost
    let ticket_cost = ticket_amount * self.price_per_ticket;

    let mut purchase_coin = purchase_coin;

    // Transfer fee coin to lp fee reserves
    let lp_fee_amount = self.inner_get_lp_fee_amount(ticket_cost);
    let lp_fee_reserves = self.inner_get_lp_fee_reserves_balance_mut<T>();
    coin::put(lp_fee_reserves, purchase_coin.split(lp_fee_amount, ctx));

    // Transfer protocol fee coin to protocol fee reserves
    let protocol_fee_amount = self.inner_get_protocol_fee_amount(ticket_cost);
    let protocol_fee_reserves = self.inner_get_protocol_fee_reserves_balance_mut<T>();
    coin::put(protocol_fee_reserves, purchase_coin.split(protocol_fee_amount, ctx));

    // Transfer ticket coin to treasury reserves
    assert!(ticket_cost > lp_fee_amount + protocol_fee_amount, ErrorExcessiveFeeCharged);
    let ticket_cost_after_fees = ticket_cost - lp_fee_amount - protocol_fee_amount;
    let treasury_reserves = self.inner_get_treasury_reserves_balance_mut<T>();
    coin::put(treasury_reserves, purchase_coin.split(ticket_cost_after_fees, ctx));

    // Record player tickets
    let buyer = tx_context::sender(ctx);
    round.add_player_ticket(buyer, ticket_amount);

    purchase_coin // Refund excess amount
}

/// Draws a winner using a random ticket number.
entry fun draw<T>(
    _self: &PrizePoolCap,
    phase_info_cap: &PhaseInfoCap,
    prize_pool: &PrizePool,
    phase_info: &mut PhaseInfo,
    pool_registry: &PoolRegistry,
    round_registry: &RoundRegistry,
    round: &mut Round,
    rand: &Random,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    phase_info.assert_drawing_phase();
    phase_info.assert_current_round_number(round.get_round_number());
    round_registry.assert_round(round);

    let prize_reserves_value = prize_pool.get_total_prize_reserves_value<T>(pool_registry);
    let lp_ticket = prize_pool.inner_cal_lp_ticket(prize_reserves_value);

    let mut generator = rand.new_generator(ctx);
    let ticket_number = generator.generate_u64_in_range(0, lp_ticket+1); // make sure to cover all tickets
    let winner_player = round.find_ticket_winner_address(ticket_number);

    // Store the winner in the current round
    round.record_drawing_result(clock, winner_player, prize_reserves_value);
    phase_info_cap.set_last_drawing_timestamp_ms(phase_info, clock);

    // Instantly move to the Distributing phase
    phase_info_cap.next(phase_info, clock, ctx);
}

/// Distributes prizes to a lounge and fees to pools.
public fun distribute<T>(
    _self: &PrizePoolCap,
    pool_cap: &PoolCap,
    lounge_cap: &LoungeCap,
    phase_info_cap: &PhaseInfoCap,
    phase_info: &mut PhaseInfo,
    prize_pool: &mut PrizePool,
    pool_registry: &mut PoolRegistry,
    lounge_registry: &mut LoungeRegistry,
    round_registry: &RoundRegistry,
    round: &mut Round,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    phase_info.assert_distributing_phase();
    phase_info.assert_current_round_number(round.get_round_number());
    round_registry.assert_round(round);

    if (round.get_winner().is_some()) {
        let winner = round.get_winner().extract();
        let prize_coin = prize_pool.inner_aggregate_prize_to_lounge<T>(
            phase_info,
            pool_cap,
            pool_registry,
            ctx,
        );

        lounge_cap.create_lounge<T>(
            lounge_registry,
            round.get_round_number(),
            winner,
            prize_coin,
            ctx,
        );
    };

    let fee_reserves = prize_pool.inner_get_lp_fee_reserves_balance_mut<T>();
    inner_distribute_fee_to_pools<T>(pool_registry, fee_reserves, ctx);

    // Instantly move to the Settling phase
    phase_info_cap.next(phase_info, clock, ctx);
}

/// Internal functions

fun inner_aggregate_prize_to_lounge<T>(
    _self: &PrizePool,
    phase_info: &PhaseInfo,
    pool_cap: &PoolCap,
    pool_registry: &mut PoolRegistry,
    ctx: &mut TxContext,
): Coin<T> {
    let risk_ratios = pool_registry.get_pool_risk_ratios();
    let risk_ratios_len = risk_ratios.length();

    let mut i = 0;
    let mut total_balance = balance::zero<T>();
    while (i < risk_ratios_len) {
        let risk_ratio_bps = risk_ratios[i];
        let prize_coin = pool_cap.withdraw_prize<T>(
            pool_registry,
            risk_ratio_bps,
            phase_info,
            ctx,
        );

        balance::join(&mut total_balance, prize_coin.into_balance());
        i = i + 1;
    };

    from_balance(total_balance, ctx)
}

fun inner_distribute_fee_to_pools<T>(
    pool_registry: &mut PoolRegistry,
    reserves: &mut Balance<T>,
    ctx: &mut TxContext,
) {
    let reserves_value = reserves.value();

    let total_risk_ratio_bps = pool_registry.get_total_risk_ratio_bps();
    let risk_ratios = pool_registry.get_pool_risk_ratios();
    let risk_ratios_len = risk_ratios.length();

    let mut i = 0;
    while (i < risk_ratios_len) {
        let risk_ratio_bps = risk_ratios[i];
        let fee_for_pool = inner_cal_fee_for_risk_ratio(
            risk_ratio_bps,
            reserves_value,
            total_risk_ratio_bps,
        );
        let fee_coin = from_balance(reserves.split(fee_for_pool), ctx);
        let pool = pool_registry.get_pool_by_risk_ratio_mut<T>(risk_ratio_bps);
        pool.deposit_fee(fee_coin);
        i = i + 1;
    };
}

fun inner_cal_fee_for_risk_ratio(
    risk_ratio_bps: u64,
    total_reserves_value: u64,
    total_risk_ratio_bps: u64,
): u64 {
    let fee_for_pool = risk_ratio_bps * total_reserves_value / total_risk_ratio_bps;
    fee_for_pool
}

fun inner_get_treasury_reserves_balance_value<T>(self: &PrizePool): u64 {
    if (!self.reserves.contains(TREASURY_RESERVES_KEY)) {
        0
    } else {
        self.reserves.borrow<vector<u8>, Balance<T>>(TREASURY_RESERVES_KEY).value()
    }
}

fun inner_get_treasury_reserves_balance_mut<T>(self: &mut PrizePool): &mut Balance<T> {
    if (!self.reserves.contains(TREASURY_RESERVES_KEY)) {
        self.reserves.add(TREASURY_RESERVES_KEY, balance::zero<T>());
    };
    self.reserves.borrow_mut<vector<u8>, Balance<T>>(TREASURY_RESERVES_KEY)
}

fun inner_get_lp_fee_reserves_balance_value<T>(self: &PrizePool): u64 {
    if (!self.reserves.contains(LP_FEE_RESERVES_KEY)) {
        0
    } else {
        self.reserves.borrow<vector<u8>, Balance<T>>(LP_FEE_RESERVES_KEY).value()
    }
}

fun inner_get_lp_fee_reserves_balance_mut<T>(self: &mut PrizePool): &mut Balance<T> {
    if (!self.reserves.contains(LP_FEE_RESERVES_KEY)) {
        self.reserves.add(LP_FEE_RESERVES_KEY, balance::zero<T>());
    };
    self.reserves.borrow_mut<vector<u8>, Balance<T>>(LP_FEE_RESERVES_KEY)
}

fun inner_get_protocol_fee_reserves_balance_value<T>(self: &PrizePool): u64 {
    if (!self.reserves.contains(PROTOCOL_FEE_RESERVES_KEY)) {
        0
    } else {
        self.reserves.borrow<vector<u8>, Balance<T>>(PROTOCOL_FEE_RESERVES_KEY).value()
    }
}

fun inner_get_protocol_fee_reserves_balance_mut<T>(self: &mut PrizePool): &mut Balance<T> {
    if (!self.reserves.contains(PROTOCOL_FEE_RESERVES_KEY)) {
        self.reserves.add(PROTOCOL_FEE_RESERVES_KEY, balance::zero<T>());
    };
    self.reserves.borrow_mut<vector<u8>, Balance<T>>(PROTOCOL_FEE_RESERVES_KEY)
}

fun inner_get_lp_fee_amount(self: &PrizePool, purchased_value: u64): u64 {
    let lp_fee_amount = purchased_value * self.lp_fee_bps / 10000;
    lp_fee_amount
}

fun inner_get_protocol_fee_amount(self: &PrizePool, purchased_value: u64): u64 {
    let protocol_fee_amount = purchased_value * self.protocol_fee_bps / 10000;
    protocol_fee_amount
}

fun inner_cal_lp_ticket(self: &PrizePool, prize_reserves_value: u64): u64 {
    let lp_tickets = prize_reserves_value / self.price_per_ticket;
    let total_fee_bps = self.lp_fee_bps + self.protocol_fee_bps;
    let lp_tickets_with_fee = calculate_total_ticket_with_fees(
        lp_tickets,
        total_fee_bps,
    );

    lp_tickets_with_fee
}

#[test_only]
public fun init_for_testing(ctx: &mut TxContext) {
    let witness = PRIZE_POOL {};
    init(witness, ctx);
}
