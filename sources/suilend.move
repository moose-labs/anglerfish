module red_ocean::suilend_adapter;

use suilend::decimal::{Self, floor, div, mul};
use suilend::lending_market::LendingMarket;
use suilend::reserve::ctoken_ratio;

public(package) fun ctoken_to_underlying_value<SUILEND_SHARES_TOKEN, U>(
    lending_market: &LendingMarket<SUILEND_SHARES_TOKEN>,
    ctoken_amount: u64,
): u64 {
    let reserves = lending_market.reserve<SUILEND_SHARES_TOKEN, U>();
    floor(
        div(
            decimal::from(ctoken_amount),
            ctoken_ratio<SUILEND_SHARES_TOKEN>(reserves),
        ),
    )
}

public(package) fun underlying_to_ctoken_value<SUILEND_SHARES_TOKEN, U>(
    lending_market: &LendingMarket<SUILEND_SHARES_TOKEN>,
    underlying_amount: u64,
): u64 {
    let reserves = lending_market.reserve<SUILEND_SHARES_TOKEN, U>();
    floor(
        mul(
            decimal::from(underlying_amount),
            ctoken_ratio<SUILEND_SHARES_TOKEN>(reserves),
        ),
    )
}
