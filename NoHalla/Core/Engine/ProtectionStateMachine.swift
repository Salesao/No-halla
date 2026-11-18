//
//  ProtectionStateMachine.swift
//  NoHalla
//
//  Pure protection state machine (implementation brief §5.3). It holds no I/O
//  and no timers: `reduce` maps an event plus environment to a new status and
//  an ordered list of effects that the engine executes. `setup` and `bypassing`
//  are derived UI statuses, not machine states (brief §5.3, spec D25/D27).
//
//  Transition table (§5.3) plus the owner decisions:
//   - D25: Cancel during grace triggers an immediate re-check, no hidden bypass.
//   - D27: the master Protection switch resumes everything and disables, or
//     re-enables into checking.
//   - Manual Resume all from frozen starts a bypass window; its expiry forces
//     an immediate check. Pause resumes everything and suspends freezing.
//

import Foundation

/// Events fed into the machine by the engine (network, IP verdicts, timers,
/// user actions and the master protection switch).
enum ProtectionEvent {
    case appStarted(configValid: Bool)
    case networkChanged
    case ipAllowed
    case ipDisallowed
    case noQuorum
    case graceExpired
    case freezeNowTapped
    case cancelTapped
    case resumeAllTapped
    case pauseRequested(PauseDuration)
    case pauseExpired
    case turnOnNowTapped
    case protectionEnabled
    case protectionDisabled
    case bypassExpired
}

/// Side effects the engine must perform, in order, after a transition.
enum Effect {
    case startGrace(seconds: Int)
    case cancelGrace
    case freeze(reason: FreezeReason)
    case resumeAll
    case startBypass(minutes: Int)
    case cancelBypass
    case startPause(PauseDuration)
    case cancelPause
    case immediateCheck
    case clearFrozenState
}

/// Pure, value-type protection state machine. No I/O, no timers, no globals.
struct ProtectionStateMachine {
    /// Inputs that shape transitions but are not part of the status itself.
    struct Environment {
        var freezeWhenUnknown: Bool
        var graceSeconds: Int
        var bypassMinutes: Int
        var trustedEmpty: Bool

        init(freezeWhenUnknown: Bool, graceSeconds: Int, bypassMinutes: Int, trustedEmpty: Bool) {
            self.freezeWhenUnknown = freezeWhenUnknown
            self.graceSeconds = graceSeconds
            self.bypassMinutes = bypassMinutes
            self.trustedEmpty = trustedEmpty
        }
    }

    private(set) var status: ProtectionStatus

    init() {
        self.status = .initializing
    }

    /// Applies one event. Unknown or inert combinations return no effects and
    /// leave the status unchanged. Freezing never happens before the first
    /// successful check, while paused/disabled, or while the trusted list is
    /// empty (setup).
    mutating func reduce(_ event: ProtectionEvent, env: Environment) -> [Effect] {
        // The master switch overrides every active state (D27).
        if case .protectionDisabled = event {
            return disable()
        }

        switch status {
        case .initializing:
            return reduceInitializing(event)
        case .checking:
            return reduceChecking(event, env: env)
        case .protected:
            return reduceProtected(event, env: env)
        case .grace:
            return reduceGrace(event, env: env)
        case .frozen:
            return reduceFrozen(event, env: env)
        case .unknown:
            return reduceUnknown(event, env: env)
        case .paused:
            return reducePaused(event)
        case .disabled:
            return reduceDisabled(event)
        }
    }

    // MARK: - Per-state reducers

    private mutating func reduceInitializing(_ event: ProtectionEvent) -> [Effect] {
        if case .appStarted(let configValid) = event, configValid {
            status = .checking
            return [.immediateCheck]
        }
        // No freeze before the first check; an invalid config keeps initializing.
        return []
    }

    private mutating func reduceChecking(_ event: ProtectionEvent, env: Environment) -> [Effect] {
        switch event {
        case .ipAllowed:
            status = .protected
            return []
        case .ipDisallowed:
            // Setup (empty trusted list) never freezes (FR-10).
            guard !env.trustedEmpty else { return [] }
            status = .grace
            return [.startGrace(seconds: env.graceSeconds)]
        case .noQuorum:
            guard !env.trustedEmpty else { return [] }
            status = .unknown
            return env.freezeWhenUnknown ? [.startGrace(seconds: env.graceSeconds)] : []
        case .networkChanged:
            return [.immediateCheck]
        case .pauseRequested(let duration):
            return pause(duration)
        case .protectionEnabled:
            return [.immediateCheck]
        default:
            return []
        }
    }

