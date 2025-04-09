module red_ocean::lending;

use red_ocean::phase::PhaseInfo;
use red_ocean::suilend_adapter::{ctoken_to_underlying_value, underlying_to_ctoken_value};
use sui::bag::{Self, Bag};
use sui::balance::{Self, Balance};
use sui::clock::Clock;
use sui::coin::{Coin, into_balance, from_balance};
use sui::table::{Self, Table};
use suilend::lending_market::LendingMarket;
use suilend::reserve::CToken;

const ErrorPoolAlreadyRegistered: u64 = 1;
const ErrorPoolNotRegistered: u64 = 2;
const ErrorInvalidWeights: u64 = 3;
const ErrorSuilendLendingTokenValueLoss: u64 = 4;
const ErrorInsufficientSharesToBurn: u64 = 5;

public struct LendingCap has key, store {
    id: UID,
}

public struct AllocationCap has key, store {
    id: UID,
}

public struct LendingWeightBps has copy, drop, store {
    scallop: u64,
    suilend: u64,
}

public struct Lending has key {
    id: UID,
    /// The reserves bag
    reserves: Bag,
    /// Mapping pool id with shares amount
    pool_shares: Table<ID, u64>,
    /// Total shares on every pool
    total_shares: u64,
    /// Lending weights
    weights: LendingWeightBps,
}

public struct ReservesTokenType<phantom T> has copy, drop, store {}

public struct UnderlyingTokenReservesKey has copy, drop, store {}
public struct SuilendLendingTokenReservesKey has copy, drop, store {}

fun init(ctx: &mut TxContext) {
    let authority = ctx.sender();

    let lending_cap = LendingCap {
        id: object::new(ctx),
    };

    transfer::share_object(Lending {
        id: object::new(ctx),
        reserves: bag::new(ctx),
        pool_shares: table::new(ctx),
        total_shares: 0,
        weights: LendingWeightBps {
            scallop: 5000,
            suilend: 5000,
        },
    });

    transfer::public_transfer(lending_cap, authority);
}

#[test_only]
public fun init_for_testing(ctx: &mut TxContext) {
    init(ctx);
}

public fun new_allocation_cap(_self: &LendingCap, allocator: address, ctx: &mut TxContext) {
    let allocation_cap = AllocationCap {
        id: object::new(ctx),
    };
    transfer::public_transfer(allocation_cap, allocator)
}

public fun register_pool(
    _self: &LendingCap,
    lending: &mut Lending,
    pool_id: ID,
    _ctx: &mut TxContext,
) {
    assert!(lending.pool_shares.contains(pool_id) == false, ErrorPoolAlreadyRegistered);

    lending.pool_shares.add(pool_id, 0);
}

public fun update_weights(
    _self: &LendingCap,
    lending: &mut Lending,
    weights: LendingWeightBps,
    _ctx: &mut TxContext,
) {
    assert_weights_valid(weights);

    lending.weights = weights;
}

public fun assert_weights_valid(self: LendingWeightBps) {
    assert!(self.scallop + self.suilend == 10000, ErrorInvalidWeights);
}

// Public views

public fun get_total_reserves_value<U, SUILEND_SHARES_TOKEN>(
    lending: &Lending,
    suilend_lending_market: &LendingMarket<SUILEND_SHARES_TOKEN>,
): u64 {
    let underlying_reserves_balance = lending
        .reserves
        .borrow<ReservesTokenType<UnderlyingTokenReservesKey>, Balance<U>>(ReservesTokenType<
            UnderlyingTokenReservesKey,
        > {});
    let underlying_reserves_value = underlying_reserves_balance.value();

    let suilend_reserves_value = lending.get_suilend_lending_token_value<SUILEND_SHARES_TOKEN, U>(
        suilend_lending_market,
    );

    underlying_reserves_value + suilend_reserves_value
}

// Public mutable

