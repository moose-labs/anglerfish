module anglerfish::prize_pool;

use anglerfish::lounge::{LoungeCap, LoungeRegistry};
use anglerfish::phase::{PhaseInfo, PhaseInfoCap};
use anglerfish::pool::{PoolRegistry, PoolCap};
use anglerfish::round::{Self, Round};
use anglerfish::ticket_calculator::calculate_total_ticket_with_fees;
use sui::bag::{Self, Bag};
use sui::balance::{Self, Balance};
use sui::clock::Clock;
use sui::coin::{Self, Coin, from_balance};
use sui::random::{Random, new_generator};
use anglerfish::archive_round::ArchiveRound;

// const ErrorMaximumNumberOfPlayersReached: u64 = 1;
const ErrorInvalidPoolRegistry: u64 = 2;
const ErrorInvalidLoungeRegistry: u64 = 3;
const ErrorPurchaseAmountTooLow: u64 = 4;
const ErrorLpFeeAmountTooHigh: u64 = 5;
const ErrorProtocolFeeAmountTooHigh: u64 = 6;
const ErrorExcessiveFeeCharged: u64 = 7;
const ErrorInvalidRound: u64 = 8;

const TREASURY_RESERVES_KEY: vector<u8> = b"treasury_reserves";
const LP_FEE_RESERVES_KEY: vector<u8> = b"lp_fee_reserves";
const PROTOCOL_FEE_RESERVES_KEY: vector<u8> = b"protocol_fee_reserves";

/// Capability for authorized PrizePool operations.
public struct PrizePoolCap has key, store {
    id: UID,
}

/// Shared object storing lottery configuration and state.
public struct PrizePool has key {
    id: UID,
    /// The pool factory that hold pools
    pool_registry: Option<ID>,
    /// The lounge factory that can create lounges
    lounge_registry: Option<ID>,
    /// Object id of the current round
    current_round: Option<ID>,
    /// The maximum number of players that can participate in the prize pool each round
    price_per_ticket: u64,
    /// The prize provider fees in basis points
    lp_fee_bps: u64,
    /// The protocol fee in basis points
    protocol_fee_bps: u64,
    /// The reserves bag that hold the purchased tickets, fees, and protocol fees
    reserves: Bag,
}

fun init(ctx: &mut TxContext) {
    let authority = ctx.sender();

    let authority_cap = PrizePoolCap {
        id: object::new(ctx),
    };

    transfer::share_object(PrizePool {
        id: object::new(ctx),
        pool_registry: option::none(),
        lounge_registry: option::none(),
        current_round: option::none(),
        price_per_ticket: 0,
        lp_fee_bps: 2500,
        protocol_fee_bps: 500,
        reserves: bag::new(ctx),
    });

    transfer::transfer(authority_cap, authority);
}

/// Capability to manage the prize pool

public fun set_pool_registry(
    _self: &PrizePoolCap,
    prize_pool: &mut PrizePool,
    pool_registry_id: ID,
    _ctx: &mut TxContext,
) {
    prize_pool.pool_registry = option::some(pool_registry_id);
}

public fun set_lounge_registry(
    _self: &PrizePoolCap,
    prize_pool: &mut PrizePool,
    lounge_registry_id: ID,
    _ctx: &mut TxContext,
) {
    prize_pool.lounge_registry = option::some(lounge_registry_id);
}

/// Initializes a Round for the current round in LiquidityProviding phase.
public  fun initialize_round(
    _self: &PrizePoolCap,
    prize_pool: &mut PrizePool,
    phase_info: &PhaseInfo,
    archive_round: &ArchiveRound,
    ctx: &mut TxContext,
) {
    phase_info.assert_liquidity_providing_phase();
    assert!(prize_pool.archive_round.is_some(), ErrorInvalidArchiveRound);
    assert!(object::id(archive_round) == *option::borrow(&prize_pool.archive_round), ErrorInvalidArchiveRound);
    let round_number = phase_info.get_current_round();
    if (!archive_round.contains(round_number)) {
        let round = round::new(round_number, ctx);
        let round_id = object::id(&round);
        add_round(&ctx.sender_as_cap<ArchiveRoundCap>(), archive_round, round_number, round_id);
        transfer::share_object(round);
        event::emit(RoundCreated {
            round_id,
            round_number,
            archive_round_id: object::id(archive_round),
        });
    };
    }

