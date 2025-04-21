module red_ocean::ticket_calculator;

public(package) fun calculate_total_ticket_with_fees(lp_tickets: u64, total_fees_bps: u64): u64 {
    (lp_tickets * 10000) / (10000 - total_fees_bps)
}