public(package) fun add_liquidity<U, SUILEND_SHARES_TOKEN>(
    self: &mut Lending,
    phase_info: &PhaseInfo,
    suilend_lending_market: &mut LendingMarket<SUILEND_SHARES_TOKEN>,
    pool_id: ID,
    clock: &Clock,
    deposit_underlying_coin: Coin<U>,
    ctx: &mut TxContext,
) {
    assert!(self.pool_shares.contains(pool_id), ErrorPoolNotRegistered);

    phase_info.assert_liquidity_providing_phase();

    let deposit_underlying_value = deposit_underlying_coin.value();

    let reserves_token_type = ReservesTokenType<UnderlyingTokenReservesKey> {};
    self.inner_ensure_reserves_type_exists<UnderlyingTokenReservesKey, U>(
        reserves_token_type,
    );

    // Routing to lending markets
    self.inner_route_depositing(suilend_lending_market, deposit_underlying_coin, clock, ctx);

    // create shares for the pool
    let total_reserves_value = get_total_reserves_value<U, SUILEND_SHARES_TOKEN>(
        self,
        suilend_lending_market,
    );
    let total_shares = self.total_shares;
    let shares_to_mint = inner_calculate_shares_to_mint(
        total_reserves_value,
        deposit_underlying_value,
        total_shares,
    );
    if (self.pool_shares.contains(pool_id)) {
        let pool_shares = self.pool_shares.borrow_mut<ID, u64>(pool_id);
        *pool_shares = *pool_shares + shares_to_mint;
    } else {
        self.pool_shares.add(pool_id, shares_to_mint);
    };
}

public(package) fun remove_liquidity<U, SUILEND_SHARES_TOKEN>(
    self: &mut Lending,
    phase_info: &PhaseInfo,
    suilend_lending_market: &mut LendingMarket<SUILEND_SHARES_TOKEN>,
    pool_id: ID,
    redeem_underlying_value: u64,
    clock: &Clock,
    ctx: &mut TxContext,
): Coin<U> {
    assert!(self.pool_shares.contains(pool_id), ErrorPoolNotRegistered);

    phase_info.assert_liquidity_providing_phase();

    let reserves_token_type = ReservesTokenType<UnderlyingTokenReservesKey> {};
    self.inner_ensure_reserves_type_exists<UnderlyingTokenReservesKey, U>(
        reserves_token_type,
    );

    // Burn pool shares
    let total_reserves_value = get_total_reserves_value<U, SUILEND_SHARES_TOKEN>(
        self,
        suilend_lending_market,
    );
    let shares_to_burn = inner_calculate_shares_to_burn(
        total_reserves_value,
        redeem_underlying_value,
        self.total_shares,
    );
    let pool_shares = self.pool_shares.borrow_mut<ID, u64>(pool_id);
    assert!(*pool_shares >= shares_to_burn, ErrorInsufficientSharesToBurn);
    *pool_shares = *pool_shares - shares_to_burn;

    // Routing to lending markets
    let underlying_coin = self.inner_route_redeeming<U, SUILEND_SHARES_TOKEN>(
        suilend_lending_market,
        redeem_underlying_value,
        clock,
        ctx,
    );
    assert!(underlying_coin.value() == redeem_underlying_value, ErrorSuilendLendingTokenValueLoss);

    underlying_coin
}

// Inner

