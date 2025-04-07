module red_ocean::suilend_adapter;

use suilend::lending_market::LendingMarket;
use suilend::reserve::ctoken_market_value;

public struct SuilendPoolKey<phantom T> has copy, drop, store {}

public(package) fun get_suilend_ctoken_position_value<P, T>(
    lending_market: &LendingMarket<P>,
    ctoken_amount: u64,
): u64 {
    let reserves = lending_market.reserve<P, T>();
    ctoken_market_value<P>(reserves, ctoken_amount).floor()
}
