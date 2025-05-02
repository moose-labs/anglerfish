module anglerfish::archive_round {
    use sui::table::{Self, Table};

    /// Shared object storing historical Round IDs.
    public struct ArchiveRound has key {
        id: UID,
        rounds: Table<u64, ID>,
    }

    /// Capability for authorized ArchiveRound operations.
    public struct ArchiveRoundCap has key { id: UID }

    /// Creates a new shared ArchiveRound and its capability, returns the ID and capability.
    public fun new(ctx: &mut TxContext): (ID, ArchiveRoundCap) {
        let archive = ArchiveRound {
            id: object::new(ctx),
            rounds: table::new(ctx),
        };
        let archive_id = object::id(&archive);
        let cap = ArchiveRoundCap { id: object::new(ctx) };
        transfer::share_object(archive);
        (archive_id, cap)
    }

    /// Adds a Round ID for a given round number.
    public fun add_round(_cap: &ArchiveRoundCap, archive: &mut ArchiveRound, round_number: u64, round_id: ID) {
        archive.rounds.add(round_number, round_id);
    }

    /// Retrieves the Round ID for a given round number, if it exists.
    public fun get_round_id(archive: &ArchiveRound, round_number: u64): Option<ID> {
        if (archive.rounds.contains(round_number)) {
            option::some(*archive.rounds.borrow(round_number))
        } else {
            option::none()
        }
    }

    /// Checks if a round number exists in the archive.
    public fun contains(archive: &ArchiveRound, round_number: u64): bool {
        archive.rounds.contains(round_number)
    }
}