/// Calculates ticket amounts with fees for the lottery system.
module anglerfish::ticket_calculator;

// Error codes
const ErrorInvalidFees: u64 = 2001;

/// Basis points denominator (10000 = 100%).
const BPS_DENOMINATOR: u64 = 10000;

/// Calculates the total ticket amount including fees based on basis points.
public(package) fun calculate_total_ticket_with_fees(ticket_amount: u64, total_fees_bps: u64): u64 {
    assert!(total_fees_bps < BPS_DENOMINATOR, ErrorInvalidFees);
    let denominator = BPS_DENOMINATOR - total_fees_bps;
    ticket_amount * BPS_DENOMINATOR / denominator
}

#[test]
fun test_edge_cases() {
    assert!(calculate_total_ticket_with_fees(0, 3000) == 0);
    assert!(calculate_total_ticket_with_fees(100, 0) == 100);
    assert!(calculate_total_ticket_with_fees(100, 9999) == 1000000);
}

#[test, expected_failure(abort_code = ErrorInvalidFees)]
fun test_invalid_fees() {
    calculate_total_ticket_with_fees(100, 10000);
}
