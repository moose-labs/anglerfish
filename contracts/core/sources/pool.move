/// Manages liquidity pools with varying risk ratios for lottery reserves.
module anglerfish::pool;

use anglerfish::phase::PhaseInfo;
use math::u64::mul_div;
use sui::bag::{Self, Bag};
use sui::balance::Balance;
use sui::coin::{Self, Coin, from_balance};
use sui::event::emit;
use sui::table::{Self, Table};
use sui::vec_map::{Self, VecMap};

const MAX_RISK_RATIO_BPS: u64 = 10000;

const ErrorNotOneTimeWitness: u64 = 4001;
const ErrorTooSmallToMint: u64 = 4002;
const ErrorTooLargeToRedeem: u64 = 4003;
const ErrorInsufficientShares: u64 = 4004;
const ErrorInsufficientReserves: u64 = 4005;
const ErrorPoolRiskRatioTooHigh: u64 = 4006;
const ErrorPoolDepositDisabled: u64 = 4007;
const ErrorPoolAlreadyCreated: u64 = 4008;
const ErrorZeroRedeemValue: u64 = 4009;

/// POOL a OneTimeWitness struct
public struct POOL has drop {}

public struct PoolCap has key, store {
    id: UID,
}

public struct PoolCapCreated has copy, drop {
    cap_id: ID,
}

