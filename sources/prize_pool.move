module red_ocean::prize_pool;

use red_ocean::lounge::{LoungeCap, LoungeFactory};
use red_ocean::phase::{PhaseInfo, PhaseInfoCap};
use red_ocean::pool::{PoolFactory, PoolCap};
use red_ocean::ticket_calculator::calculate_total_ticket_with_fees;
use sui::bag::{Self, Bag};
use sui::balance::{Self, Balance};
use sui::clock::Clock;
use sui::coin::{Self, Coin, from_balance};
use sui::random::{Random, new_generator};
use sui::table::{Self, Table};
use sui::vec_set::{Self, VecSet};

const ErrorMaximumNumberOfPlayersReached: u64 = 1;
const ErrorInvalidPoolFactory: u64 = 2;
const ErrorPurchaseAmountTooLow: u64 = 3;
const ErrorFeeAmountTooHigh: u64 = 4;
const ErrorProtocolFeeAmountTooHigh: u64 = 5;

const TICKET_RESERVES_KEY: vector<u8> = b"ticket_reserves";
const FEE_RESERVES_KEY: vector<u8> = b"fee_reserves";
const PROTOCOL_FEE_RESERVES_KEY: vector<u8> = b"protocol_fee_reserves";

public struct Round has store {
    /// The table of players that contain the address and their purchased tickets
    player_tickets: Table<address, u64>,
    /// The list of unique players
    players: VecSet<address>,
    /// Winner address
    winner: Option<address>,
}

public struct PrizePoolCap has key, store {
    id: UID,
}

public struct PrizePool has key {
    id: UID,
    /// The pool factory that hold pools
    pool_factory: Option<ID>,
    /// The lounge factory that can create lounges
    lounge_factory: Option<ID>,
    /// The maximum number of players that can participate in the prize pool each round
    max_players: u64,
    /// The ticket price based on unit of the pool
    price_per_ticket: u64,
    /// The purchased ticket fees in basis points
    fee_bps: u64,
    /// The protocol fee in basis points
    protocol_fee_bps: u64,
    /// The reserves bag that hold the purchased tickets, fees, and protocol fees
    reserves: Bag,
    /// The table of round that contain participant address and their contribution
    rounds: Table<u64, Round>,
    /// An prize pool cap id that can manage the prize pool
    authority: ID,
}

fun init(ctx: &mut TxContext) {
    let authority = ctx.sender();

    let authority_cap = PrizePoolCap {
        id: object::new(ctx),
    };

    transfer::share_object(PrizePool {
        id: object::new(ctx),
        pool_factory: option::none(),
        lounge_factory: option::none(),
        max_players: 0,
        price_per_ticket: 0,
        fee_bps: 2500,
        protocol_fee_bps: 500,
        reserves: bag::new(ctx),
        rounds: table::new(ctx),
        authority: object::id(&authority_cap),
    });

    transfer::transfer(authority_cap, authority);
}

/// Capability to manage the prize pool

public fun set_pool_factory(
    _self: &PrizePoolCap,
    prize_pool: &mut PrizePool,
    pool_factory_id: ID,
    _ctx: &mut TxContext,
) {
    prize_pool.pool_factory = option::some(pool_factory_id);
}

public fun set_lounge_factory(
    _self: &PrizePoolCap,
    prize_pool: &mut PrizePool,
    lounge_factory_id: ID,
    _ctx: &mut TxContext,
) {
    prize_pool.lounge_factory = option::some(lounge_factory_id);
}

public fun set_max_players(
    _self: &PrizePoolCap,
    prize_pool: &mut PrizePool,
    max_players: u64,
    _ctx: &mut TxContext,
) {
    prize_pool.max_players = max_players;
}

public fun set_price_per_ticket(
    _self: &PrizePoolCap,
    prize_pool: &mut PrizePool,
    price_per_ticket: u64,
    _ctx: &mut TxContext,
) {
    prize_pool.price_per_ticket = price_per_ticket;
}

