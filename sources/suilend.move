module red_ocean::suilend_adapter;

use suilend::lending_market::LendingMarket;
use suilend::reserve::ctoken_market_value;

public(package) fun get_suilend_lending_token_value<SUILEND_SHARES_TOKEN, U>(
    lending_market: &LendingMarket<SUILEND_SHARES_TOKEN>,
    ctoken_amount: u64,
): u64 {
    let reserves = lending_market.reserve<SUILEND_SHARES_TOKEN, U>();
    ctoken_market_value<SUILEND_SHARES_TOKEN>(reserves, ctoken_amount).floor()
}
