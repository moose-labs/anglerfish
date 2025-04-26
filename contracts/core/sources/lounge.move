module anglerfish::lounge;

use sui::bag::{Self, Bag};
use sui::balance::{Self, Balance};
use sui::coin::{Self, Coin, from_balance};

const ErrorUnauthorized: u64 = 0;
const ErrorRecipientCannotBeZero: u64 = 1;
const ErrorNotAvailableLounge: u64 = 2;

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
    /// Pool authorized creator
    creator: ID,
}

fun init(ctx: &mut TxContext) {
    let authority = ctx.sender();

    let authority_cap = LoungeCap {
        id: object::new(ctx),
    };

    transfer::share_object(LoungeRegistry {
        id: object::new(ctx),
        lounges: bag::new(ctx),
        creator: object::id(&authority_cap),
    });

    transfer::public_transfer(authority_cap, authority);
}

#[test_only]
public fun init_for_testing(ctx: &mut TxContext) {
    init(ctx);
}

public fun create_lounge<T>(
    self: &LoungeCap, // Enforce to use by lounge cap capability
    lounge_registry: &mut LoungeRegistry,
    lounge_number: u64,
    recipient: address,
    ctx: &mut TxContext,
): u64 {
    assert!(object::id(self) == lounge_registry.creator, ErrorUnauthorized);
    assert!(recipient != @0x0, ErrorRecipientCannotBeZero);

    let lounge = Lounge<T> {
        id: object::new(ctx),
        reserves: balance::zero<T>(),
        recipient,
    };

    lounge_registry.lounges.add(lounge_number, lounge);

    lounge_number
}

public fun is_lounge_available(lounge_registry: &LoungeRegistry, lounge_number: u64): bool {
    lounge_registry.lounges.contains(lounge_number)
}

public fun claim<T>(self: &mut LoungeRegistry, lounge_number: u64, ctx: &mut TxContext): Coin<T> {
    assert!(self.is_lounge_available(lounge_number), ErrorNotAvailableLounge);

    let lounge = self.inner_get_lounge_number_mut(lounge_number);

    assert!(lounge.recipient == ctx.sender(), ErrorUnauthorized);
    from_balance(lounge.reserves.withdraw_all(), ctx)
}

public fun add_reserves<T>(self: &mut LoungeRegistry, lounge_number: u64, coin: Coin<T>) {
    assert!(self.is_lounge_available(lounge_number), ErrorNotAvailableLounge);

    let lounge = self.inner_get_lounge_number_mut(lounge_number);
    coin::put(&mut lounge.reserves, coin);
}

public fun get_lounge_number<T>(self: &mut LoungeRegistry, lounge_number: u64): &Lounge<T> {
    assert!(self.is_lounge_available(lounge_number), ErrorNotAvailableLounge);
    self.lounges.borrow(lounge_number)
}

public fun get_recipient<T>(lounge: &Lounge<T>): address {
    lounge.recipient
}

public fun get_prize_reserves_value<T>(lounge: &Lounge<T>): u64 {
    lounge.reserves.value()
}

// === Private functions ===

fun inner_get_lounge_number_mut<T>(self: &mut LoungeRegistry, lounge_number: u64): &mut Lounge<T> {
    assert!(self.is_lounge_available(lounge_number), ErrorNotAvailableLounge);
    let lounge = self.lounges.borrow_mut(lounge_number);
    lounge
}