fun inner_route_depositing<U, SUILEND_SHARES_TOKEN>(
    self: &mut Lending,
    suilend_lending_market: &mut LendingMarket<SUILEND_SHARES_TOKEN>,
    coin: Coin<U>,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    // TODO: add weights logic
    // TODO: add scallop logic
    let deposit_value = coin.value();

    {
        let suilend_usdc_market_index = 0; // TODO: load from config + ability to recovery fund from deprecated markets
        let suilend_ctoken_coin = suilend_lending_market.deposit_liquidity_and_mint_ctokens<
            SUILEND_SHARES_TOKEN,
            U,
        >(
            suilend_usdc_market_index,
            clock,
            coin,
            ctx,
        );

        let suilend_reserves_token_key = get_suilend_reserves_token_key();
        self.inner_ensure_reserves_type_exists<
            SuilendLendingTokenReservesKey,
            CToken<SUILEND_SHARES_TOKEN, U>,
        >(suilend_reserves_token_key);

        let returned_ctoken_value = ctoken_to_underlying_value<SUILEND_SHARES_TOKEN, U>(
            suilend_lending_market,
            suilend_ctoken_coin.value(),
        );

        assert!(returned_ctoken_value >= deposit_value, ErrorSuilendLendingTokenValueLoss);

        // Add into suilend lending tokenreserves
        let suilend_ctoken_reserves_balance = self
            .reserves
            .borrow_mut<
                ReservesTokenType<SuilendLendingTokenReservesKey>,
                Balance<CToken<SUILEND_SHARES_TOKEN, U>>,
            >(suilend_reserves_token_key);
        suilend_ctoken_reserves_balance.join(into_balance(suilend_ctoken_coin));
    };
}

fun inner_route_redeeming<U, SUILEND_SHARES_TOKEN>(
    self: &mut Lending,
    suilend_lending_market: &mut LendingMarket<SUILEND_SHARES_TOKEN>,
    redeem_amount: u64,
    clock: &Clock,
    ctx: &mut TxContext,
): Coin<U> {
    let suilend_ctoken_reserves_balance = self
        .reserves
        .borrow_mut<
            ReservesTokenType<SuilendLendingTokenReservesKey>,
            Balance<CToken<SUILEND_SHARES_TOKEN, U>>,
        >(get_suilend_reserves_token_key());
    let ctoken_amount = underlying_to_ctoken_value<SUILEND_SHARES_TOKEN, U>(
        suilend_lending_market,
        redeem_amount,
    );
    let redeem_ctoken_balanace = suilend_ctoken_reserves_balance.split(ctoken_amount);
    let underlying_coin = suilend_lending_market.redeem_ctokens_and_withdraw_liquidity<
        SUILEND_SHARES_TOKEN,
        U,
    >(
        0,
        clock,
        from_balance(redeem_ctoken_balanace, ctx),
        option::none(),
        ctx,
    );
    underlying_coin
}

fun inner_ensure_reserves_type_exists<K, LT>(
    lending: &mut Lending,
    reserves_token_type: ReservesTokenType<K>,
) {
    if (lending.reserves.contains(reserves_token_type) == false) {
        lending.reserves.add(reserves_token_type, balance::zero<LT>());
    }
}

fun inner_calculate_shares_to_mint(reserves: u64, deposit_amount: u64, total_shares: u64): u64 {
    let shares_to_mint = if (reserves == 0) {
        deposit_amount
    } else {
        deposit_amount * total_shares / reserves
    };
    shares_to_mint
}

fun inner_calculate_shares_to_burn(reserves: u64, redeem_amount: u64, total_shares: u64): u64 {
    let shares_to_burn = if (reserves == 0) {
        0
    } else {
        redeem_amount * total_shares / reserves
    };
    shares_to_burn
}

// Suilend implementation

fun get_suilend_reserves_token_key(): ReservesTokenType<SuilendLendingTokenReservesKey> {
    ReservesTokenType<SuilendLendingTokenReservesKey> {}
}

public fun get_suilend_lending_token_value<SUILEND_SHARES_TOKEN, U>(
    lending: &Lending,
    lending_market: &LendingMarket<SUILEND_SHARES_TOKEN>,
): u64 {
    let suilend_ctoken_reserves_balance = lending
        .reserves
        .borrow<
            ReservesTokenType<SuilendLendingTokenReservesKey>,
            Balance<CToken<SUILEND_SHARES_TOKEN, U>>,
        >(get_suilend_reserves_token_key());
    ctoken_to_underlying_value<SUILEND_SHARES_TOKEN, U>(
        lending_market,
        suilend_ctoken_reserves_balance.value(),
    )
}
