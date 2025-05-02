module anglerfish::errors ;

// phase.move errors
const EUninitialized: u64 = 1;
const EAlreadyInitialized: u64 = 2;
const ENotLiquidityPhase: u64 = 3;
const ENotTicketingPhase: u64 = 4;
const ENotDrawingPhase: u64 = 5;
const ENotDistributingPhase: u64 = 6;
const ENotSettlingPhase: u64 = 7;
const ECurrentPhaseNotCompleted: u64 = 8;
const ECurrentPhaseNotAllowedIterateFromEntry: u64 = 9;
const EDurationTooShort: u64 = 10;
const EInvalidRound: u64 = 11;
const ENotOneTimeWitness: u64 = 12;

// lounge.move errors
const EUnauthorized: u64 = 1001;
const ERecipientZero: u64 = 1002;
const ENotAvailable: u64 = 1003;
const EEmptyReserves: u64 = 1004;
const ENotEmptyReserves: u64 = 1005;

// ticket_calculator.move errors
const EInvalidFees: u64 = 2001;

// round.move errors
const EZeroTicketCount: u64 = 3001;
const EPlayerNotFound: u64 = 3002;
const EInvalidRoundNumber: u64 = 3003;
const EPlayerZero: u64 = 3004;

// pool.move errors
const ETooSmallToMint: u64 = 4001;
const ETooLargeToRedeem: u64 = 4002;
const EInsufficientShares: u64 = 4003;
const EInsufficientReserves: u64 = 4004;
const EPoolRiskRatioTooHigh: u64 = 4005;
const EPoolDepositDisabled: u64 = 4006;
const EPoolAlreadyCreated: u64 = 4007;
const EZeroRedeemValue: u64 = 4008;

// prize_pool.move errors
const EPurchaseAmountTooLow: u64 = 5001;
const ELpFeeAmountTooHigh: u64 = 5002;
const EProtocolFeeAmountTooHigh: u64 = 5003;
const EExcessiveFeeCharged: u64 = 5004;
const EInvalidRoundNumberSequence: u64 = 5005;

// Public accessors
public fun e_uninitialized(): u64 { EUninitialized }
public fun e_already_initialized(): u64 { EAlreadyInitialized }
public fun e_not_liquidity_phase(): u64 { ENotLiquidityPhase }
public fun e_not_ticketing_phase(): u64 { ENotTicketingPhase }
public fun e_not_drawing_phase(): u64 { ENotDrawingPhase }
public fun e_not_distributing_phase(): u64 { ENotDistributingPhase }
public fun e_not_settling_phase(): u64 { ENotSettlingPhase }
public fun e_current_phase_not_completed(): u64 { ECurrentPhaseNotCompleted }
public fun e_current_phase_not_allowed_iterate_from_entry(): u64 { ECurrentPhaseNotAllowedIterateFromEntry }
public fun e_duration_too_short(): u64 { EDurationTooShort }
public fun e_invalid_round(): u64 { EInvalidRound }
public fun e_not_one_time_witness(): u64 { ENotOneTimeWitness }

public fun e_unauthorized(): u64 { EUnauthorized }
public fun e_recipient_zero(): u64 { ERecipientZero }
public fun e_not_available(): u64 { ENotAvailable }
public fun e_empty_reserves(): u64 { EEmptyReserves }
public fun e_not_empty_reserves(): u64 { ENotEmptyReserves }

public fun e_invalid_fees(): u64 { EInvalidFees }

public fun e_zero_ticket_count(): u64 { EZeroTicketCount }
public fun e_player_not_found(): u64 { EPlayerNotFound }
public fun e_invalid_round_number(): u64 { EInvalidRoundNumber }
public fun e_player_zero(): u64 { EPlayerZero }

public fun e_too_small_to_mint(): u64 { ETooSmallToMint }
public fun e_too_large_to_redeem(): u64 { ETooLargeToRedeem }
public fun e_insufficient_shares(): u64 { EInsufficientShares }
public fun e_insufficient_reserves(): u64 { EInsufficientReserves }
public fun e_pool_risk_ratio_too_high(): u64 { EPoolRiskRatioTooHigh }
public fun e_pool_deposit_disabled(): u64 { EPoolDepositDisabled }
public fun e_pool_already_created(): u64 { EPoolAlreadyCreated }
public fun e_zero_redeem_value(): u64 { EZeroRedeemValue }

public fun e_purchase_amount_too_low(): u64 { EPurchaseAmountTooLow }
public fun e_lp_fee_amount_too_high(): u64 { ELpFeeAmountTooHigh }
public fun e_protocol_fee_amount_too_high(): u64 { EProtocolFeeAmountTooHigh }
public fun e_excessive_fee_charged(): u64 { EExcessiveFeeCharged }
public fun e_invalid_round_number_sequence(): u64 { EInvalidRoundNumberSequence }
