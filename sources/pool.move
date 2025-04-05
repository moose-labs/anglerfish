module red_ocean::pool;

use red_ocean::phase::PhaseInfo;
use sui::bag::{Self, Bag};
use sui::balance::Balance;
use sui::coin::{Coin, into_balance, from_balance};
use sui::table::{Self, Table};
use sui::vec_set::{Self, VecSet};

const ErrorUnauthorized: u64 = 1;
const ErrorTooSmallToMint: u64 = 2;
const ErrorTooLargeToRedeem: u64 = 3;
const ErrorInsufficientShares: u64 = 4;
const ErrorPoolRiskRatioTooHigh: u64 = 5;
const ErrorPoolDepositDisabled: u64 = 6;
const ErrorPoolAlreadyCreated: u64 = 7;

const MAX_RISK_RATIO_BPS: u64 = 10000;

public struct PoolCap has key, store {
    id: UID,
}

public struct PoolFactory has key, store {
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
    /// The total shares in the pool
    total_shares: u64,
    /// Tracking user share objects
    user_shares: Table<address, u64>,
    /// The risk ratio in basis points
    risk_ratio_bps: u64,
    /// This flag is used to enable/disable deposit
    is_deposit_enabled: bool,
    /// The address of the prize pool
    /// This is used to allow the pool to transfer funds to the prize pool reserves
    prize_pool: address, // TODO: just to prize pool reserve
}

fun init(ctx: &mut TxContext) {
    let authority = ctx.sender();

    let authority_cap = PoolCap {
        id: object::new(ctx),
    };

    transfer::share_object(PoolFactory {
        id: object::new(ctx),
        pool_keys: vec_set::empty<u64>(),
        pools: bag::new(ctx),
        creator: object::id(&authority_cap),
    });

    transfer::transfer(authority_cap, authority);
}

public fun create_pool<T>(
    self: &mut PoolFactory,
    pool_cap: &PoolCap,
    risk_ratio_bps: u64,
    ctx: &mut TxContext,
) {
    // Avaliable for who hold cap
    assert!(self.creator == object::id(pool_cap), ErrorUnauthorized);
    assert!(risk_ratio_bps <= MAX_RISK_RATIO_BPS, ErrorPoolRiskRatioTooHigh);

    // Check if pool already created
    assert!(self.pool_keys.contains(&risk_ratio_bps) == false, ErrorPoolAlreadyCreated);

    let pool = Pool<T> {
        id: object::new(ctx),
        reserves: sui::balance::zero<T>(),
        total_shares: 0,
        risk_ratio_bps,
        user_shares: table::new<address, u64>(ctx),
        is_deposit_enabled: false,
        prize_pool: ctx.sender(), // TODO: change it
    };

    self.pool_keys.insert(risk_ratio_bps);

    bag::add(&mut self.pools, risk_ratio_bps, pool)
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
        deposit_amount / reserve * self.total_shares
    };

    assert!(shares_to_mint > 0, ErrorTooSmallToMint);

    self.total_shares = self.total_shares + shares_to_mint;
    self.reserves.join(into_balance(deposit_coin));

    if (table::contains<address, u64>(&self.user_shares, depositor)) {
        let deposited = table::borrow_mut<address, u64>(&mut self.user_shares, depositor);
        *deposited = *deposited + shares_to_mint;
    } else {
        table::add<address, u64>(&mut self.user_shares, depositor, shares_to_mint);
    }
}

public fun redeem<T>(
    self: &mut Pool<T>,
    phase_info: &PhaseInfo,
    shares_amount: u64,
    ctx: &mut TxContext,
): Coin<T> {
    phase_info.assert_liquidity_providing_phase();

    let redeemer = tx_context::sender(ctx);
    let user_deposit_amount = *table::borrow<address, u64>(&self.user_shares, redeemer);

    assert!(user_deposit_amount > 0, ErrorInsufficientShares);

    let total_liquidty = self.reserves.value();
    let total_shares = self.total_shares;
    let shares_price = total_liquidty / total_shares;
    let redeem_amount = shares_amount * shares_price;

    assert!(redeem_amount <= user_deposit_amount, ErrorTooLargeToRedeem);

    let redeem_coin = from_balance(self.reserves.split(redeem_amount), ctx);

    redeem_coin
}

public fun withdraw_to_reserves_prize<T>(
    self: &mut Pool<T>,
    phase_info: &PhaseInfo,
    amount: u64,
    ctx: &mut TxContext,
) {
    assert!(ctx.sender() == self.prize_pool, ErrorUnauthorized);
    phase_info.assert_settling_phase();

    let withdraw_coin = from_balance(self.reserves.split(amount), ctx);
    transfer::public_transfer(withdraw_coin, self.prize_pool);
}

public fun set_deposit_enabled<T>(self: &mut Pool<T>, _pool_cap: &PoolCap, enabled: bool) {
    self.is_deposit_enabled = enabled;
}

public fun get_deposit_enabled<T>(self: &Pool<T>): bool {
    self.is_deposit_enabled
}

public fun get_pool_keys(self: &PoolFactory): VecSet<u64> {
    self.pool_keys
}

public fun get_pools(self: &PoolFactory): &Bag {
    &self.pools
}

public fun get_pool_by_risk_ratio<T>(self: &PoolFactory, risk_ratio_bps: u64): &Pool<T> {
    bag::borrow(&self.pools, risk_ratio_bps)
}

public fun get_pool_mut_by_risk_ratio<T>(
    self: &mut PoolFactory,
    risk_ratio_bps: u64,
): &mut Pool<T> {
    bag::borrow_mut(&mut self.pools, risk_ratio_bps)
}

public fun get_reserves<T>(self: &Pool<T>): &Balance<T> {
    &self.reserves
}

public fun get_total_shares<T>(self: &Pool<T>): u64 {
    self.total_shares
}

public fun get_prize_reserves<T>(self: &Pool<T>): u64 {
    self.risk_ratio_bps * self.reserves.value() / MAX_RISK_RATIO_BPS
}

public fun get_user_shares<T>(self: &Pool<T>, user: address): u64 {
    if (table::contains<address, u64>(&self.user_shares, user)) {
        *table::borrow<address, u64>(&self.user_shares, user)
    } else {
        0
    }
}

public fun assert_deposit_enabled<T>(self: &Pool<T>) {
    assert!(self.is_deposit_enabled, ErrorPoolDepositDisabled);
}

#[test_only]
public fun init_for_testing(ctx: &mut TxContext) {
    init(ctx);
}
