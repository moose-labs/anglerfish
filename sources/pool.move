module red_ocean::pool;

use red_ocean::lounge::Lounge;
use red_ocean::phase::PhaseInfo;
use sui::bag::{Self, Bag};
use sui::balance::Balance;
use sui::coin::{Self, Coin, from_balance};
use sui::table::{Self, Table};
use sui::vec_set::{Self, VecSet};

const ErrorUnauthorized: u64 = 1;
const ErrorTooSmallToMint: u64 = 2;
const ErrorTooLargeToRedeem: u64 = 3;
const ErrorInsufficientShares: u64 = 4;
const ErrorInsufficientReserves: u64 = 5;
const ErrorPoolRiskRatioTooHigh: u64 = 6;
const ErrorPoolDepositDisabled: u64 = 7;
const ErrorPoolAlreadyCreated: u64 = 8;

const MAX_RISK_RATIO_BPS: u64 = 10000;

public struct PoolCap has key, store {
    id: UID,
}

public struct PoolFactory has key {
    id: UID,
    /// The list of pool risk ratios that are created
    pool_keys: VecSet<u64>,
    /// Mapping from pool id to pool object
    pools: Bag,
    /// Pool authorized creator
    creator: ID,
}

public struct Pool<phantom T> has key, store {
    id: UID,
    /// The total liquidity in the pool
    reserves: Balance<T>,
    /// The total value of the reserves in the pool
    total_reserves_value: u64,
    /// The total shares in the pool
    total_shares: u64,
    /// Tracking user share objects
    user_shares: Table<address, u64>,
    /// The total amount of fees in the pool
    cumulative_fees: u64,
    /// The risk ratio in basis points
    risk_ratio_bps: u64,
    /// This flag is used to enable/disable deposit
    is_deposit_enabled: bool,
}

fun init(ctx: &mut TxContext) {
    let authority = ctx.sender();

    let pool_cap = PoolCap {
        id: object::new(ctx),
    };

    transfer::share_object(PoolFactory {
        id: object::new(ctx),
        pool_keys: vec_set::empty<u64>(),
        pools: bag::new(ctx),
        creator: object::id(&pool_cap),
    });

    transfer::transfer(pool_cap, authority);
}

#[test_only]
public fun init_for_testing(ctx: &mut TxContext) {
    init(ctx);
}

public fun create_pool<T>(
    self: &PoolCap, // Enforce to use by pool cap capability
    pool_factory: &mut PoolFactory,
    risk_ratio_bps: u64,
    ctx: &mut TxContext,
) {
    // Avaliable for who hold cap
    assert!(pool_factory.creator == object::id(self), ErrorUnauthorized);
    assert!(risk_ratio_bps <= MAX_RISK_RATIO_BPS, ErrorPoolRiskRatioTooHigh);

    // Check if pool already created
    assert!(pool_factory.pool_keys.contains(&risk_ratio_bps) == false, ErrorPoolAlreadyCreated);

    let pool = Pool<T> {
        id: object::new(ctx),
        reserves: sui::balance::zero<T>(),
        total_reserves_value: 0,
        total_shares: 0,
        cumulative_fees: 0,
        risk_ratio_bps,
        user_shares: table::new<address, u64>(ctx),
        is_deposit_enabled: false,
    };

    pool_factory.pool_keys.insert(risk_ratio_bps);

    bag::add(&mut pool_factory.pools, risk_ratio_bps, pool)
}

/// Pool Factory implementation
///

public fun get_total_reserves_value<T>(self: &PoolFactory): u64 {
    let (pool_risk_ratios, len) = self.inner_get_pool_risk_ratios_with_len();

    let mut i = 0;
    let mut total_reserves_value = 0;
    while (i < len) {
        let risk_ratio_bps = pool_risk_ratios[i];
        let pool = self.get_pool_by_risk_ratio<T>(risk_ratio_bps);
        total_reserves_value = total_reserves_value + pool.get_reserves().value();
        i = i + 1;
    };

    total_reserves_value
}

public fun get_total_prize_reserves_value<T>(self: &PoolFactory): u64 {
    let (pool_risk_ratios, len) = self.inner_get_pool_risk_ratios_with_len();

    let mut i = 0;
    let mut total_prize_reserves_value = 0;
    while (i < len) {
        let risk_ratio_bps = pool_risk_ratios[i];
        let pool = self.get_pool_by_risk_ratio<T>(risk_ratio_bps);
        total_prize_reserves_value = total_prize_reserves_value + pool.get_prize_reserves_value();
        i = i + 1;
    };

    total_prize_reserves_value
}

public fun get_total_risk_ratio_bps(self: &PoolFactory): u64 {
    let (pool_risk_ratios, len) = self.inner_get_pool_risk_ratios_with_len();

    let mut i = 0;
    let mut total_risk_ratio_bps = 0;
    while (i < len) {
        let risk_ratio_bps = pool_risk_ratios[i];
        total_risk_ratio_bps = total_risk_ratio_bps + risk_ratio_bps;
        i = i + 1;
    };

    total_risk_ratio_bps
}

public fun get_pool_by_risk_ratio<T>(self: &PoolFactory, risk_ratio_bps: u64): &Pool<T> {
    bag::borrow(&self.pools, risk_ratio_bps)
}

public fun get_pool_by_risk_ratio_mut<T>(
    self: &mut PoolFactory,
    risk_ratio_bps: u64,
): &mut Pool<T> {
    bag::borrow_mut(&mut self.pools, risk_ratio_bps)
}

