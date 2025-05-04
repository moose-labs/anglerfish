/// Manages prize lounges for lottery winners to claim reserves.
module anglerfish::lounge;

use sui::balance::Balance;
use sui::coin::{Self, Coin, from_balance};
use sui::event::emit;
use sui::table::{Self, Table};

// Error codes
const ErrorNotOneTimeWitness: u64 = 1001;
const ErrorUnauthorized: u64 = 1002;
const ErrorRecipientZero: u64 = 1003;
const ErrorNotAvailable: u64 = 1004;
const ErrorEmptyReserves: u64 = 1005;
const ErrorNotEmptyReserves: u64 = 1006;
const ErrorLoungeExists: u64 = 1005;

/// LOUNGE a OneTimeWitness struct
public struct LOUNGE has drop {}

public struct LoungeCap has key, store {
    id: UID,
}

public struct Lounge<phantom T> has key, store {
    id: UID,
    /// Lounge number
    lounge_number: u64,
    /// Reserves
    reserves: Balance<T>,
    /// An address that can claim the reserves
    recipient: address,
    // Active or not
    is_active: bool,
}

public struct LoungeRegistry has key {
    id: UID,
    /// The table of lounges that contain the lounge id and the claimable address
    lounges: Table<u64, ID>,
}

/// Event emitted when a LoungeCap is created.
public struct LoungeCapCreated has copy, drop {
    cap_id: ID,
}

/// Event emitted when a Lounge is created.
public struct LoungeCreated has copy, drop {
    lounge_id: ID,
    lounge_number: u64,
    recipient: address,
}

/// Event emitted when reserves are claimed from a Lounge.
public struct LoungeClaimed has copy, drop {
    lounge_id: ID,
    recipient: address,
    amount: u64,
}

/// Initializes LoungeRegistry and LoungeCap with OneTimeWitness.
fun init(witness: LOUNGE, ctx: &mut TxContext) {
    assert!(sui::types::is_one_time_witness(&witness), ErrorNotOneTimeWitness);

    let authority = ctx.sender();

    let authority_cap = LoungeCap {
        id: object::new(ctx),
    };

    let lounge_registry = LoungeRegistry {
        id: object::new(ctx),
        lounges: table::new(ctx),
    };

    emit(LoungeCapCreated { cap_id: object::id(&authority_cap) });

    transfer::share_object(lounge_registry);
    transfer::public_transfer(authority_cap, authority);
}

/// Creates a Lounge for a winner to claim prizes.
public fun create_lounge<T>(
    _self: &LoungeCap,
    lounge_registry: &mut LoungeRegistry,
    lounge_number: u64,
    recipient: address,
    prize_coin: Coin<T>,
    ctx: &mut TxContext,
): ID {
    assert!(recipient != @0x0, ErrorRecipientZero);
    assert!(!lounge_registry.lounges.contains(lounge_number), ErrorLoungeExists);

    let lounge = Lounge<T> {
        id: object::new(ctx),
        lounge_number,
        reserves: prize_coin.into_balance(),
        recipient,
        is_active: true,
    };

    let lounge_id = object::id(&lounge);
    transfer::share_object(lounge);
    lounge_registry.lounges.add(lounge_number, lounge_id);

    emit(LoungeCreated {
        lounge_id,
        lounge_number,
        recipient,
    });

    lounge_id
}

/// Checks if a lounge is available in the registry.
public fun is_lounge_available(lounge_registry: &LoungeRegistry, lounge_number: u64): bool {
    lounge_registry.lounges.contains(lounge_number)
}

/// Allows the recipient to claim all reserves from a lounge.
public fun claim<T>(
    self: &mut LoungeRegistry,
    lounge: &mut Lounge<T>,
    ctx: &mut TxContext,
): Coin<T> {
    self.assert_lounge(lounge);

    assert!(lounge.recipient == ctx.sender(), ErrorUnauthorized);
    assert!(lounge.reserves.value() > 0, ErrorEmptyReserves);

    let amount = lounge.reserves.value();
    let coin = from_balance(lounge.reserves.withdraw_all(), ctx);
    lounge.is_active = false;

    emit(LoungeClaimed {
        lounge_id: object::id(lounge),
        recipient: lounge.recipient,
        amount,
    });

    coin
}

/// Adds reserves to a lounge for prize distribution.
public(package) fun add_reserves<T>(
    self: &LoungeRegistry,
    lounge: &mut Lounge<T>,
    coin: Coin<T>,
) {
    self.assert_lounge(lounge);

    coin::put(&mut lounge.reserves, coin);
}

/// Deletes a completed Lounge
public fun delete_lounge<T>(
    _self: &LoungeCap,
    lounge_registry: &mut LoungeRegistry,
    lounge: &mut Lounge<T>,
) {
    lounge_registry.assert_lounge(lounge);

    let lounge_id = lounge_registry.lounges.remove(lounge.get_lounge_number());
    assert!(lounge.reserves.value() == 0, ErrorNotEmptyReserves);
    assert!(lounge_id == object::id(lounge), ErrorNotAvailable);

    lounge.is_active = false;
}

/// Retrieves a lounge by number for inspection.
public fun get_lounge_id(self: &mut LoungeRegistry, lounge_number: u64): Option<ID> {
    if (self.lounges.contains(lounge_number)) {
        option::some(*self.lounges.borrow(lounge_number))
    } else {
        option::none()
    }
}

/// Gets the recipient address of a lounge.
public fun get_lounge_number<T>(lounge: &Lounge<T>): u64 {
    lounge.lounge_number
}

/// Gets the recipient address of a lounge.
public fun get_recipient<T>(lounge: &Lounge<T>): address {
    lounge.recipient
}

/// Gets the value of reserves in a lounge.
public fun get_prize_reserves_value<T>(lounge: &Lounge<T>): u64 {
    lounge.reserves.value()
}

/// Asserts that a Lounge ID matches the registry for a given lounge number.
public fun assert_lounge<T>(lounge_registry: &LoungeRegistry, lounge: &Lounge<T>) {
    let lounge_number = lounge.get_lounge_number();
    assert!(lounge_registry.lounges.contains(lounge_number), ErrorNotAvailable);
    assert!(
        *lounge_registry.lounges.borrow(lounge_number) == object::id(lounge),
        ErrorNotAvailable,
    );
}

#[test_only]
public fun init_for_testing(ctx: &mut TxContext) {
    let witness = LOUNGE {};
    init(witness, ctx);
}
