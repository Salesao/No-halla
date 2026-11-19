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
    /// D30: true when the process was frozen only because it runs under the
    /// selected app's terminal, not because its executable lives in the app
    /// bundle. Reconcile uses this to resume such processes if the user turns
    /// the terminal option off. Absent in older state files → false.
    var terminalDescendant: Bool

    init(
        pid: Int32,
        startTimeSec: Int64,
        startTimeUsec: Int64,
        bundleID: String,
        path: String,
        terminalDescendant: Bool = false
    ) {
        self.pid = pid
        self.startTimeSec = startTimeSec
        self.startTimeUsec = startTimeUsec
        self.bundleID = bundleID
        self.path = path
        self.terminalDescendant = terminalDescendant
    }

    private enum CodingKeys: String, CodingKey {
        case pid, startTimeSec, startTimeUsec, bundleID, path, terminalDescendant
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        pid = try container.decode(Int32.self, forKey: .pid)
        startTimeSec = try container.decode(Int64.self, forKey: .startTimeSec)
        startTimeUsec = try container.decode(Int64.self, forKey: .startTimeUsec)
        bundleID = try container.decode(String.self, forKey: .bundleID)
        path = try container.decode(String.self, forKey: .path)
        terminalDescendant = try container.decodeIfPresent(Bool.self, forKey: .terminalDescendant) ?? false
    }
}