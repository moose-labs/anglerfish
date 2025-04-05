module red_ocean::prize_pool;

use red_ocean::pool::{PoolFactory, Pool};
use sui::table::{Self, Table};

const ErrorUnauthorized: u64 = 1;

public struct Round has store {
    participants: Table<address, u64>,
}

public struct Lounge has store {
    id: UID,
    /// An address that can claim the prize
    claimable_address: address,
}

public struct PrizePoolCap has key, store {
    id: UID,
}

public struct PrizePool has key, store {
    id: UID,
    /// The pool factory that hold pools
    pool_factory: ID,
    /// The table of round that contain participant address and their contribution
    rounds: Table<u64, Round>,
    /// The table of lounges that contain the lounge id and the claimable address
    lounges: Table<u64, Lounge>,
    /// An prize pool cap id that can manage the prize pool
    authority: ID,
}

fun init(ctx: &mut TxContext) {
    let authority = ctx.sender();

    let authority_cap = PrizePoolCap {
        id: object::new(ctx),
    };

    transfer::share_object(PrizePool {
        id: object::new(ctx),
        pool_factory: object::id(&authority_cap), // will be replace with pool factory id
        rounds: table::new(ctx),
        lounges: table::new(ctx),
        authority: object::id(&authority_cap),
    });

    transfer::transfer(authority_cap, authority);
}

public fun set_pool_factory(
    self: &PrizePoolCap,
    prize_pool: &mut PrizePool,
    pool_factory_id: ID,
    _ctx: &mut TxContext,
) {
    assert!(object::id(self) == prize_pool.authority, ErrorUnauthorized);
    prize_pool.pool_factory = pool_factory_id;
}

public fun get_total_prize_pool<T>(_self: &PrizePool, pool_factory: &PoolFactory): u64 {
    let pool_keys = pool_factory.get_pool_keys().into_keys();
    let pool_keys_len = pool_keys.length();

    let mut i = 0;
    let mut total_prize_pool = 0;
    while (i < pool_keys_len) {
        let risk_ratio_bps = pool_keys[i];
        let pool = pool_factory.get_pool_by_risk_ratio<T>(risk_ratio_bps);
        total_prize_pool = total_prize_pool + pool.get_prize_reserves();
        i = i + 1;
    };

    total_prize_pool
}

public fun purchase_ticket(
    self: &mut PrizePool,
    pool_factory: &mut PoolFactory,
    risk_ratio_bps: u64,
    amount: u64,
    _ctx: &mut TxContext,
) {}

#[test_only]
public fun init_for_testing(ctx: &mut TxContext) {
    init(ctx);
}
