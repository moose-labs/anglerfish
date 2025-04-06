module red_ocean::phase;

use sui::clock::Clock;

const ErrorUninitialized: u64 = 1;
const ErrorAlreadyInitialized: u64 = 2;
const ErrorNotLiquidityPhase: u64 = 3;
const ErrorNotTicketingPhase: u64 = 4;
const ErrorNotDrawingPhase: u64 = 5;
const ErrorNotSettlingPhase: u64 = 6;
const ErrorCurrentPhaseNotCompleted: u64 = 7;
const ErrorDurationTooShort: u64 = 8;

public enum Phase has copy, drop, store {
    /// The system is not yet initialized.
    Uninitialized,
    /// Users can deposit into or withdraw from the liquidity pool.
    LiquidityProviding,
    /// Deposits are closed; selling tickets to players who want liquidity.
    Ticketing,
    /// Tickets are drawing for prizes
    Drawing,
    /// The system is in the process of settling the results.
    Settling,
}

public struct PhaseDurations has copy, drop, store {
    /// The duration of the liquidity providing phase in seconds
    liquidity_providing_duration: u64,
    /// The duration of the ticketing phase in seconds
    ticketing_duration: u64,
    /// The duration of the drawing phase in seconds
    settling_duration: u64,
}

public struct PhaseInfoCap has key, store {
    id: UID,
}

public struct PhaseInfo has key {
    id: UID,
    /// Represents the current epoch or round in a sequential process
    current_round: u64,
    /// Indicates whether the liquidity pool is processing deposits, ticket sales, or drawing
    current_phase: Phase,
    /// The timestamp of the current phase in seconds
    current_phase_at: u64,
    /// The durations of each phase in seconds
    durations: PhaseDurations,
}

fun init(ctx: &mut TxContext) {
    let authority = ctx.sender();

    let phase_info_cap = PhaseInfoCap {
        id: object::new(ctx),
    };

    transfer::share_object(PhaseInfo {
        id: object::new(ctx),
        current_round: 0,
        current_phase: Phase::Uninitialized,
        current_phase_at: 0,
        durations: PhaseDurations {
            liquidity_providing_duration: 0,
            ticketing_duration: 0,
            settling_duration: 0,
        },
    });

    transfer::transfer(phase_info_cap, authority);
}

public fun initialize(
    _self: &PhaseInfoCap, // Enforce to use by phase info cap capability
    phase_info: &mut PhaseInfo,
    liquidity_providing_duration: u64,
    ticketing_duration: u64,
    settling_duration: u64,
    _: &mut TxContext,
) {
    assert!(phase_info.current_phase == Phase::Uninitialized, ErrorAlreadyInitialized);

    let phase_durations = PhaseDurations {
        liquidity_providing_duration,
        ticketing_duration,
        settling_duration,
    };

    phase_durations.assert_durations();
    phase_info.durations = phase_durations;

    // Set the initial phase to Settling
    phase_info.current_phase = Phase::Settling;
}

public fun next(
    self: &PhaseInfoCap, // Enforce to use by phase info cap capability
    phase_info: &mut PhaseInfo,
    clock: &Clock,
    _: &mut TxContext,
) {
    assert_initialized(phase_info);

    assert!(phase_info.is_current_phase_completed(clock), ErrorCurrentPhaseNotCompleted);

    phase_info.current_phase = phase_info.inner_next_phase();
    phase_info.current_phase_at = clock.timestamp_ms();

    self.inner_bump_round(phase_info);
}

public fun get_current_phase(self: &PhaseInfo): Phase {
    self.current_phase
}

public fun get_current_round(self: &PhaseInfo): u64 {
    self.current_round
}

public fun get_current_phase_at(self: &PhaseInfo): u64 {
    self.current_phase_at
}

public fun is_current_phase_completed(self: &PhaseInfo, clock: &Clock): bool {
    let current_timestamp_ms = clock.timestamp_ms();
    match (self.current_phase) {
        Phase::Uninitialized => false,
        Phase::LiquidityProviding => current_timestamp_ms >= self.estimate_current_phase_completed_at(),
        Phase::Ticketing => current_timestamp_ms >=  self.estimate_current_phase_completed_at(),
        Phase::Drawing => true,
        Phase::Settling => current_timestamp_ms >=  self.estimate_current_phase_completed_at(),
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
        Phase::Settling => current_phase_at + durations.settling_duration,
    }
}

/// Internal

fun inner_bump_round(_self: &PhaseInfoCap, phase_info: &mut PhaseInfo) {
    if (phase_info.current_phase == Phase::LiquidityProviding) {
        phase_info.current_round = phase_info.current_round + 1;
    }
}

fun inner_next_phase(self: &PhaseInfo): Phase {
    match (self.current_phase) {
        Phase::Uninitialized => Phase::Uninitialized,
        Phase::LiquidityProviding => Phase::Ticketing,
        Phase::Ticketing => Phase::Drawing,
        Phase::Drawing => Phase::Settling,
        Phase::Settling => Phase::LiquidityProviding,
    }
}

/// Assertions

fun assert_durations(self: &PhaseDurations) {
    assert!(self.liquidity_providing_duration > 0, ErrorDurationTooShort);
    assert!(self.ticketing_duration > 0, ErrorDurationTooShort);
    assert!(self.settling_duration > 0, ErrorDurationTooShort);
}

/// Check the current phase of the liquidity pool
/// and whether the phase info object is initialized.

public fun assert_initialized(self: &PhaseInfo) {
    assert!(self.current_phase != Phase::Uninitialized, ErrorUninitialized);
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

public fun assert_settling_phase(self: &PhaseInfo) {
    assert!(self.current_phase == Phase::Settling, ErrorNotSettlingPhase);
}

#[test_only]
public fun init_for_testing(ctx: &mut TxContext) {
    init(ctx);
}
