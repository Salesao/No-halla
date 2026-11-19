import Darwin
import Foundation

// NoHallaWatchdog — resumes frozen processes if No-halla dies unexpectedly
// (brief §5.5/§8.9, FR-41). Standalone executable inside the app bundle:
// Foundation/Darwin only, no UI, no root. On a normal quit the app resumes
// everything and clears state.json itself, so recovery here is a no-op.

struct WatchdogArguments {
    let parentPID: Int32
    let statePath: String
}

func parseArguments() -> WatchdogArguments? {
    var parentPID: Int32?
    var statePath: String?
    var index = 1
    let args = CommandLine.arguments
    while index < args.count {
        switch args[index] {
        case "--parent":
            if index + 1 < args.count, let pid = Int32(args[index + 1]) {
                parentPID = pid
                index += 2
            } else {
                return nil
            }
        case "--state":
            if index + 1 < args.count {
                statePath = args[index + 1]
                index += 2
            } else {
                return nil
            }
        default:
            return nil
        }
    }
    guard let pid = parentPID, let path = statePath else { return nil }
    return WatchdogArguments(parentPID: pid, statePath: path)
}

func parentIsAlive(_ pid: Int32) -> Bool {
    // kill(pid, 0) probes existence without sending a signal.
    if kill(pid, 0) == 0 { return true }
    return errno == EPERM
}

// MARK: - Recovery snapshot

/// Mirrors the frozen entries of PersistedState in state.json (schemaVersion 1).
/// Decoded locally: the watchdog must not depend on app-module code.
struct WatchdogFrozenProcess: Decodable {
    let pid: Int32
    let startTimeSec: Int64
    let startTimeUsec: Int64
    let bundleID: String
    let path: String
}

/// Mirrors PersistedState; dates are ISO 8601 as written by StateStore.
struct WatchdogState: Decodable {
    let schemaVersion: Int
    let frozen: [WatchdogFrozenProcess]
    let frozenSince: Date?
    let reason: String?
    let lastKnownIP: String?
}

/// Current start time of a process via public libproc (brief §8.4).
/// nil when the process is gone or not inspectable.
func currentStartTime(of pid: Int32) -> (sec: Int64, usec: Int64)? {
    var info = proc_bsdinfo()
    let size = Int32(MemoryLayout<proc_bsdinfo>.stride)
    let result = proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size)
    guard result == size else { return nil }
    return (Int64(info.pbi_start_tvsec), Int64(info.pbi_start_tvusec))
}

func logError(_ message: String) {
    FileHandle.standardError.write(Data("NoHallaWatchdog: \(message)\n".utf8))
}

/// Best-effort resume of every frozen process whose identity still matches,
/// then removal of the state file. A missing file means the app quit
/// normally and already cleaned up — nothing to do.
/// D29 (spec-v2, owner-approved): identity-checked intent recovery — G1
/// (FR-41/42) prioritized; the narrow G2 ownership window (a pause created by
/// another agent in the crash-before-SIGSTOP window) is an accepted residual
/// risk, narrowed by SafetyGuard. See DECISIONS.md D29 / README "Crash recovery".
func recoverFrozenProcesses(statePath: String) {
    let fileManager = FileManager.default
    guard fileManager.fileExists(atPath: statePath) else { return }

    let stateURL = URL(fileURLWithPath: statePath)
    let data: Data
    do {
        data = try Data(contentsOf: stateURL)
    } catch {
        // Leave the file in place for the app's startup recovery (FR-42).
        logError("cannot read state file: \(error)")
        return
    }

    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let state: WatchdogState
    do {
        state = try decoder.decode(WatchdogState.self, from: data)
    } catch {
        logError("cannot decode state file: \(error)")
        return
    }

    for record in state.frozen {
        // Never address process groups or launchd, even from a corrupt file.
        guard record.pid > 1 else { continue }
        // Identity check immediately before SIGCONT: a mismatching start
        // time means the PID was reused — skip, never signal a stranger.
        guard let start = currentStartTime(of: record.pid),
              start.sec == record.startTimeSec,
              start.usec == record.startTimeUsec else {
            continue
        }
        if kill(record.pid, SIGCONT) != 0 {
            logError("SIGCONT failed for pid \(record.pid) (errno \(errno))")
        }
    }

    try? fileManager.removeItem(at: stateURL)
}

// MARK: - Main

guard let arguments = parseArguments() else {
    FileHandle.standardError.write(Data("usage: NoHallaWatchdog --parent <pid> --state <path>\n".utf8))
    exit(1)
}

// A non-positive pid would address a process group, not a single process.
guard arguments.parentPID > 1 else {
    logError("invalid parent pid \(arguments.parentPID)")
    exit(1)
}

// If the parent is already gone at startup there is nothing to watch.
// Recovery of a stale state file is handled by the app's startup recovery.
guard parentIsAlive(arguments.parentPID) else {
    exit(0)
}

let kq = kqueue()
guard kq >= 0 else {
    logError("kqueue creation failed (errno \(errno))")
    exit(1)
}

var change = kevent(
    ident: UInt(arguments.parentPID),
    filter: Int16(EVFILT_PROC),
    flags: UInt16(EV_ADD | EV_ENABLE),
    fflags: UInt32(NOTE_EXIT),
    data: 0,
    udata: nil
)

if kevent(kq, &change, 1, nil, 0, nil) < 0 {
    let registrationErrno = errno
    close(kq)
    if registrationErrno == ESRCH {
        // The parent exited between the liveness probe and registration;
        // treat it as a parent exit and run recovery right away.
        recoverFrozenProcesses(statePath: arguments.statePath)
        exit(0)
    }
    logError("EVFILT_PROC registration failed (errno \(registrationErrno))")
    exit(1)
}

// Block until the parent exits; NOTE_EXIT is the only registered event.
var parentExited = false
while !parentExited {
    var event = kevent()
    let count = kevent(kq, nil, 0, &event, 1, nil)
    if count < 0 {
        if errno == EINTR { continue }
        close(kq)
        logError("kevent wait failed (errno \(errno))")
        exit(1)
    }
    if count == 0 { continue }
    if event.flags & UInt16(EV_ERROR) != 0 {
        close(kq)
        logError("kevent reported EV_ERROR (data \(event.data))")
        exit(1)
    }
    if event.filter == Int16(EVFILT_PROC), event.fflags & UInt32(NOTE_EXIT) != 0 {
        parentExited = true
    }
}
close(kq)

// Wait 1 s so a normal quit can finish its own resume-all + state cleanup
// first; then recover whatever is left. Total resume latency stays within
// the 2 s budget of FR-41 (1 s wait + signals).
sleep(1)
recoverFrozenProcesses(statePath: arguments.statePath)
exit(0)
