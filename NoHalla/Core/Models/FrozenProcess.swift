//
//  FrozenProcess.swift
//  NoHalla
//
//  Identity of a SIGSTOP-ed process persisted in state.json so recovery can
//  verify the process start time before sending SIGCONT (PID-reuse guard,
//  brief §5.4/§8.4, FR-18/19).
//

import Foundation

/// A frozen process with the identity data needed for safe resumption.
struct FrozenProcess: Codable, Equatable {
    var pid: Int32
    /// Process start time (seconds part), from proc_pidinfo/proc_bsdinfo.
    var startTimeSec: Int64
    /// Process start time (microseconds part), from proc_pidinfo/proc_bsdinfo.
    var startTimeUsec: Int64
    var bundleID: String
    var path: String
}