public fun set_price_per_ticket(
    _self: &PrizePoolCap,
    prize_pool: &mut PrizePool,
    price_per_ticket: u64,
    _ctx: &mut TxContext,
) {
    prize_pool.price_per_ticket = price_per_ticket;
}

public fun set_lp_fee_bps(
    _self: &PrizePoolCap,
    prize_pool: &mut PrizePool,
    lp_fee_bps: u64,
    _ctx: &mut TxContext,
) {
    assert!(lp_fee_bps < 6000, ErrorLpFeeAmountTooHigh);
    prize_pool.lp_fee_bps = lp_fee_bps;
}

public fun set_protocol_fee_bps(
    _self: &PrizePoolCap,
    prize_pool: &mut PrizePool,
    protocol_fee_bps: u64,
    _ctx: &mut TxContext,
) {
    assert!(protocol_fee_bps < 3000, ErrorProtocolFeeAmountTooHigh);
    prize_pool.protocol_fee_bps = protocol_fee_bps;
}

public fun claim_protocol_fee<T>(
    _self: &PrizePoolCap,
    prize_pool: &mut PrizePool,
    ctx: &mut TxContext,
): Coin<T> {
    let protocol_fee_reserves = prize_pool.inner_get_protocol_fee_reserves_balance_mut<T>();
    let fee_coin = from_balance(protocol_fee_reserves.withdraw_all(), ctx);
    fee_coin
}

public fun claim_treasury_reserve<T>(
    _self: &PrizePoolCap,
    prize_pool: &mut PrizePool,
    ctx: &mut TxContext,
): Coin<T> {
    let reserves = prize_pool.inner_get_treasury_reserves_balance_mut<T>();
    let fee_coin = from_balance(reserves.withdraw_all(), ctx);
    fee_coin
}

public fun get_pool_registry(self: &PrizePool): Option<ID> {
    self.pool_registry
}

