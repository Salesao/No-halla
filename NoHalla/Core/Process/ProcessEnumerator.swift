//
//  ProcessEnumerator.swift
//  NoHalla
//
//  Read-only process discovery built on the public libproc API and
//  NSWorkspace (implementation brief §8.4, FR-16). Supplies the raw
//  material for the freeze set — running app instances, their children
//  and every process whose executable lives inside the app bundle —
//  plus the identity data (start time, uid, path) used to guard against
//  PID reuse before any signal is sent. No signals are issued here.
//

import AppKit
import Darwin
import Foundation

/// A running instance of an app as reported by NSWorkspace.
struct RunningProcess {
    let pid: Int32
    let bundleID: String
    let bundlePath: String
    let executablePath: String
}

/// Process enumeration helpers. All calls are best-effort: processes that
/// exit mid-enumeration or deny inspection are skipped, never fatal.
enum ProcessEnumerator {

    /// Running instances of the given bundle identifier (main app processes).
    /// Bundle and executable paths come from NSRunningApplication; empty
    /// strings mean the information was unavailable.
    static func instances(of bundleID: String) -> [RunningProcess] {
        // Filter the runningApplications property: the withBundleIdentifier:
        // method overload is ambiguous with the property in Swift.
        let apps = NSWorkspace.shared.runningApplications.filter { $0.bundleIdentifier == bundleID }
        return apps.map { app in
            RunningProcess(
                pid: app.processIdentifier,
                bundleID: app.bundleIdentifier ?? bundleID,
                bundlePath: app.bundleURL?.path ?? "",
                executablePath: app.executableURL?.path ?? ""
            )
        }
    }

    /// Every PID currently visible to the caller (`proc_listallpids`).
    /// The buffer is grown and the call repeated when the process table
    /// outgrows it between sizing and listing.
    static func allPIDs() -> [Int32] {
        listPIDs(initialCapacity: 1024) { buffer, bufferSize in
            proc_listallpids(buffer, bufferSize)
        }
    }

    /// Executable path of a process (`proc_pidpath`), or nil when the
    /// process is gone or its path cannot be read.
    static func path(of pid: Int32) -> String? {
        guard pid > 0 else { return nil }
        // PROC_PIDPATHINFO_MAXSIZE == 4 * MAXPATHLEN (the expression macro is
        // not imported into Swift; MAXPATHLEN is).
        let bufferSize = 4 * Int(MAXPATHLEN)
        var buffer = [CChar](repeating: 0, count: bufferSize)
        let result = proc_pidpath(pid, &buffer, UInt32(bufferSize))
        guard result > 0 else { return nil }
        return String(cString: buffer)
    }

    /// Start time of a process (`proc_bsdinfo.pbi_start_tvsec/tvusec`).
    /// Used as the identity check against PID reuse before each signal;
    /// nil when the process is gone or inspection is denied.
    static func startTime(of pid: Int32) -> (sec: Int64, usec: Int64)? {
        guard let info = bsdInfo(of: pid) else { return nil }
        return (sec: Int64(info.pbi_start_tvsec), usec: Int64(info.pbi_start_tvusec))
    }

    /// Owner uid of a process (`proc_bsdinfo.pbi_uid`), or nil when the
    /// process is gone or inspection is denied.
    static func uid(of pid: Int32) -> UInt32? {
        bsdInfo(of: pid)?.pbi_uid
    }

    /// Direct children of a process (`proc_listchildpids`), with the same
    /// overflow-retry handling as `allPIDs()`.
    static func childPIDs(of pid: Int32) -> [Int32] {
        guard pid > 0 else { return [] }
        return listPIDs(initialCapacity: 64) { buffer, bufferSize in
            proc_listchildpids(pid, buffer, bufferSize)
        }
    }

    /// PIDs of all processes whose executable path lies inside the app
    /// bundle at `path` (helpers, XPC services — FR-16). Scans the full
    /// process table; the prefix match requires a path-component boundary
    /// so `/Applications/Foo.app` never matches `/Applications/Foo.app2`.
    static func processes(insideBundleAt path: String) -> [Int32] {
        let trimmed = path.hasSuffix("/") ? String(path.dropLast()) : path
        guard !trimmed.isEmpty else { return [] }
        let prefix = trimmed + "/"
        var matches: [Int32] = []
        for pid in allPIDs() {
            guard let processPath = self.path(of: pid) else { continue }
            if processPath == trimmed || processPath.hasPrefix(prefix) {
                matches.append(pid)
            }
        }
        return matches
    }

    // MARK: - Private helpers

    /// Fetches `proc_bsdinfo` via `proc_pidinfo(PROC_PIDTBSDINFO)`.
    /// Accepts the result only when the kernel returned exactly one full
    /// struct; partial or failed reads yield nil.
    private static func bsdInfo(of pid: Int32) -> proc_bsdinfo? {
        guard pid > 0 else { return nil }
        var info = proc_bsdinfo()
        let size = MemoryLayout<proc_bsdinfo>.stride
        let result = proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, Int32(size))
        guard result == Int32(size) else { return nil }
        return info
    }

    /// Fills a PID buffer through a libproc listing call. These calls return
    /// the NUMBER OF PIDS placed in the buffer (not bytes), capped at the
    /// buffer capacity — the kernel does NOT report the required size when the
    /// buffer is too small. To detect truncation we allocate a `capacity + 1`
    /// sentinel slot: if the returned count exceeds `capacity` the kernel
    /// filled the sentinel, so more pids exist and the buffer is grown and the
    /// call retried (bounded). The buffer size argument is in bytes. This works
    /// for both proc_listallpids and proc_listchildpids (the NULL-size hint is
    /// valid only for proc_listallpids, so it is not used here).
    private static func listPIDs(
        initialCapacity: Int,
        list: (UnsafeMutableRawPointer?, Int32) -> Int32
    ) -> [Int32] {
        var capacity = max(initialCapacity, 1)
        for _ in 0..<16 {
            // One extra sentinel slot so a full buffer is detectable.
            var buffer = [pid_t](repeating: 0, count: capacity + 1)
            let result = buffer.withUnsafeMutableBytes { raw in
                list(raw.baseAddress, Int32(raw.count))
            }
            if result <= 0 { return [] }
            let count = Int(result)
            if count <= capacity {
                return Array(buffer.prefix(count)).filter { $0 > 0 }
            }
            // count == capacity + 1: the kernel filled the sentinel, so the
            // table is larger than capacity. Grow and retry.
            capacity *= 2
        }
        return []
    }
}