    private mutating func reduceProtected(_ event: ProtectionEvent, env: Environment) -> [Effect] {
        switch event {
        case .networkChanged:
            status = .checking
            return [.immediateCheck]
        case .ipDisallowed:
            guard !env.trustedEmpty else { return [] }
            status = .grace
            return [.startGrace(seconds: env.graceSeconds)]
        case .noQuorum:
            guard !env.trustedEmpty else { return [] }
            status = .unknown
            return env.freezeWhenUnknown ? [.startGrace(seconds: env.graceSeconds)] : []
        case .bypassExpired:
            status = .checking
            return [.cancelBypass, .immediateCheck]
        case .pauseRequested(let duration):
            return pause(duration)
        case .ipAllowed:
            return []
        default:
            return []
        }
    }

    private mutating func reduceGrace(_ event: ProtectionEvent, env: Environment) -> [Effect] {
        switch event {
        case .ipAllowed:
            status = .protected
            return [.cancelGrace]
        case .graceExpired:
            status = .frozen
            return [.freeze(reason: .ipDisallowed)]
        case .freezeNowTapped:
            status = .frozen
            return [.cancelGrace, .freeze(reason: .ipDisallowed)]
        case .cancelTapped:
            // D25: immediate re-check, no bypass.
            status = .checking
            return [.cancelGrace, .immediateCheck]
        case .networkChanged:
            status = .checking
            return [.cancelGrace, .immediateCheck]
        case .noQuorum:
            status = .unknown
            return env.freezeWhenUnknown
                ? [.cancelGrace, .startGrace(seconds: env.graceSeconds)]
                : [.cancelGrace]
        case .pauseRequested(let duration):
            status = .paused
            return [.cancelGrace, .resumeAll, .startPause(duration)]
        case .ipDisallowed:
            // Already counting down toward a freeze; keep the grace window.
            return []
        default:
            return []
        }
    }

    private mutating func reduceFrozen(_ event: ProtectionEvent, env: Environment) -> [Effect] {
        switch event {
        case .ipAllowed:
            status = .protected
            return [.resumeAll, .clearFrozenState]
        case .resumeAllTapped:
            status = .protected
            return [.resumeAll, .startBypass(minutes: env.bypassMinutes), .clearFrozenState]
        case .pauseRequested(let duration):
            status = .paused
            return [.resumeAll, .startPause(duration), .clearFrozenState]
        case .networkChanged:
            // R1: stay frozen; the immediate re-check resolves to allowed
            // (resumeAll + clearFrozenState) or keeps frozen. Leaving to
            // .checking here would strand SIGSTOP processes on the next
            // allowed verdict (which has no resume effect in .checking).
            return [.immediateCheck]
        case .ipDisallowed, .noQuorum:
            // Stay frozen; a later allowed verdict or Resume all releases.
            return []
        default:
            return []
        }
    }

    private mutating func reduceUnknown(_ event: ProtectionEvent, env: Environment) -> [Effect] {
        switch event {
        case .ipAllowed:
            status = .protected
            return [.cancelGrace]
        case .graceExpired:
            status = .frozen
            return [.freeze(reason: .unknown)]
        case .freezeNowTapped:
            status = .frozen
            return [.cancelGrace, .freeze(reason: .unknown)]
        case .ipDisallowed:
            // A known bad IP is disallowed regardless of freezeWhenUnknown.
            guard !env.trustedEmpty else { return [] }
            status = .grace
            return [.cancelGrace, .startGrace(seconds: env.graceSeconds)]
        case .cancelTapped:
            status = .checking
            return [.cancelGrace, .immediateCheck]
        case .networkChanged:
            status = .checking
            return [.cancelGrace, .immediateCheck]
        case .pauseRequested(let duration):
            status = .paused
            return [.cancelGrace, .resumeAll, .startPause(duration)]
        case .noQuorum:
            return []
        default:
            return []
        }
    }

    private mutating func reducePaused(_ event: ProtectionEvent) -> [Effect] {
        switch event {
        case .pauseExpired, .turnOnNowTapped:
            status = .checking
            return [.cancelPause, .immediateCheck]
        case .protectionEnabled:
            status = .checking
            return [.cancelPause, .immediateCheck]
        default:
            // Paused is orthogonal: network/IP events never initiate a freeze.
            return []
        }
    }

    private mutating func reduceDisabled(_ event: ProtectionEvent) -> [Effect] {
        switch event {
        case .protectionEnabled, .turnOnNowTapped:
            status = .checking
            return [.immediateCheck]
        default:
            return []
        }
    }

    // MARK: - Shared transitions

    /// Master switch off (D27): resume everything, cancel all timers, disable.
    private mutating func disable() -> [Effect] {
        status = .disabled
        return [.cancelGrace, .cancelBypass, .cancelPause, .resumeAll, .clearFrozenState]
    }

    /// Pause protection: resume everything and suspend freezing until the
    /// pause expires or the user turns protection back on.
    private mutating func pause(_ duration: PauseDuration) -> [Effect] {
        status = .paused
        return [.cancelGrace, .resumeAll, .startPause(duration), .clearFrozenState]
    }
}