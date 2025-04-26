module anglerfish::round;

use sui::table::{Self, Table};
use sui::vec_set::{Self, VecSet};

public struct Round has store {
    /// The table of players that contain the address and their purchased tickets
    player_tickets: Table<address, u64>,
    /// The list of unique players
    players: VecSet<address>,
    /// Winner address
    winner: Option<address>,
}

public fun new(ctx: &mut TxContext): Round {
    Round {
        player_tickets: table::new(ctx),
        players: vec_set::empty(),
        winner: option::none(),
    }
}

public(package) fun add_player_ticket(self: &mut Round, player: address, amount: u64) {
    if (self.players.contains(&player)) {
        let current_participant = self.player_tickets.borrow_mut(player);
        *current_participant = *current_participant + amount;
    } else {
        self.players.insert(player);
        self.player_tickets.add(player, amount);
    };
}

public(package) fun set_winner(self: &mut Round, winner: Option<address>) {
    self.winner = winner;
}

public(package) fun find_ticket_winner_address(self: &Round, ticket_number: u64): Option<address> {
    let mut i = 0;
    let mut cumulative_tickets = 0;
    let mut winner = option::none();

    let players = self.players.into_keys();
    let total_players = self.players.size();
    while (i < total_players) {
        let player = players[i];
        let ticket_count = *self.player_tickets.borrow(player);
        cumulative_tickets = cumulative_tickets + ticket_count;
        if (ticket_number < cumulative_tickets) {
            winner = option::some(player);
            break
        };
        i = i + 1;
    };

    winner
}

public fun contains(self: &Round, player: &address): bool {
    self.players.contains(player)
}

public fun get_winner(self: &Round): Option<address> {
    self.winner
}

public fun get_number_of_players(self: &Round): u64 {
    self.players.size()
}

public fun get_player_tickets(self: &Round, player: address): u64 {
    if (self.player_tickets.contains(player)) {
        *self.player_tickets.borrow(player)
    } else {
        0
    }
}

public fun get_total_purchased_tickets(self: &Round): u64 {
    let players = self.players.into_keys();
    let total_players = self.players.size();

    let mut i = 0;
    let mut total_tickets = 0;
    while (i < total_players) {
        let player = players[i];
        total_tickets = total_tickets + *self.player_tickets.borrow(player);
        i = i + 1;
    };

    total_tickets
}