public fun set_fee_bps(
    _self: &PrizePoolCap,
    prize_pool: &mut PrizePool,
    fee_bps: u64,
    _ctx: &mut TxContext,
) {
    assert!(fee_bps < 6000, ErrorFeeAmountTooHigh);
    prize_pool.fee_bps = fee_bps;
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

public fun new_round_table_if_needed(
    _self: &PrizePoolCap,
    prize_pool: &mut PrizePool,
    phase_info: &PhaseInfo,
    ctx: &mut TxContext,
) {
    let current_round = phase_info.get_current_round();
    prize_pool.inner_ensure_round_table_exists(current_round, ctx);
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

public fun get_pool_factory(self: &PrizePool): Option<ID> {
    self.pool_factory
}

public fun get_lounge_factory(self: &PrizePool): Option<ID> {
    self.lounge_factory
}

public fun get_max_players(self: &PrizePool): u64 {
    self.max_players
}

public fun get_price_per_ticket(self: &PrizePool): u64 {
    self.price_per_ticket
}

public fun get_fee_bps(self: &PrizePool): u64 {
    self.fee_bps
}

public fun get_protocol_fee_bps(self: &PrizePool): u64 {
    self.protocol_fee_bps
}

public fun get_player_tickets(self: &PrizePool, phase_info: &PhaseInfo, player: address): u64 {
    let current_round = phase_info.get_current_round();
    let round = self.rounds.borrow(current_round);
    if (round.players.contains(&player)) {
        *round.player_tickets.borrow(player)
    } else {
        0
    }
}

/// Public functions
///

public fun get_total_prize_reserves_value<T>(_self: &PrizePool, pool_factory: &PoolFactory): u64 {
    pool_factory.get_total_prize_reserves_value<T>()
}

public fun get_ticket_reserves_value<T>(self: &PrizePool): u64 {
    self.inner_get_ticket_reserves_balance_value<T>()
}

public fun get_fee_reserves_value<T>(self: &PrizePool): u64 {
    self.inner_get_fee_reserves_balance_value<T>()
}

public fun get_protocol_fee_reserves_value<T>(self: &PrizePool): u64 {
    self.inner_get_protocol_fee_reserves_balance_value<T>()
}

public fun get_total_purchased_tickets(self: &PrizePool, phase_info: &PhaseInfo): u64 {
    let current_round = phase_info.get_current_round();
    let round = self.rounds.borrow(current_round);
    let players = round.players.into_keys();
    let total_players = round.players.size();

    let mut i = 0;
    let mut total_tickets = 0;
    while (i < total_players) {
        let player = players[i];
        total_tickets = total_tickets + *round.player_tickets.borrow(player);
        i = i + 1;
    };

    total_tickets
}

public fun purchase_ticket<T>(
    self: &mut PrizePool,
    phase_info: &PhaseInfo,
    purchase_coin: Coin<T>,
    ctx: &mut TxContext,
) {
    phase_info.assert_ticketing_phase();

    // Check if the current round table already exists
    let current_round = phase_info.get_current_round();
    self.inner_ensure_round_table_exists(current_round, ctx);

    self.assert_max_players(phase_info);

    let purchase_value = purchase_coin.value();
    assert!(purchase_value > 0, ErrorPurchaseAmountTooLow);

    let ticket_amount = purchase_value / self.price_per_ticket;
    assert!(ticket_amount > 0, ErrorPurchaseAmountTooLow);

    let mut purchase_coin = purchase_coin;

    // Transfer fee coin to fee reserves
    let fee_amount = self.inner_get_fee_amount(purchase_value);
    let fee_reserves = self.inner_get_fee_reserves_balance_mut<T>();
    coin::put(fee_reserves, purchase_coin.split(fee_amount, ctx));

    // Transfer protocol fee coin to protocol fee reserves
    let protocol_fee_amount = self.inner_get_protocol_fee_amount(purchase_value);
    let protocol_fee_reserves = self.inner_get_protocol_fee_reserves_balance_mut<T>();
    coin::put(protocol_fee_reserves, purchase_coin.split(protocol_fee_amount, ctx));

    // Transfer ticket coin to ticket reserves
    let ticket_reserves = self.inner_get_ticket_reserves_balance_mut<T>();
    coin::put(ticket_reserves, purchase_coin);

    // Check if the buyer already exists in the current round
    let buyer = tx_context::sender(ctx);
    let round = self.rounds.borrow_mut(current_round);

    if (round.players.contains(&buyer)) {
        let current_participant = round.player_tickets.borrow_mut(buyer);
        *current_participant = *current_participant + ticket_amount;
    } else {
        round.players.insert(buyer);
        round.player_tickets.add(buyer, ticket_amount);
    };
}

entry fun draw<T>(
    _self: &PrizePoolCap, // Enforcing the use of the PrizePoolCap
    phase_info_cap: &PhaseInfoCap,
    phase_info: &mut PhaseInfo,
    prize_pool: &mut PrizePool,
    pool_factory: &PoolFactory,
    rand: &Random,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    phase_info.assert_drawing_phase();

    let prize_reserves_value = prize_pool.get_total_prize_reserves_value<T>(pool_factory);
    let lp_tickets = prize_reserves_value / prize_pool.price_per_ticket;
    let total_fee_bps = prize_pool.fee_bps + prize_pool.protocol_fee_bps;
    let lp_tickets_with_fee = calculate_total_ticket_with_fees(
        lp_tickets,
        total_fee_bps,
    );

    let mut generator = rand.new_generator(ctx);
    let ticket_number = generator.generate_u64_in_range(1, lp_tickets_with_fee);

    let winner_player = prize_pool.inner_find_ticket_winner_address(phase_info, ticket_number);

    // Store the winner in the current round
    let current_round = phase_info.get_current_round();
    let round = prize_pool.rounds.borrow_mut(current_round);
    if (winner_player.is_some()) {
        round.winner = winner_player;
    } else {
        round.winner = option::none();
    };

    // Instantly move to the Settling phase
    phase_info_cap.next(phase_info, clock, ctx);
}

public fun settle<T>(
    _self: &PrizePoolCap,
    pool_cap: &PoolCap,
    lounge_cap: &LoungeCap,
    phase_info: &PhaseInfo,
    prize_pool: &mut PrizePool,
    pool_factory: &mut PoolFactory,
    lounge_factory: &mut LoungeFactory,
    ctx: &mut TxContext,
) {
    phase_info.assert_settling_phase();
    prize_pool.assert_valid_pool_factory(pool_factory);
    prize_pool.assert_valid_longe_factory(lounge_factory);

    let current_round = phase_info.get_current_round();
    let round = prize_pool.rounds.borrow_mut(current_round);

    if (round.winner.is_some()) {
        let winner = round.winner.extract();
        let lounge_number = lounge_cap.create_lounge<T>(lounge_factory, current_round, winner, ctx);
        prize_pool.inner_aggregate_prize_to_lounge<T>(
            phase_info,
            pool_cap,
            pool_factory,
            lounge_factory,
            lounge_number,
            ctx,
        );
    } else {
        // distribute ticket reserves to the pools
        let ticket_reserves = prize_pool.inner_get_ticket_reserves_balance_mut<T>();
        inner_distribute_fee_to_pools<T>(phase_info, pool_factory, ticket_reserves, ctx);
    };

    // distribute fees reserves to the pools
    let fee_reserves = prize_pool.inner_get_fee_reserves_balance_mut<T>();
    inner_distribute_fee_to_pools<T>(phase_info, pool_factory, fee_reserves, ctx);

    // We create round table for the next round
    prize_pool.inner_ensure_round_table_exists(current_round + 1, ctx);
}

/// Internal
///

fun inner_aggregate_prize_to_lounge<T>(
    self: &PrizePool,
    phase_info: &PhaseInfo,
    pool_cap: &PoolCap,
    pool_factory: &mut PoolFactory,
    lounge_factory: &mut LoungeFactory,
    lounge_number: u64,
    ctx: &mut TxContext,
) {
    self.assert_valid_pool_factory(pool_factory);

    let lounge = lounge_factory.get_lounge_number_mut<T>(lounge_number);

    let risk_ratios = pool_factory.get_pool_risk_ratios().into_keys();
    let risk_ratios_len = risk_ratios.length();

    let mut i = 0;
    while (i < risk_ratios_len) {
        let risk_ratio_bps = risk_ratios[i];
        pool_cap.withdraw_prize<T>(pool_factory, phase_info, lounge, risk_ratio_bps, ctx);
        i = i + 1;
    };
}

fun inner_distribute_fee_to_pools<T>(
    phase_info: &PhaseInfo,
    pool_factory: &mut PoolFactory,
    reserves: &mut Balance<T>,
    ctx: &mut TxContext,
) {
    phase_info.assert_settling_phase();

    let reserves_value = reserves.value();

    let total_risk_ratio_bps = pool_factory.get_total_risk_ratio_bps();
    let risk_ratios = pool_factory.get_pool_risk_ratios().into_keys();
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
        let pool = pool_factory.get_pool_by_risk_ratio_mut<T>(risk_ratio_bps);
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

fun inner_get_ticket_reserves_balance_value<T>(self: &PrizePool): u64 {
    if (!self.reserves.contains(TICKET_RESERVES_KEY)) {
        0
    } else {
        self.reserves.borrow<vector<u8>, Balance<T>>(TICKET_RESERVES_KEY).value()
    }
}

fun inner_get_ticket_reserves_balance_mut<T>(self: &mut PrizePool): &mut Balance<T> {
    if (!self.reserves.contains(TICKET_RESERVES_KEY)) {
        self.reserves.add(TICKET_RESERVES_KEY, balance::zero<T>());
    };
    self.reserves.borrow_mut<vector<u8>, Balance<T>>(TICKET_RESERVES_KEY)
}

fun inner_get_fee_reserves_balance_value<T>(self: &PrizePool): u64 {
    if (!self.reserves.contains(FEE_RESERVES_KEY)) {
        0
    } else {
        self.reserves.borrow<vector<u8>, Balance<T>>(FEE_RESERVES_KEY).value()
    }
}

fun inner_get_fee_reserves_balance_mut<T>(self: &mut PrizePool): &mut Balance<T> {
    if (!self.reserves.contains(FEE_RESERVES_KEY)) {
        self.reserves.add(FEE_RESERVES_KEY, balance::zero<T>());
    };
    self.reserves.borrow_mut<vector<u8>, Balance<T>>(FEE_RESERVES_KEY)
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

fun inner_get_fee_amount(self: &PrizePool, purchased_value: u64): u64 {
    let fee_amount = purchased_value * self.fee_bps / 10000;
    fee_amount
}

fun inner_get_protocol_fee_amount(self: &PrizePool, purchased_value: u64): u64 {
    let protocol_fee_amount = purchased_value * self.protocol_fee_bps / 10000;
    protocol_fee_amount
}

fun inner_ensure_round_table_exists(self: &mut PrizePool, current_round: u64, ctx: &mut TxContext) {
    if (!self.rounds.contains(current_round)) {
        self
            .rounds
            .add(
                current_round,
                Round {
                    player_tickets: table::new(ctx),
                    players: vec_set::empty<address>(),
                    winner: option::none(),
                },
            );
    };
}

fun inner_find_ticket_winner_address(
    prize_pool: &PrizePool,
    phase_info: &PhaseInfo,
    ticket_number: u64,
): Option<address> {
    let current_round = phase_info.get_current_round();
    let round = prize_pool.rounds.borrow(current_round);

    let mut i = 0;
    let mut cumulative_tickets = 0;
    let mut winner = option::none();

    let players = round.players.into_keys();
    let total_players = round.players.size();
    while (i < total_players) {
        let player = players[i];
        let ticket_count = *round.player_tickets.borrow(player);
        cumulative_tickets = cumulative_tickets + ticket_count;
        if (ticket_number < cumulative_tickets) {
            winner = option::some(player);
            break
        };
        i = i + 1;
    };

    winner
}

/// Assertions
///

fun assert_valid_pool_factory(self: &PrizePool, pool_factory: &PoolFactory) {
    assert!(self.pool_factory.is_some(), ErrorInvalidPoolFactory);
    assert!(object::id(pool_factory) == self.pool_factory.borrow(), ErrorInvalidPoolFactory);
}

fun assert_valid_longe_factory(self: &PrizePool, lounge_factory: &LoungeFactory) {
    assert!(self.lounge_factory.is_some(), ErrorInvalidPoolFactory);
    assert!(object::id(lounge_factory) == self.lounge_factory.borrow(), ErrorInvalidPoolFactory);
}

fun assert_max_players(self: &PrizePool, phase_info: &PhaseInfo) {
    let current_round = phase_info.get_current_round();
    let current_player_count = self.rounds.borrow(current_round).players.size();
    assert!(current_player_count < self.max_players, ErrorMaximumNumberOfPlayersReached);
}

#[test_only]
public fun init_for_testing(ctx: &mut TxContext) {
    init(ctx);
}