public fun get_lounge_registry(self: &PrizePool): Option<ID> {
    self.lounge_registry
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

/// Gets player’s total tickets for a given round number (UI support).
public fun get_player_tickets(
    self: &PrizePool,
    player: address,
    round: &Round,
    _ctx: &mut TxContext,
): u64 {
    self.assert_current_round(round);

    if (round.contains(&player)) {
        round.get_player_tickets( player)
    } else {
        0
    }
}


/// Public views & functions
///

public fun get_total_prize_reserves_value<T>(_self: &PrizePool, pool_registry: &PoolRegistry): u64 {
    pool_registry.get_total_prize_reserves_value<T>()
}

public fun get_treasury_reserves_value<T>(self: &PrizePool): u64 {
    self.inner_get_treasury_reserves_balance_value<T>()
}

public fun get_lp_fee_reserves_value<T>(self: &PrizePool): u64 {
    self.inner_get_lp_fee_reserves_balance_value<T>()
}

public fun get_protocol_fee_reserves_value<T>(self: &PrizePool): u64 {
    self.inner_get_protocol_fee_reserves_balance_value<T>()
}

public fun purchase_ticket<T>(
    self: &mut PrizePool,
    round: &mut Round,
    phase_info: &PhaseInfo,
    purchase_coin: Coin<T>,
    ctx: &mut TxContext,
): Coin<T> {
    phase_info.assert_ticketing_phase();
    self.assert_current_round(round);

    assert!(self.pool_registry.is_some(), ErrorInvalidPoolRegistry);
    assert!(self.lounge_registry.is_some(), ErrorInvalidLoungeRegistry);

    let purchase_value = purchase_coin.value();
    assert!(purchase_value > 0, ErrorPurchaseAmountTooLow);

    let ticket_amount = purchase_value / self.price_per_ticket;
    assert!(ticket_amount > 0, ErrorPurchaseAmountTooLow);

    // Calculate exact cost for tickets
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

    // Check if the buyer already exists in the current round
    let buyer = tx_context::sender(ctx);
    round.add_player_ticket(buyer, ticket_amount);

    purchase_coin // Refund excess amount
}

entry fun draw<T>(
    _self: &PrizePoolCap, // Enforcing the use of the PrizePoolCap
    phase_info_cap: &PhaseInfoCap,
    phase_info: &mut PhaseInfo,
    prize_pool: &mut PrizePool,
    round: &mut Round,
    pool_registry: &PoolRegistry,
    rand: &Random,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    phase_info.assert_drawing_phase();
    prize_pool.assert_current_round(round);

    assert!(prize_pool.pool_registry.is_some(), ErrorInvalidPoolRegistry);
    assert!(prize_pool.lounge_registry.is_some(), ErrorInvalidLoungeRegistry);

    let prize_reserves_value = prize_pool.get_total_prize_reserves_value<T>(pool_registry);
    let lp_tickets = prize_reserves_value / prize_pool.price_per_ticket;
    let total_fee_bps = prize_pool.lp_fee_bps + prize_pool.protocol_fee_bps;
    let lp_tickets_with_fee = calculate_total_ticket_with_fees(
        lp_tickets,
        total_fee_bps,
    );

    let mut generator = rand.new_generator(ctx);
    let ticket_number = generator.generate_u64_in_range(0, lp_tickets_with_fee);
    let winner_player = round.find_ticket_winner_address(ticket_number);

    // Store the winner in the current round
    round.record_drawing_result(clock, winner_player, prize_reserves_value);

    // Instantly move to the Distributing phase
    phase_info_cap.next(phase_info, clock, ctx);
}

public fun distribute<T>(
    _self: &PrizePoolCap,
    pool_cap: &PoolCap,
    lounge_cap: &LoungeCap,
    phase_info_cap: &PhaseInfoCap,
    phase_info: &mut PhaseInfo,
    prize_pool: &mut PrizePool,
    pool_registry: &mut PoolRegistry,
    lounge_registry: &mut LoungeRegistry,
    round: &mut Round,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    phase_info.assert_distributing_phase();
    prize_pool.assert_current_round(round);

    prize_pool.assert_valid_pool_registry(pool_registry);
    prize_pool.assert_valid_longe_registry(lounge_registry);


    if (round.get_winner().is_some()) {
        let winner = round.get_winner().extract();
        let lounge_number = lounge_cap.create_lounge<T>(
            lounge_registry,
            round.get_round_number(),
            winner,
            ctx,
        );
        prize_pool.inner_aggregate_prize_to_lounge<T>(
            phase_info,
            pool_cap,
            pool_registry,
            lounge_registry,
            lounge_number,
            ctx,
        );
    };

    let fee_reserves = prize_pool.inner_get_lp_fee_reserves_balance_mut<T>();
    inner_distribute_fee_to_pools<T>(pool_registry, fee_reserves, ctx);

    // We create round table for the next round
    prize_pool.inner_ensure_round_table_exists(current_round + 1, ctx);

    // Instantly move to the Settling phase
    phase_info_cap.next(phase_info, clock, ctx);
}

/// Internal
///

fun inner_aggregate_prize_to_lounge<T>(
    self: &PrizePool,
    phase_info: &PhaseInfo,
    pool_cap: &PoolCap,
    pool_registry: &mut PoolRegistry,
    lounge_registry: &mut LoungeRegistry,
    lounge_number: u64,
    ctx: &mut TxContext,
) {
    self.assert_valid_pool_registry(pool_registry);

    let risk_ratios = pool_registry.get_pool_risk_ratios();
    let risk_ratios_len = risk_ratios.length();

    let mut i = 0;
    while (i < risk_ratios_len) {
        let risk_ratio_bps = risk_ratios[i];
        pool_cap.withdraw_prize<T>(
            pool_registry,
            risk_ratio_bps,
            phase_info,
            lounge_registry,
            lounge_number,
            ctx,
        );
        i = i + 1;
    };
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

fun inner_find_ticket_winner_address(
    prize_pool: &PrizePool,
    round: &Round,
    ticket_number: u64,
): Option<address> {
    round.find_ticket_winner_address(ticket_number)
}

/// Assertions
///

fun assert_valid_pool_registry(self: &PrizePool, pool_registry: &PoolRegistry) {
    assert!(self.pool_registry.is_some(), ErrorInvalidPoolRegistry);
    assert!(object::id(pool_registry) == self.pool_registry.borrow(), ErrorInvalidPoolRegistry);
}

fun assert_valid_longe_registry(self: &PrizePool, lounge_registry: &LoungeRegistry) {
    assert!(self.lounge_registry.is_some(), ErrorInvalidLoungeRegistry);
    assert!(
        object::id(lounge_registry) == self.lounge_registry.borrow(),
        ErrorInvalidLoungeRegistry,
    );
}

fun assert_current_round(self: &PrizePool, round: &Round) {
    assert!(self.current_round.is_some(), ErrorInvalidRound);
    assert!(object::id(round) == self.current_round.borrow(), ErrorInvalidRound);
}



#[test_only]
public fun init_for_testing(ctx: &mut TxContext) {
    init(ctx);
}
