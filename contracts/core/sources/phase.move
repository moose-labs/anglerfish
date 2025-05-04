/// Manages lottery phase lifecycle and round tracking.
module anglerfish::phase;

use sui::clock::Clock;
use sui::event::emit;

// Error codes
const ErrorNotOneTimeWitness: u64 = 1;
const ErrorUninitialized: u64 = 2;
const ErrorAlreadyInitialized: u64 = 3;
const ErrorNotLiquidityPhase: u64 = 4;
const ErrorNotTicketingPhase: u64 = 5;
const ErrorNotDrawingPhase: u64 = 6;
const ErrorNotDistributingPhase: u64 = 7;
const ErrorNotSettlingPhase: u64 = 8;
const ErrorCurrentPhaseNotCompleted: u64 = 9;
const ErrorCurrentPhaseNotAllowedIterateFromEntry: u64 = 10;
const ErrorDurationTooShort: u64 = 11;
const ErrorInvalidRound: u64 = 12;

/// PHASE a OneTimeWitness struct
public struct PHASE has drop {}

/// Capability for phase transitions.
public struct PhaseInfoCap has key, store {
    id: UID,
}

public struct PhaseInfoCapCreated has copy, drop {
    cap_id: ID,
}

/// Represents the current phase of the lottery system.
public enum Phase has copy, drop, store {
    /// The system is not yet initialized.
    Uninitialized,
    /// Users can deposit into or withdraw from the liquidity pool.
    LiquidityProviding,
    /// Deposits are closed; selling tickets to players who want liquidity.
    Ticketing,
    /// Tickets are waiting for draw the prizes
    Drawing,
    /// The system is in the process of distributing the results.
    Distributing,
    /// The system is in the process of settling the results.
    Settling,
}

/// Stores durations for timed phases.
public struct PhaseDurations has copy, drop, store {
    /// The duration of the liquidity providing phase in seconds
    liquidity_providing_duration: u64,
    /// The duration of the ticketing phase in seconds
    ticketing_duration: u64,
}

/// Shared object tracking the lottery’s phase state, including UI metadata.
public struct PhaseInfo has key {
    id: UID,
    /// Represents the current epoch or round in a sequential process
    current_round_number: u64,
    /// Indicates whether the liquidity pool is processing deposits, ticket sales, or drawing
    current_phase: Phase,
    /// The timestamp of the current phase in seconds
    current_phase_at: u64,
    /// The durations of each phase in seconds
    durations: PhaseDurations,
    /// Timestamp of the last Drawing phase
    last_drawing_timestamp_ms: u64,
}

/// Initializes PhaseInfo and PhaseInfoCap with OneTimeWitness.
fun init(witness: PHASE, ctx: &mut TxContext) {
    assert!(sui::types::is_one_time_witness(&witness), ErrorNotOneTimeWitness);
    let authority = ctx.sender();

    let phase_info_cap = PhaseInfoCap {
        id: object::new(ctx),
    };

    let phase_info = PhaseInfo {
        id: object::new(ctx),
        current_round_number: 0,
        current_phase: Phase::Uninitialized,
        current_phase_at: 0,
        durations: PhaseDurations {
            liquidity_providing_duration: 0,
            ticketing_duration: 0,
        },
        last_drawing_timestamp_ms: 0,
    };

    emit(PhaseInfoCapCreated { cap_id: object::id(&phase_info_cap) });

    transfer::share_object(phase_info);
    transfer::transfer(phase_info_cap, authority);
}

/// Initializes PhaseInfo with durations and sets Settling phase to allow prize_pool to start a new round.
public fun initialize(
    _self: &PhaseInfoCap,
    phase_info: &mut PhaseInfo,
    liquidity_providing_duration: u64,
    ticketing_duration: u64,
    _: &mut TxContext,
) {
    assert!(phase_info.current_phase == Phase::Uninitialized, ErrorAlreadyInitialized);
    let phase_durations = PhaseDurations {
        liquidity_providing_duration,
        ticketing_duration,
    };

    phase_durations.assert_durations();
    phase_info.durations = phase_durations;

    // Set the initial phase to Settling
    phase_info.current_phase = Phase::Settling;
    phase_info.current_round_number = 0;
}

/// Advances phase from LiquidityProviding or Ticketing (entry point).
public fun next_entry(
    self: &PhaseInfoCap,
    phase_info: &mut PhaseInfo,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    assert!(phase_info.is_allowed_next_from_entry(), ErrorCurrentPhaseNotAllowedIterateFromEntry);
    self.next(phase_info, clock, ctx);
}

/// Advances to the next phase, updating timestamps and round numbers.
public(package) fun next(
    self: &PhaseInfoCap,
    phase_info: &mut PhaseInfo,
    clock: &Clock,
    _: &mut TxContext,
) {
    assert_initialized(phase_info);
    assert!(phase_info.is_current_phase_completed(clock), ErrorCurrentPhaseNotCompleted);

    phase_info.current_phase = phase_info.next_phase();
    phase_info.current_phase_at = clock.timestamp_ms();

    self.bump_round(phase_info);
}

