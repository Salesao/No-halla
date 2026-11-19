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

    /// Parent/child links for one BFS walk (D30). Roots are not in `pids`; the
    /// map is immutable once returned, so it can be read off the controller queue.
    struct ProcessTree {
    let parent: [Int32: Int32]
    let children: [Int32: [Int32]]
    /// Discovered pids, parents before children.
    let pids: [Int32]

    /// Every descendant of `root`, excluding `root` itself.
    func subtree(of root: Int32, limit: Int = 4096) -> [Int32] {
        var result: [Int32] = []
        var stack = [root]
        while let pid = stack.popLast() {
            for child in children[pid] ?? [] {
                result.append(child)
                if result.count >= limit { return result }
                stack.append(child)
            }
        }
        return result
    }
    }

    /// Walks the descendants of `roots` breadth-first and records the links
    /// the freeze selection needs. Depth and node caps bound the walk on
    /// pathological forks; the visited set prevents cycles and pid reuse
    /// inside one walk (D30).
    static func tree(rootedAt roots: [Int32], maxDepth: Int = 24, maxCount: Int = 8192) -> ProcessTree {
        var parent: [Int32: Int32] = [:]
        var children: [Int32: [Int32]] = [:]
        var pids: [Int32] = []
        var visited = Set(roots.filter { $0 > 1 })
        var frontier = Array(visited)
        var depth = 0

        while !frontier.isEmpty && depth < maxDepth && pids.count < maxCount {
            var next: [Int32] = []
            walk: for pid in frontier {
                for child in childPIDs(of: pid) {
                    guard child > 1, visited.insert(child).inserted else { continue }
                    parent[child] = pid
                    children[pid, default: []].append(child)
                    pids.append(child)
                    next.append(child)
                    if pids.count >= maxCount { break walk }
                }
            }
            frontier = next
            depth += 1
        }
        return ProcessTree(parent: parent, children: children, pids: pids)
    }

    /// `pbi_comm`: the kernel's short process name (16 chars), available even
    /// when `proc_pidpath` fails. Login shells report "-zsh".
    static func comm(of pid: Int32) -> String? {
        guard let info = bsdInfo(of: pid) else { return nil }
        let bytes = withUnsafeBytes(of: info.pbi_comm) { raw in
            raw.prefix { $0 != 0 }
        }
        guard !bytes.isEmpty else { return nil }
        return String(decoding: bytes, as: UTF8.self)
    }

    /// True when the process has a controlling terminal (`e_tdev`).
    /// Detached daemons report 0 or `UInt32.max` (D30).
    static func hasControllingTerminal(of pid: Int32) -> Bool {
        guard let info = bsdInfo(of: pid) else { return false }
        return info.e_tdev != 0 && info.e_tdev != UInt32.max
    }

    /// PIDs whose executable lives in an `.app` bundle whose
    /// `CFBundleIdentifier` equals `bundleID`. Unlike `instances(of:)` this
    /// also finds helper apps LaunchServices does not register — for example
    /// Orca's terminal host, a bare LSUIElement bundle under
    /// `~/Library/Application Support` (D30). Scans the full process table and
    /// caches identifiers per bundle path, so repeated reconcile passes are
    /// cheap.
    static func processes(bundleID: String) -> [Int32] {
        guard !bundleID.isEmpty else { return [] }
        var matches: [Int32] = []
        for pid in allPIDs() {
            guard let executable = path(of: pid),
                  let bundlePath = enclosingBundlePath(ofExecutableAt: executable),
                  bundleIdentifier(atBundlePath: bundlePath) == bundleID else { continue }
            matches.append(pid)
        }
        return matches
    }

    /// Nearest enclosing `.app` directory of an executable path, or nil for a
    /// loose binary such as `/usr/bin/login`.
    static func enclosingBundlePath(ofExecutableAt path: String) -> String? {
        guard !path.isEmpty else { return nil }
        var url = URL(fileURLWithPath: path)
        while url.path != "/", url.path != "." {
            url.deleteLastPathComponent()
            if url.pathExtension == "app" { return url.path }
        }
        return nil
    }

    // MARK: - Private helpers

    /// Identifier cache for `processes(bundleID:)`, keyed by `.app` path.
    /// App updates move the path, so entries never go stale; the cap only
    /// bounds memory on a long-running agent.
    private static var bundleIDCache: [String: String] = [:]
    private static let bundleIDCacheLock = NSLock()

    /// Reads `CFBundleIdentifier` from `<bundle>/Contents/Info.plist` once per
    /// bundle path. An empty string caches the negative result: a directory
    /// that looks like a bundle but has no identifier is not re-read every pass.
    private static func bundleIdentifier(atBundlePath path: String) -> String? {
        bundleIDCacheLock.lock()
        if let cached = bundleIDCache[path] {
            bundleIDCacheLock.unlock()
            return cached.isEmpty ? nil : cached
        }
        bundleIDCacheLock.unlock()

        let infoPath = (path as NSString).appendingPathComponent("Contents/Info.plist")
        let identifier = NSDictionary(contentsOfFile: infoPath)?["CFBundleIdentifier"] as? String

        bundleIDCacheLock.lock()
        if bundleIDCache.count >= 512 { bundleIDCache.removeAll(keepingCapacity: true) }
        bundleIDCache[path] = identifier ?? ""
        bundleIDCacheLock.unlock()
        return identifier
    }

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
