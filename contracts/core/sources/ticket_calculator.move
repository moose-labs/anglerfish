module anglerfish::ticket_calculator {
    use math::u64::mul_div;

    public(package) fun calculate_total_ticket_with_fees(
        lp_tickets: u64,
        total_fees_bps: u64,
    ): u64 {
        let lp_deducted_fees = (10000 - total_fees_bps);
        let w = mul_div(lp_tickets, 10000, lp_deducted_fees);
        w
    }
}

#[test_only]
module anglerfish::ticket_calculator_test {
    use anglerfish::ticket_calculator::calculate_total_ticket_with_fees;

    #[test]
    public fun test_calculate_total_ticket_with_fees() {
        assert!(calculate_total_ticket_with_fees(100, 3000) == 142);
        assert!(calculate_total_ticket_with_fees(100_000_000_000, 3000) == 142857142857);
    }
}