public(package) fun set_last_drawing_timestamp_ms(
    _self: &PhaseInfoCap,
    phase_info: &mut PhaseInfo,
    clock: &Clock,
) {
    phase_info.assert_drawing_phase();
    phase_info.last_drawing_timestamp_ms = clock.timestamp_ms();
}

/// Public views

public fun is_initialized(self: &PhaseInfo): bool {
    self.current_phase != Phase::Uninitialized
}

// Gets to current phase of the platform
public fun get_current_phase(self: &PhaseInfo): Phase {
    self.current_phase
}

/// Gets the current epoch or round in a sequential process
public fun get_current_round_number(self: &PhaseInfo): u64 {
    self.current_round_number
}

/// Gets the timestamp of the current phase in seconds.
public fun get_current_phase_at(self: &PhaseInfo): u64 {
    self.current_phase_at
}

/// Gets the timestamp of the last Drawing phase.
public fun get_last_drawing_timestamp_ms(self: &PhaseInfo): u64 {
    self.last_drawing_timestamp_ms
}

public fun is_current_phase_completed(self: &PhaseInfo, clock: &Clock): bool {
    let current_timestamp_ms = clock.timestamp_ms();
    match (self.current_phase) {
        Phase::Uninitialized => false,
        Phase::LiquidityProviding => current_timestamp_ms >= self.estimate_current_phase_completed_at(),
        Phase::Ticketing => current_timestamp_ms >= self.estimate_current_phase_completed_at(),
        Phase::Drawing => true,
        Phase::Distributing => true,
        Phase::Settling => true,
    }
}

public fun is_allowed_next_from_entry(self: &PhaseInfo): bool {
    match (self.current_phase) {
        Phase::Uninitialized => false,
        Phase::LiquidityProviding => true,
        Phase::Ticketing => true,
        Phase::Drawing => false, // triggered by prize_pool::draw
        Phase::Distributing => false, // triggered by prize_pool::distribute
        Phase::Settling => false, // triggered by prize_pool::start_next_round
    }
}

public fun estimate_current_phase_completed_at(self: &PhaseInfo): u64 {
    let durations = self.durations;
    let current_phase_at = self.current_phase_at;
    match (self.current_phase) {
        Phase::Uninitialized => 0,
        Phase::LiquidityProviding => current_phase_at + durations.liquidity_providing_duration,
        Phase::Ticketing => current_phase_at + durations.ticketing_duration,
        Phase::Drawing => 0,
        Phase::Distributing => 0,
        Phase::Settling => 0,
    }
}

/// Private functions

fun bump_round(_self: &PhaseInfoCap, phase_info: &mut PhaseInfo) {
    if (phase_info.current_phase == Phase::LiquidityProviding) {
        phase_info.current_round_number = phase_info.current_round_number + 1;
    }
}

fun next_phase(self: &PhaseInfo): Phase {
    match (self.current_phase) {
        Phase::Uninitialized => Phase::Uninitialized,
        Phase::LiquidityProviding => Phase::Ticketing,
        Phase::Ticketing => Phase::Drawing,
        Phase::Drawing => Phase::Distributing,
        Phase::Distributing => Phase::Settling,
        Phase::Settling => Phase::LiquidityProviding,
    }
}

/// Assertions

fun assert_durations(self: &PhaseDurations) {
    assert!(self.liquidity_providing_duration > 0, ErrorDurationTooShort);
    assert!(self.ticketing_duration > 0, ErrorDurationTooShort);
}

/// Check the current phase of the liquidity pool
/// and whether the phase info object is initialized.

public fun assert_initialized(self: &PhaseInfo) {
    assert!(self.is_initialized(), ErrorUninitialized);
}

public fun assert_liquidity_providing_phase(self: &PhaseInfo) {
    assert!(self.current_phase == Phase::LiquidityProviding, ErrorNotLiquidityPhase);
}

public fun assert_ticketing_phase(self: &PhaseInfo) {
    assert!(self.current_phase == Phase::Ticketing, ErrorNotTicketingPhase);
}

public fun assert_drawing_phase(self: &PhaseInfo) {
    assert!(self.current_phase == Phase::Drawing, ErrorNotDrawingPhase);
}

public fun assert_distributing_phase(self: &PhaseInfo) {
    assert!(self.current_phase == Phase::Distributing, ErrorNotDistributingPhase);
}

public fun assert_settling_phase(self: &PhaseInfo) {
    assert!(self.current_phase == Phase::Settling, ErrorNotSettlingPhase);
}

public fun assert_current_round_number(self: &PhaseInfo, round_number: u64) {
    assert!(self.current_round_number == round_number, ErrorInvalidRound);
}

#[test_only]
public fun init_for_testing(ctx: &mut TxContext) {
    init(PHASE {}, ctx);
}
