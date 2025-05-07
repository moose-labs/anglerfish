/// Manages lottery rounds, ticket purchases, and winner selection.
module anglerfish::round;

use anglerfish::iterator::IteratorCap;
use sui::clock::Clock;
use sui::event::emit;
use sui::table::{Self, Table};

// Error codes
const ENotOneTimeWitness: u64 = 3001;
const ErrorZeroTicketCount: u64 = 3002;
const ErrorInvalidRoundNumber: u64 = 3003;
const ErrorPlayerZero: u64 = 3004;

/// ROUND a OneTimeWitness struct
public struct ROUND has drop {}

/// Shared object storing historical Round IDs.
public struct RoundRegistry has key {
    id: UID,
    rounds: Table<u64, ID>,
}

/// Capability for authorized RoundRegistry operations.
public struct RoundRegistryCap has key { id: UID }

public struct RoundRegistryCapCreated has copy, drop { cap_id: ID }

/// Represents a single ticket purchase by a player.
public struct Purchase has copy, drop, store {
    address: address,
    ticket_count: u64,
    start_index: u64,
}

public struct Round has key {
    /// Object id
    id: UID,
    /// Round number
    round_number: u64,
    /// Total ticket sold
    total_tickets: u64,
    /// The list of ticket purchases
    purchases: vector<Purchase>,
    /// Records of players and collection of purchases
    players: Table<address, vector<u64>>,
    /// Winner address
    winner: Option<address>,
    /// The prize amount for the round
    prize_amount: u64,
    /// The timestamp of drawing the winner
    drawing_timestamp_ms: u64,
    // Active or not
    is_active: bool,
}

/// Initializes RoundRegistry and RoundRegistryCap with OneTimeWitness.
fun init(witness: ROUND, ctx: &mut TxContext) {
    assert!(sui::types::is_one_time_witness(&witness), ENotOneTimeWitness);

    let authority = ctx.sender();

    let round_cap = RoundRegistryCap { id: object::new(ctx) };

    let round_registry = RoundRegistry {
        id: object::new(ctx),
        rounds: table::new(ctx),
    };

    emit(RoundRegistryCapCreated { cap_id: object::id(&round_cap) });

    transfer::share_object(round_registry);
    transfer::transfer(round_cap, authority);
}

/// Retrieves the Round ID for a given round number, if it exists.
public fun get_round_id(round_registry: &RoundRegistry, round_number: u64): Option<ID> {
    if (round_registry.rounds.contains(round_number)) {
        option::some(*round_registry.rounds.borrow(round_number))
    } else {
        option::none()
    }
}

/// Checks if a round number exists in the round_registry.
public fun contains(round_registry: &RoundRegistry, round_number: u64): bool {
    round_registry.rounds.contains(round_number)
}

/// Creates a new shared Round and registers it in RoundRegistry.
public(package) fun create_round(
    _iter_cap: &IteratorCap,
    round_registry: &mut RoundRegistry,
    round_number: u64,
    ctx: &mut TxContext,
): ID {
    let round_id = new(round_number, ctx);
    round_registry.rounds.add(round_number, round_id);
    round_id
}

/// Creates a new shared Round object for the given round number.
public(package) fun new(round_number: u64, ctx: &mut TxContext): ID {
    let round = Round {
        id: object::new(ctx),
        round_number,
        total_tickets: 0,
        purchases: vector::empty(),
        players: table::new(ctx),
        winner: option::none(),
        prize_amount: 0,
        drawing_timestamp_ms: 0,
        is_active: true,
    };

    let round_id = object::id(&round);
    transfer::share_object(round);
    round_id
}

public fun delete_round(
    _self: &RoundRegistryCap,
    round_registry: &mut RoundRegistry,
    round: &mut Round,
) {
    let round_id = round_registry.rounds.remove(round.get_round_number());

    assert!(round_id == object::id(round), ErrorInvalidRoundNumber);

    round.is_active = false;
}

/// Adds a player's ticket purchase, updating total_tickets and players table.
public(package) fun add_player_ticket(self: &mut Round, player: address, ticket_count: u64) {
    assert!(ticket_count > 0, ErrorZeroTicketCount);
    assert!(player != @0x0, ErrorPlayerZero);

    let start_index = self.total_tickets;
    self.total_tickets = self.total_tickets + ticket_count;
    let purchase = Purchase {
        address: player,
        ticket_count,
        start_index,
    };

    let purchase_index = self.purchases.length();
    vector::push_back(&mut self.purchases, purchase);
    if (!self.players.contains(player)) {
        self.players.add(player, vector::empty());
    };
    let player_purchases = self.players.borrow_mut(player);
    player_purchases.push_back(purchase_index);
}

/// Finds the winner's address for a given ticket number using binary search.
public(package) fun find_ticket_winner_address(self: &Round, ticket_number: u64): Option<address> {
    let mut left = 0;
    let mut right = self.purchases.length();

    // binary search
    while (left < right) {
        let mid = (left + right) / 2;
        let purchase = &self.purchases[mid];
        let start = purchase.start_index;
        let end = start + purchase.ticket_count;

        if (ticket_number < start) {
            right = mid;
        } else if (ticket_number >= end) {
            left = mid + 1;
        } else {
            return option::some(purchase.address)
        };
    };
    option::none()
}

/// Records the drawing result, including winner, prize amount, and timestamp.
public(package) fun record_drawing_result(
    self: &mut Round,
    clock: &Clock,
    winner: Option<address>,
    prize_amount: u64,
) {
    self.winner = winner;
    self.prize_amount = prize_amount;
    self.drawing_timestamp_ms = clock.timestamp_ms();
}

/// Checks if a player participated in the round.
public fun has_player(self: &Round, player: &address): bool {
    self.players.contains(*player)
}

/// Gets the round number.
public fun get_round_number(self: &Round): u64 {
    self.round_number
}

/// Gets the total tickets sold.
public fun total_tickets(self: &Round): u64 {
    self.total_tickets
}

/// Gets the winner's address, if any.
public fun get_winner(self: &Round): Option<address> {
    self.winner
}

/// Gets the prize amount for the round.
public fun get_prize_amount(self: &Round): u64 {
    self.prize_amount
}

/// Gets the timestamp of the drawing.
public fun get_drawing_timestamp_ms(self: &Round): u64 {
    self.drawing_timestamp_ms
}

/// Gets the number of unique players.
public fun get_number_of_players(self: &Round): u64 {
    self.players.length()
}

/// Gets the total tickets purchased by a player for UI display.
public fun get_player_tickets(self: &Round, player: address): u64 {
    if (!self.players.contains(player)) {
        return 0
    };

    let player_purchases = self.players.borrow(player);
    let mut total_tickets = 0;
    let mut i = 0;

    while (i < player_purchases.length()) {
        let purchase_index = *player_purchases.borrow(i);
        let purchase = self.purchases[purchase_index];
        total_tickets = total_tickets + purchase.ticket_count;

        i = i + 1;
    };

    total_tickets
}

/// Asserts that the round ID matches the round number in the registry.
public fun assert_round(round_registry: &RoundRegistry, round: &Round) {
    let opt_round_id = round_registry.get_round_id(round.get_round_number());
    assert!(opt_round_id.is_some(), ErrorInvalidRoundNumber);
    assert!(opt_round_id.borrow() == object::id(round), ErrorInvalidRoundNumber);
}

#[test_only]
public fun init_for_testing(ctx: &mut TxContext) {
    let witness = ROUND {};
    init(witness, ctx);
}