public struct PoolRegistry has key {
    id: UID,
    /// The list of pool risk ratios that are created
    pool_ids: VecMap<u64, address>,
    /// Mapping from pool id to pool object
    pools: Bag,
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

/// Initializes PoolRegistry and PoolCap with OneTimeWitness.
fun init(witness: POOL, ctx: &mut TxContext) {
    assert!(sui::types::is_one_time_witness(&witness), ErrorNotOneTimeWitness);

    let authority = ctx.sender();

    let pool_cap = PoolCap {
        id: object::new(ctx),
    };

    let pool_registry = PoolRegistry {
        id: object::new(ctx),
        pool_ids: vec_map::empty(),
        pools: bag::new(ctx),
    };

    emit(PoolCapCreated { cap_id: object::id(&pool_cap) });

    transfer::share_object(pool_registry);
    transfer::transfer(pool_cap, authority);
}

/// Creates a new pool with the specified risk ratio.
public fun create_pool<T>(
    _self: &PoolCap,
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

    bag::add(&mut pool_registry.pools, risk_ratio_bps, pool);
}

/// Pool Registry implementation

/// Gets the total reserves value across all pools.
public fun get_total_reserves_value<T>(self: &PoolRegistry): u64 {
    let pool_risk_ratios = self.pool_ids.keys();
    let len = pool_risk_ratios.length();
    let mut total_reserves_value = 0;
    let mut i = 0;

    while (i < len) {
        let risk_ratio_bps = *vector::borrow(&pool_risk_ratios, i);
        let pool = self.get_pool_by_risk_ratio<T>(risk_ratio_bps);
        total_reserves_value = total_reserves_value + pool.get_reserves().value();

        i = i + 1;
    };

    total_reserves_value
}

/// Gets the total prize reserves value across all pools.
public fun get_total_prize_reserves_value<T>(self: &PoolRegistry): u64 {
    let pool_risk_ratios = self.pool_ids.keys();
    let len = pool_risk_ratios.length();
    let mut total_prize_reserves_value = 0;
    let mut i = 0;

    while (i < len) {
        let risk_ratio_bps = *vector::borrow(&pool_risk_ratios, i);
        let pool = self.get_pool_by_risk_ratio<T>(risk_ratio_bps);
        total_prize_reserves_value = total_prize_reserves_value + pool.get_prize_reserves_value();

        i = i + 1;
    };

    total_prize_reserves_value
}

/// Gets the total risk ratio across all pools.
public fun get_total_risk_ratio_bps(self: &PoolRegistry): u64 {
    let pool_risk_ratios = self.pool_ids.keys();
    let len = pool_risk_ratios.length();
    let mut total_risk_ratio_bps = 0;
    let mut i = 0;

    while (i < len) {
        let risk_ratio_bps = *vector::borrow(&pool_risk_ratios, i);
        total_risk_ratio_bps = total_risk_ratio_bps + risk_ratio_bps;

        i = i + 1;
    };

    total_risk_ratio_bps
}

/// Gets a pool by its risk ratio.
public fun get_pool_by_risk_ratio<T>(self: &PoolRegistry, risk_ratio_bps: u64): &Pool<T> {
    bag::borrow(&self.pools, risk_ratio_bps)
}

/// Gets the list of pool risk ratios.
public fun get_pool_risk_ratios(self: &PoolRegistry): vector<u64> {
    self.pool_ids.keys()
}

/// Pool implementation

/// Enables or disables deposits for a pool.
public fun set_deposit_enabled<T>(
    _self: &PoolCap,
    pool_registry: &mut PoolRegistry,
    risk_ratio_bps: u64,
    enabled: bool,
) {
    let pool = get_pool_by_risk_ratio_mut<T>(pool_registry, risk_ratio_bps);
    pool.is_deposit_enabled = enabled;
}

/// Deposits coins into a pool, minting shares.
public fun deposit<T>(
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

    // calculate share to mint
    let shares_to_mint = pool.coins_to_shares(deposit_amount);
    assert!(shares_to_mint > 0, ErrorTooSmallToMint);

    // update pool shares
    pool.inner_update_shares_for_deposit(depositor, shares_to_mint);

    // update pool reserves
    pool.inner_put_reserves_balance(deposit_coin);
}

/// Redeems shares from a pool, returning coins.
public fun redeem<T>(
    pool_registry: &mut PoolRegistry,
    phase_info: &PhaseInfo,
    risk_ratio_bps: u64,
    redeem_shares_amount: u64,
    ctx: &mut TxContext,
): Coin<T> {
    phase_info.assert_liquidity_providing_phase();

    let pool = get_pool_by_risk_ratio_mut<T>(pool_registry, risk_ratio_bps);

    let redeemer = tx_context::sender(ctx);
    let user_shares_amount = pool.get_user_shares(redeemer);

    assert!(redeem_shares_amount > 0, ErrorInsufficientShares);
    assert!(redeem_shares_amount <= user_shares_amount, ErrorTooLargeToRedeem);

    // Calculate redemption value before updating reserve value
    let redeem_value = pool.shares_to_coins(redeem_shares_amount);
    assert!(redeem_value > 0, ErrorZeroRedeemValue);

    // update pool reserves
    pool.inner_update_shares_for_redemption(redeemer, redeem_shares_amount);

    // transfer coin to redeemer
    let coin = pool.inner_take_reserves_balance(redeem_value, ctx);
    coin
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

/// Withdraws prize reserves from a pool.
public(package) fun withdraw_prize<T>(
    _self: &PoolCap,
    pool_registry: &mut PoolRegistry,
    risk_ratio_bps: u64,
    phase_info: &PhaseInfo,
    ctx: &mut TxContext,
): Coin<T> {
    phase_info.assert_distributing_phase();

    let pool = get_pool_by_risk_ratio_mut<T>(pool_registry, risk_ratio_bps);

    let prize_reserves_amount = pool.get_prize_reserves_value();

    let prize_coin = pool.inner_take_reserves_balance(prize_reserves_amount, ctx);

    prize_coin
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

public fun coins_to_shares<T>(self: &Pool<T>, amount: u64): u64 {
    let reserve = self.reserves.value();

    if (reserve == 0) {
        amount
    } else {
        mul_div(amount, self.total_shares, reserve)
    }
}

public fun shares_to_coins<T>(self: &Pool<T>, shares: u64): u64 {
    let reserve = self.reserves.value();
    mul_div(shares, reserve, self.total_shares)
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

public fun inner_update_shares_for_redemption<T>(
    self: &mut Pool<T>,
    redeemer: address,
    share_amount: u64,
) {
    // Update user shares
    let user_shares = self.user_shares.borrow_mut(redeemer);
    *user_shares = *user_shares - share_amount;

    // Update total shares
    self.total_shares = self.total_shares - share_amount;
}

public fun inner_update_shares_for_deposit<T>(
    self: &mut Pool<T>,
    depositor: address,
    share_amount: u64,
) {
    // Update user shares
    if (table::contains<address, u64>(&self.user_shares, depositor)) {
        let deposited = table::borrow_mut<address, u64>(&mut self.user_shares, depositor);
        *deposited = *deposited + share_amount;
    } else {
        table::add<address, u64>(&mut self.user_shares, depositor, share_amount);
    };

    // Update total shares
    self.total_shares = self.total_shares + share_amount;
}

/// Assertions

public fun assert_deposit_enabled<T>(self: &Pool<T>) {
    assert!(self.is_deposit_enabled, ErrorPoolDepositDisabled);
}

/// Test functions

#[test_only]
public fun get_pool_by_risk_ratio_mut_for_testing<T>(
    self: &mut PoolRegistry,
    risk_ratio_bps: u64,
): &mut Pool<T> {
    get_pool_by_risk_ratio_mut(self, risk_ratio_bps)
}

#[test_only]
public fun init_for_testing(ctx: &mut TxContext) {
    let witness = POOL {};
    init(witness, ctx);
}
