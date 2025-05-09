module usdc::usdc;

use sui::coin::{Self, TreasuryCap};

public struct USDC has drop {}

fun init(witness: USDC, ctx: &mut TxContext) {
    let (mut treasury, metadata) = coin::create_currency(
        witness,
        6,
        b"USDC",
        b"",
        b"",
        option::none(),
        ctx,
    );

    // Instantly mint 1 billion USDC to the sender
    mint(
        &mut treasury,
        1_000_000_000_000_000,
        ctx.sender(),
        ctx,
    );

    transfer::public_freeze_object(metadata);
    transfer::public_transfer(treasury, ctx.sender());
}

public fun mint(
    treasury_cap: &mut TreasuryCap<USDC>,
    amount: u64,
    recipient: address,
    ctx: &mut TxContext,
) {
    let coin = coin::mint(treasury_cap, amount, ctx);
    transfer::public_transfer(coin, recipient)
}
