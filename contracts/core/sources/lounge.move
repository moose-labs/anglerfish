/// Manages prize lounges for lottery winners to claim reserves.
module anglerfish::lounge;

use anglerfish::errors;
use sui::bag::{Self, Bag};
use sui::balance::{Self, Balance};
use sui::coin::{Self, Coin, from_balance};
use sui::event::emit;

/// LOUNGE a OneTimeWitness struct
public struct LOUNGE has drop {}

public struct LoungeCap has key, store {
    id: UID,
}

public struct Lounge<phantom T> has key, store {
    id: UID,
    /// Reserves
    reserves: Balance<T>,
    /// An address that can claim the reserves
    recipient: address,
}

public struct LoungeRegistry has key {
    id: UID,
    /// The table of lounges that contain the lounge id and the claimable address
    lounges: Bag,
}

public struct LoungeCapCreated has copy, drop {
    cap_id: ID,
}

/// Initializes LoungeRegistry and LoungeCap with OneTimeWitness.
fun init(witness: LOUNGE, ctx: &mut TxContext) {
    assert!(sui::types::is_one_time_witness(&witness), errors::e_not_one_time_witness());

    let authority = ctx.sender();

    let authority_cap = LoungeCap {
        id: object::new(ctx),
    };

    let lounge_registry = LoungeRegistry {
        id: object::new(ctx),
        lounges: bag::new(ctx),
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
    ctx: &mut TxContext,
): u64 {
    assert!(recipient != @0x0, errors::e_recipient_zero());

    let lounge = Lounge<T> {
        id: object::new(ctx),
        reserves: balance::zero<T>(),
        recipient,
    };

    lounge_registry.lounges.add(lounge_number, lounge);
    lounge_number
}

/// Checks if a lounge is available in the registry.
public fun is_lounge_available(lounge_registry: &LoungeRegistry, lounge_number: u64): bool {
    lounge_registry.lounges.contains(lounge_number)
}

/// Allows the recipient to claim all reserves from a lounge.
public fun claim<T>(self: &mut LoungeRegistry, lounge_number: u64, ctx: &mut TxContext): Coin<T> {
    assert!(self.is_lounge_available(lounge_number), errors::e_not_available());

    let lounge = self.get_lounge_mut<T>(lounge_number);
    assert!(lounge.recipient == ctx.sender(), errors::e_unauthorized());
    assert!(lounge.reserves.value() > 0, errors::e_empty_reserves());

    from_balance(lounge.reserves.withdraw_all(), ctx)
}

/// Adds reserves to a lounge for prize distribution.
public fun add_reserves<T>(self: &mut LoungeRegistry, lounge_number: u64, coin: Coin<T>) {
    assert!(self.is_lounge_available(lounge_number), errors::e_not_available());
    let lounge = self.get_lounge_mut<T>(lounge_number);
    coin::put(&mut lounge.reserves, coin);
}

/// Deletes a completed Lounge
public fun delete_lounge<T>(_self: &LoungeCap, self: &mut LoungeRegistry, lounge_number: u64) {
    assert!(self.is_lounge_available(lounge_number), errors::e_not_available());

    // Remove lounge from bag
    let lounge: Lounge<T> = self.lounges.remove(lounge_number);
    let Lounge { id, reserves, recipient: _ } = lounge;

    // Lounge reserves must be zero
    assert!(reserves.value() == 0, errors::e_not_empty_reserves());

    // Delete objects
    balance::destroy_zero(reserves);
    object::delete(id);
}

/// Retrieves a lounge by number for inspection.
public fun get_lounge_number<T>(self: &mut LoungeRegistry, lounge_number: u64): &Lounge<T> {
    assert!(self.is_lounge_available(lounge_number), errors::e_not_available());
    self.lounges.borrow(lounge_number)
}

/// Gets the recipient address of a lounge.
public fun get_recipient<T>(lounge: &Lounge<T>): address {
    lounge.recipient
}

/// Gets the value of reserves in a lounge.
public fun get_prize_reserves_value<T>(lounge: &Lounge<T>): u64 {
    lounge.reserves.value()
}

/// Private functions

fun get_lounge_mut<T>(self: &mut LoungeRegistry, lounge_number: u64): &mut Lounge<T> {
    self.lounges.borrow_mut(lounge_number)
}

#[test_only]
public fun init_for_testing(ctx: &mut TxContext) {
    let witness = LOUNGE {};
    init(witness, ctx);
}