public fun get_pool_risk_ratios(self: &PoolFactory): VecSet<u64> {
    self.pool_keys
}

/// Pool Factory inner functions
///

fun inner_get_pool_risk_ratios_with_len(self: &PoolFactory): (vector<u64>, u64) {
    let pool_risk_ratios = self.get_pool_risk_ratios().into_keys();
    let pool_risk_ratios_len = pool_risk_ratios.length();
    (pool_risk_ratios, pool_risk_ratios_len)
}

/// Pool implementation
///

public fun set_deposit_enabled<T>(
    _self: &PoolCap, // Enforce to use by pool cap capability
    pool: &mut Pool<T>,
    enabled: bool,
) {
    pool.is_deposit_enabled = enabled;
}

public fun deposit<T>(
    self: &mut Pool<T>,
    phase_info: &PhaseInfo,
    deposit_coin: Coin<T>,
    ctx: &mut TxContext,
) {
    self.assert_deposit_enabled();
    phase_info.assert_liquidity_providing_phase();

    let depositor = tx_context::sender(ctx);
    let deposit_amount = deposit_coin.value();

    let reserve = self.reserves.value();
    let shares_to_mint = if (reserve == 0) {
        deposit_amount
    } else {
        deposit_amount * self.total_shares / reserve
    };

    assert!(shares_to_mint > 0, ErrorTooSmallToMint);

    self.total_shares = self.total_shares + shares_to_mint;

    self.inner_put_reserves_balance(deposit_coin);

    if (table::contains<address, u64>(&self.user_shares, depositor)) {
        let deposited = table::borrow_mut<address, u64>(&mut self.user_shares, depositor);
        *deposited = *deposited + shares_to_mint;
    } else {
        table::add<address, u64>(&mut self.user_shares, depositor, shares_to_mint);
    }
}

public fun deposit_fee<T>(self: &mut Pool<T>, fee_coin: Coin<T>) {
    self.cumulative_fees = self.cumulative_fees + fee_coin.value();
    self.inner_put_reserves_balance(fee_coin);
}

public fun redeem<T>(
    self: &mut Pool<T>,
    phase_info: &PhaseInfo,
    redeem_shares_amount: u64,
    ctx: &mut TxContext,
): Coin<T> {
    phase_info.assert_liquidity_providing_phase();

    let redeemer = tx_context::sender(ctx);
    let user_shares_amount = self.get_user_shares(redeemer);

    assert!(redeem_shares_amount > 0, ErrorInsufficientShares);
    assert!(redeem_shares_amount <= user_shares_amount, ErrorTooLargeToRedeem);

    let total_liquidity = self.reserves.value();
    let total_shares = self.total_shares;
    let redeem_value = redeem_shares_amount * total_liquidity / total_shares;

    // Update user shares
    let user_shares = self.user_shares.borrow_mut(redeemer);
    *user_shares = *user_shares - redeem_shares_amount;

    // Update total shares
    self.total_shares = self.total_shares - redeem_shares_amount;

    self.inner_take_reserves_balance(redeem_value, ctx)
}

public fun withdraw_prize<T>(
    _self: &PoolCap, // Enforce to use by pool cap capability
    pool: &mut Pool<T>,
    phase_info: &PhaseInfo,
    lounge: &mut Lounge<T>,
    ctx: &mut TxContext,
) {
    phase_info.assert_settling_phase();

    let prize_reserves_amount = pool.get_prize_reserves_value();
    let prize_coin = pool.inner_take_reserves_balance(prize_reserves_amount, ctx);

    lounge.add_reserves(prize_coin);
}

public fun get_deposit_enabled<T>(self: &Pool<T>): bool {
    self.is_deposit_enabled
}

public fun get_pools(self: &PoolFactory): &Bag {
    &self.pools
}

public fun get_reserves<T>(self: &Pool<T>): &Balance<T> {
    &self.reserves
}

public fun get_total_shares<T>(self: &Pool<T>): u64 {
    self.total_shares
}

public fun get_cumulative_fees<T>(self: &Pool<T>): u64 {
    self.cumulative_fees
}

public fun get_risk_ratio_bps<T>(self: &Pool<T>): u64 {
    self.risk_ratio_bps
}

public fun get_prize_reserves_value<T>(self: &Pool<T>): u64 {
    self.risk_ratio_bps * self.total_reserves_value / MAX_RISK_RATIO_BPS
}

public fun get_user_shares<T>(self: &Pool<T>, user: address): u64 {
    if (table::contains<address, u64>(&self.user_shares, user)) {
        *table::borrow<address, u64>(&self.user_shares, user)
    } else {
        0
    }
}

/// Inner functions

fun inner_put_reserves_balance<T>(self: &mut Pool<T>, coin: Coin<T>) {
    self.total_reserves_value = self.total_reserves_value + coin.value();
    coin::put(&mut self.reserves, coin);
}

fun inner_take_reserves_balance<T>(self: &mut Pool<T>, amount: u64, ctx: &mut TxContext): Coin<T> {
    assert!(amount <= self.reserves.value(), ErrorInsufficientReserves);
    self.total_reserves_value = self.total_reserves_value - amount;
    let coin = from_balance(self.reserves.split(amount), ctx);
    coin
}

/// Assertions

public fun assert_deposit_enabled<T>(self: &Pool<T>) {
    assert!(self.is_deposit_enabled, ErrorPoolDepositDisabled);
}
