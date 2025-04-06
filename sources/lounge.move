module red_ocean::lounge;

use sui::balance::{Self, Balance};
use sui::coin::{Self, Coin};

const ErrorUnauthorized: u64 = 0;
const ErrorRecipientCannotBeZero: u64 = 1;

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

public struct LoungeFactory has key {
    id: UID,
    /// Pool authorized creator
    creator: ID,
}

fun init(ctx: &mut TxContext) {
    let authority = ctx.sender();

    let authority_cap = LoungeCap {
        id: object::new(ctx),
    };

    transfer::share_object(LoungeFactory {
        id: object::new(ctx),
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
    lounge_factory: &mut LoungeFactory,
    recipient: address,
    ctx: &mut TxContext,
): Lounge<T> {
    assert!(object::id(self) == lounge_factory.creator, ErrorUnauthorized);
    assert!(recipient != @0x0, ErrorRecipientCannotBeZero);

    Lounge<T> {
        id: object::new(ctx),
        reserves: balance::zero<T>(),
        recipient,
    }
}

public fun claim<T>(self: &mut Lounge<T>, ctx: &mut TxContext): Balance<T> {
    assert!(self.recipient == ctx.sender(), ErrorUnauthorized);
    let bal = self.reserves.withdraw_all();
    bal
}

public fun add_reserves<T>(lounge: &mut Lounge<T>, coin: Coin<T>) {
    coin::put(&mut lounge.reserves, coin);
}
