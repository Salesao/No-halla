import Darwin
import Foundation

// NoHallaWatchdog — resumes frozen processes if No-halla dies unexpectedly.
// Stage S1 skeleton: argument parsing and parent liveness check only.
// The kqueue EVFILT_PROC/NOTE_EXIT watch and recovery land in s2-watchdog.

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

guard let arguments = parseArguments() else {
    FileHandle.standardError.write(Data("usage: NoHallaWatchdog --parent <pid> --state <path>\n".utf8))
    exit(1)
}

// If the parent is already gone at startup there is nothing to watch.
// Recovery of a stale state file is handled by the app's startup recovery.
guard parentIsAlive(arguments.parentPID) else {
    exit(0)
}

// S2 replaces this exit with the kqueue watch loop.
exit(0)