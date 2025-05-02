module anglerfish::ticket_calculator {
    use math::u64::mul_div;

    const ErrorInvalidFees: u64 = 1;

    const BPS_DENOMINATOR: u64 = 10000;

    /// Calculates total tickets including fees: lp_tickets * 10000 / (10000 - total_fees_bps).
    /// Rounds down to the nearest integer. Aborts if total_fees_bps >= 10000.
    public(package) fun calculate_total_ticket_with_fees(
        lp_tickets: u64,
        total_fees_bps: u64,
    ): u64 {
        assert!(total_fees_bps < BPS_DENOMINATOR, ErrorInvalidFees);

        let lp_deducted_fees = (BPS_DENOMINATOR - total_fees_bps);
        let total_tickets = mul_div(lp_tickets, BPS_DENOMINATOR, lp_deducted_fees);
        total_tickets
    }
}

#[test_only]
module anglerfish::ticket_calculator_test {
    use anglerfish::ticket_calculator::{Self, calculate_total_ticket_with_fees};

    #[test]
    fun test_edge_cases() {
        assert!(calculate_total_ticket_with_fees(0, 3000) == 0);
        assert!(calculate_total_ticket_with_fees(100, 0) == 100);
        assert!(calculate_total_ticket_with_fees(100, 9999) == 1000100);
    }
    #[test, expected_failure(abort_code = ticket_calculator::ErrorInvalidFees)]
    fun test_invalid_fees() {
        calculate_total_ticket_with_fees(100, 10000);
    }
}
