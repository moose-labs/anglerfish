module red_ocean::lending;

use red_ocean::suilend_adapter::get_suilend_ctoken_position_value;
use sui::bag::{Self, Bag};
use sui::balance::{Self, Balance};
use sui::coin::{Coin, from_balance, into_balance};
use sui::table::{Self, Table};
use suilend::lending_market::LendingMarket;

const ErrorLendingPoolNotFound: u64 = 1;
const ErrorAllocationCannotBeLoss: u64 = 2;

public struct LendingCap has key, store {
    id: UID,
}

public struct AllocatorCap has key, store {
    id: UID,
}

public struct LendingFactory has key {
    id: UID,
    /// The bag of red-ocean lending pools mapping to the underlying token
    pools: Bag,
}

public struct Lending<phantom T> has key, store {
    id: UID,
    /// The total amount of assets in the lending pool
    reserves: Balance<T>,
    /// The bag of lending tokens
    lending_token_reserves: Bag,
    /// Mapping pool id to shares amount
    pool_shares: Table<ID, u64>,
    /// Total shares on every pool
    total_shares: u64,
}

/// An allocating position
/// This is a hot potato struct, it enforces the allocator
/// to fill the amount lend before end of the PTB.
public struct Allocating {
    before_allocation: u64,
}

public struct LendingPoolKey<phantom T> has copy, drop, store {}

fun init(ctx: &mut TxContext) {
    let authority = ctx.sender();

    let lending_cap = LendingCap {
        id: object::new(ctx),
    };

    transfer::share_object(LendingFactory {
        id: object::new(ctx),
        pools: bag::new(ctx),
    });

    transfer::public_transfer(lending_cap, authority);
}

public fun create_lending_pool<T>(
    _self: &LendingCap, // Enforce to use by lending capability
    lending_factory: &mut LendingFactory,
    key: LendingPoolKey<T>,
    ctx: &mut TxContext,
) {
    let pool = Lending {
        id: object::new(ctx),
        reserves: balance::zero<T>(),
        lending_token_reserves: bag::new(ctx),
        pool_shares: table::new(ctx),
        total_shares: 0,
    };

    lending_factory.pools.add(key, pool);
}

public fun new_allocator_cap(_self: &LendingCap, authorized: address, ctx: &mut TxContext) {
    let allocator_cap = AllocatorCap {
        id: object::new(ctx),
    };
    transfer::public_transfer(allocator_cap, authorized)
}

public fun suilend_begin<P, T>(
    _self: &AllocatorCap,
    lending_factory: &mut LendingFactory,
    key: LendingPoolKey<T>,
    lending_market: &LendingMarket<P>,
    ctx: &mut TxContext,
): (Coin<T>, Coin<P>, Allocating) {
    assert!(lending_factory.pools.contains(key), ErrorLendingPoolNotFound);

    let lending_pool = lending_factory.pools.borrow_mut<LendingPoolKey<T>, Lending<T>>(key);

    let lending_token_reserves = lending_pool
        .lending_token_reserves
        .borrow_mut<LendingPoolKey<T>, Balance<P>>(key);
    let lending_token_balance = lending_token_reserves.withdraw_all();
    let lending_token_coin = from_balance(lending_token_balance, ctx);
    let lending_token_value = get_suilend_ctoken_position_value<P, T>(
        lending_market,
        lending_token_coin.value(),
    );

    let underlying_token_balance = lending_pool.reserves.withdraw_all();
    let underlying_token_coin = from_balance(underlying_token_balance, ctx);
    let underlying_token_value = underlying_token_coin.value();

    (
        underlying_token_coin,
        lending_token_coin,
        Allocating {
            before_allocation: lending_token_value + underlying_token_value,
        },
    )
}

public fun end_suilend<P, T>(
    _self: &AllocatorCap,
    allocate: Allocating,
    lending_factory: &mut LendingFactory,
    key: LendingPoolKey<T>,
    lending_market: &LendingMarket<P>,
    underlying_coin: Coin<T>,
    lending_token_coin: Coin<P>,
) {
    let Allocating { before_allocation } = allocate;

    let underlying_token_value = underlying_coin.value();

    let lending_token_value = get_suilend_ctoken_position_value<P, T>(
        lending_market,
        lending_token_coin.value(),
    );

    let total_underlying_value = underlying_token_value + lending_token_value;

    assert!(total_underlying_value >= before_allocation, ErrorAllocationCannotBeLoss);

    let lending_pool = lending_factory.pools.borrow_mut<LendingPoolKey<T>, Lending<T>>(key);

    lending_pool.reserves.join(into_balance(underlying_coin));

    let lending_token_reserves = lending_pool
        .lending_token_reserves
        .borrow_mut<LendingPoolKey<T>, Balance<P>>(key);
    lending_token_reserves.join(into_balance(lending_token_coin));
}
