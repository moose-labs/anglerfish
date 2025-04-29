module anglerfish::pool;

use anglerfish::lounge::LoungeRegistry;
use anglerfish::phase::PhaseInfo;
use math::u64::mul_div;
use sui::bag::{Self, Bag};
use sui::balance::Balance;
use sui::coin::{Self, Coin, from_balance};
use sui::table::{Self, Table};
use sui::vec_map::{Self, VecMap};

const ErrorTooSmallToMint: u64 = 1;
const ErrorTooLargeToRedeem: u64 = 2;
const ErrorInsufficientShares: u64 = 3;
const ErrorInsufficientReserves: u64 = 4;
const ErrorPoolRiskRatioTooHigh: u64 = 5;
const ErrorPoolDepositDisabled: u64 = 6;
const ErrorPoolAlreadyCreated: u64 = 7;

const MAX_RISK_RATIO_BPS: u64 = 10000;

public struct PoolCap has key, store {
    id: UID,
}

public struct PoolRegistry has key {
    id: UID,
    /// The list of pool risk ratios that are created
    pool_ids: VecMap<u64, address>,
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

    transfer::share_object(PoolRegistry {
        id: object::new(ctx),
        pool_ids: vec_map::empty(),
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
    _self: &PoolCap, // Enforce to use by pool cap capability
    pool_registry: &mut PoolRegistry,
    phase_info: &PhaseInfo,
    risk_ratio_bps: u64,
    ctx: &mut TxContext,
) {
    assert!(risk_ratio_bps <= MAX_RISK_RATIO_BPS, ErrorPoolRiskRatioTooHigh);
    assert!(pool_registry.pool_ids.contains(&risk_ratio_bps) == false, ErrorPoolAlreadyCreated);

    phase_info.assert_settling_phase();

    let pool_id = object::new(ctx);

    pool_registry.pool_ids.insert(risk_ratio_bps, pool_id.to_address());

    let pool = Pool<T> {
        id: pool_id,
        reserves: sui::balance::zero<T>(),
        total_reserves_value: 0,
        total_shares: 0,
        cumulative_fees: 0,
        risk_ratio_bps,
        user_shares: table::new<address, u64>(ctx),
        is_deposit_enabled: false,
    };

    bag::add(&mut pool_registry.pools, risk_ratio_bps, pool)
}

/// Pool Registry implementation
///

public fun get_total_reserves_value<T>(self: &PoolRegistry): u64 {
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

public fun get_total_prize_reserves_value<T>(self: &PoolRegistry): u64 {
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

public fun get_total_risk_ratio_bps(self: &PoolRegistry): u64 {
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

public fun get_pool_by_risk_ratio<T>(self: &PoolRegistry, risk_ratio_bps: u64): &Pool<T> {
    bag::borrow(&self.pools, risk_ratio_bps)
}

public fun get_pool_risk_ratios(self: &PoolRegistry): vector<u64> {
    self.pool_ids.keys()
}

/// Pool Registry inner functions
///

fun inner_get_pool_risk_ratios_with_len(self: &PoolRegistry): (vector<u64>, u64) {
    let pool_risk_ratios = self.get_pool_risk_ratios();
    let pool_risk_ratios_len = pool_risk_ratios.length();
    (pool_risk_ratios, pool_risk_ratios_len)
}

/// Pool implementation
///

public fun set_deposit_enabled<T>(
    _self: &PoolCap, // Enforce to use by pool cap capability
    pool_registry: &mut PoolRegistry,
    risk_ratio_bps: u64,
    enabled: bool,
) {
    let pool = get_pool_by_risk_ratio_mut<T>(pool_registry, risk_ratio_bps);
    pool.is_deposit_enabled = enabled;
}

public entry fun deposit<T>(
    pool_registry: &mut PoolRegistry,
    phase_info: &PhaseInfo,
    risk_ratio_bps: u64,
    deposit_coin: Coin<T>,
    ctx: &mut TxContext,
) {
    phase_info.assert_liquidity_providing_phase();

    let pool = get_pool_by_risk_ratio_mut<T>(pool_registry, risk_ratio_bps);
    pool.assert_deposit_enabled();

    let depositor = tx_context::sender(ctx);
    let deposit_amount = deposit_coin.value();

    // TODO: introduce new function, coin_to_share
    let reserve = pool.reserves.value();
    let shares_to_mint = if (reserve == 0) {
        deposit_amount
    } else {
        mul_div(deposit_amount, pool.total_shares, reserve)
    };

    assert!(shares_to_mint > 0, ErrorTooSmallToMint);

    // TODO: introduce new function, update total shares
    pool.total_shares = pool.total_shares + shares_to_mint;

    pool.inner_put_reserves_balance(deposit_coin);

    // TODO: introduce new function, update user shares
    if (table::contains<address, u64>(&pool.user_shares, depositor)) {
        let deposited = table::borrow_mut<address, u64>(&mut pool.user_shares, depositor);
        *deposited = *deposited + shares_to_mint;
    } else {
        table::add<address, u64>(&mut pool.user_shares, depositor, shares_to_mint);
    }
}

public entry fun redeem<T>(
    pool_registry: &mut PoolRegistry,
    phase_info: &PhaseInfo,
    risk_ratio_bps: u64,
    redeem_shares_amount: u64,
    ctx: &mut TxContext,
) {
    phase_info.assert_liquidity_providing_phase();

    let pool = get_pool_by_risk_ratio_mut<T>(pool_registry, risk_ratio_bps);

    let redeemer = tx_context::sender(ctx);
    let user_shares_amount = pool.get_user_shares(redeemer);

    assert!(redeem_shares_amount > 0, ErrorInsufficientShares);
    assert!(redeem_shares_amount <= user_shares_amount, ErrorTooLargeToRedeem);

    // TODO: intruduct new function, shares_to_coin
    let total_liquidity = pool.reserves.value();
    let total_shares = pool.total_shares;
    let redeem_value = mul_div(redeem_shares_amount, total_liquidity, total_shares);

    // Update user shares
    // TODO: intruduct new function, update_users_share
    let user_shares = pool.user_shares.borrow_mut(redeemer);
    *user_shares = *user_shares - redeem_shares_amount;

    // Update total shares
    // TODO: intruduct new function, update_total_shares
    pool.total_shares = pool.total_shares - redeem_shares_amount;

    let coin = pool.inner_take_reserves_balance(redeem_value, ctx);
    transfer::public_transfer(coin, redeemer);
}

public(package) fun get_pool_by_risk_ratio_mut<T>(
    self: &mut PoolRegistry,
    risk_ratio_bps: u64,
): &mut Pool<T> {
    bag::borrow_mut(&mut self.pools, risk_ratio_bps)
}

public(package) fun deposit_fee<T>(self: &mut Pool<T>, fee_coin: Coin<T>) {
    self.cumulative_fees = self.cumulative_fees + fee_coin.value();
    self.inner_put_reserves_balance(fee_coin);
}

public(package) fun withdraw_prize<T>(
    _self: &PoolCap, // Enforce to use by pool cap capability
    pool_registry: &mut PoolRegistry,
    risk_ratio_bps: u64,
    phase_info: &PhaseInfo,
    lounge_registry: &mut LoungeRegistry,
    lounge_number: u64,
    ctx: &mut TxContext,
) {
    phase_info.assert_distributing_phase();

    let pool = get_pool_by_risk_ratio_mut<T>(pool_registry, risk_ratio_bps);

    let prize_reserves_amount = pool.get_prize_reserves_value();
    let prize_coin = pool.inner_take_reserves_balance(prize_reserves_amount, ctx);

    lounge_registry.add_reserves(lounge_number, prize_coin);
}

public fun get_deposit_enabled<T>(self: &Pool<T>): bool {
    self.is_deposit_enabled
}

public fun get_pools(self: &PoolRegistry): &Bag {
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
    mul_div(self.risk_ratio_bps, self.total_reserves_value, MAX_RISK_RATIO_BPS)
}

public fun get_user_shares<T>(self: &Pool<T>, user: address): u64 {
    if (table::contains<address, u64>(&self.user_shares, user)) {
        *table::borrow<address, u64>(&self.user_shares, user)
    } else {
        0
    }
}

/// Inner functions
///

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

/// === Test functions ===
///

#[test_only]
public fun get_pool_by_risk_ratio_mut_for_testing<T>(
    self: &mut PoolRegistry,
    risk_ratio_bps: u64,
): &mut Pool<T> {
    get_pool_by_risk_ratio_mut(self, risk_ratio_bps)
}
