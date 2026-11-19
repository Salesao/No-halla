//
//  NetworkMonitor.swift
//  NoHalla
//
//  Watches for network changes (implementation brief §8.1, FR-7/12/14):
//  NWPathMonitor for path changes, SCDynamicStore notifications for IP/route
//  configuration changes, and NSWorkspace.didWakeNotification for wake from
//  sleep. Every source feeds a single debounce window (default 500 ms) that
//  collapses a burst of events into one `onEvent` callback. The periodic check
//  timer lives in the engine, not here; whether checks may run while asleep is
//  also the engine's decision. `stop()` releases all sources and the monitor
//  can be started again afterwards.
//

import AppKit
import Darwin
import Foundation
import Network
import SystemConfiguration

/// Debounced observer of network path, IP/route configuration and wake events.
///
/// Thread safety: all event sources deliver onto a private serial queue, and
/// debounce scheduling happens only on that queue. Published state (`isOnline`,
/// `onEvent`) is guarded by a lock, so it can be read or replaced from any
/// thread, including from inside `onEvent` itself.
final class NetworkMonitor {
    /// Called once per debounce window when the network changed or the machine
    /// woke from sleep. Invoked on the monitor's private serial queue; hop to
    /// another queue if needed. Reading or replacing it is thread-safe.
    var onEvent: (() -> Void)? {
        get {
            lock.lock()
            defer { lock.unlock() }
            return eventHandler
        }
        set {
            lock.lock()
            defer { lock.unlock() }
            eventHandler = newValue
        }
    }

    /// Whether the latest NWPathMonitor path is `.satisfied`. Seeded from the
    /// current path at `start()` and refined by the first path update.
    var isOnline: Bool {
        lock.lock()
        defer { lock.unlock() }
        return online
    }

    private let debounceInterval: TimeInterval
    private let queue = DispatchQueue(label: "dev.nohalla.NoHalla.network-monitor")
    private let lock = NSLock()

    private var eventHandler: (() -> Void)?
    private var online = false
    private var running = false
    private var debounceWorkItem: DispatchWorkItem?
    private var pathMonitor: NWPathMonitor?
    private var dynamicStore: SCDynamicStore?
    private var wakeObserver: NSObjectProtocol?

    init(debounce: TimeInterval = 0.5) {
        self.debounceInterval = max(0, debounce)
    }

    deinit {
        stop()
    }

    // MARK: - Lifecycle

    /// Starts all event sources. Idempotent while already running.
    func start() {
        lock.lock()
        defer { lock.unlock() }
        guard !running else { return }
        running = true

        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { [weak self] path in
            self?.handlePathUpdate(path)
        }
        pathMonitor = monitor
        online = monitor.currentPath.status == .satisfied
        monitor.start(queue: queue)

        dynamicStore = makeDynamicStore()

        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: nil
        ) { [weak self] _ in
            // Wake goes through the same debounce window as network events;
            // the engine performs the immediate post-wake check (FR-12).
            self?.queue.async { self?.scheduleEvent() }
        }
    }

    /// Stops all event sources, cancels any pending debounce and releases the
    /// dynamic store and wake observer. Idempotent; `start()` may follow.
    func stop() {
        lock.lock()
        guard running else {
            lock.unlock()
            return
        }
        running = false
        debounceWorkItem?.cancel()
        debounceWorkItem = nil
        let monitor = pathMonitor
        pathMonitor = nil
        let store = dynamicStore
        dynamicStore = nil
        let observer = wakeObserver
        wakeObserver = nil
        lock.unlock()

        // Tear down outside the lock: none of these calls may block on the
        // serial queue, whose handlers briefly take the same lock.
        monitor?.pathUpdateHandler = nil
        monitor?.cancel()
        if let store = store {
            // Removing the dispatch queue stops callbacks; releasing the store
            // (ARC) invalidates it. SCDynamicStoreInvalidate is not public API.
            SCDynamicStoreSetDispatchQueue(store, nil)
        }
        if let observer = observer {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
    }

    // MARK: - VPN interface detection (FR-14)

    /// Name of the first VPN-like interface (`utun*`, `ipsec*`, `ppp*`, `tun*`)
    /// that has an assigned IPv4/IPv6 address, or nil when none exists.
    /// Uses getifaddrs; safe to call from any thread.
    func vpnInterfaceName() -> String? {
        var interfaces: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&interfaces) == 0, let head = interfaces else { return nil }
        defer { freeifaddrs(head) }

        var cursor: UnsafeMutablePointer<ifaddrs>? = head
        while let current = cursor {
            let entry = current.pointee
            cursor = entry.ifa_next
            guard let address = entry.ifa_addr, let rawName = entry.ifa_name else { continue }
            let family = Int32(address.pointee.sa_family)
            // An assigned address means IPv4/IPv6, not a link-layer entry.
            guard family == AF_INET || family == AF_INET6 else { continue }
            let name = String(cString: rawName)
            if name.hasPrefix("utun") || name.hasPrefix("ipsec")
                || name.hasPrefix("ppp") || name.hasPrefix("tun") {
                return name
            }
        }
        return nil
    }

    /// Name of the active VPN tunnel interface, or nil when the VPN is down.
    /// Unlike `vpnInterfaceName`, this requires a GLOBAL address on a
    /// utun/ipsec/ppp/tun interface — excluding loopback (127.x / ::1) and
    /// link-local (169.254.x / fe80::) — so system tunnels that only carry a
    /// link-local address (e.g. iCloud Private Relay) are not mistaken for the
    /// user's VPN. Used by the VPN-tunnel protection mode (no external query).
    func activeVPNInterface() -> String? {
        var interfaces: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&interfaces) == 0, let head = interfaces else { return nil }
        defer { freeifaddrs(head) }

        var cursor: UnsafeMutablePointer<ifaddrs>? = head
        while let current = cursor {
            let entry = current.pointee
            cursor = entry.ifa_next
            guard let address = entry.ifa_addr, let rawName = entry.ifa_name else { continue }
            let name = String(cString: rawName)
            guard name.hasPrefix("utun") || name.hasPrefix("ipsec")
                || name.hasPrefix("ppp") || name.hasPrefix("tun") else { continue }
            let family = Int32(address.pointee.sa_family)
            if family == AF_INET {
                let octets = address.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { pointer -> [UInt8] in
                    let raw = pointer.pointee.sin_addr.s_addr // network byte order
                    return [UInt8(raw & 0xff), UInt8((raw >> 8) & 0xff), UInt8((raw >> 16) & 0xff), UInt8((raw >> 24) & 0xff)]
                }
                let isLoopback = octets[0] == 127
                let isLinkLocal = octets[0] == 169 && octets[1] == 254
                if !isLoopback && !isLinkLocal { return name }
            } else if family == AF_INET6 {
                let bytes = address.withMemoryRebound(to: sockaddr_in6.self, capacity: 1) { pointer in
                    withUnsafeBytes(of: pointer.pointee.sin6_addr) { Array($0) }
                }
                let isLinkLocal = bytes[0] == 0xfe && (bytes[1] & 0xc0) == 0x80
                let isLoopback = bytes[0..<15].allSatisfy { $0 == 0 } && bytes[15] == 1
                let isUnspecified = bytes.allSatisfy { $0 == 0 }
                if !isLinkLocal && !isLoopback && !isUnspecified { return name }
            }
        }
        return nil
    }

    // MARK: - Event handling (serial queue)

    private func handlePathUpdate(_ path: NWPath) {
        lock.lock()
        online = path.status == .satisfied
        lock.unlock()
        scheduleEvent()
    }

    /// Restarts the debounce window; must run on `queue`. A burst of events
    /// within the window produces exactly one `onEvent` after the last one.
    private func scheduleEvent() {
        lock.lock()
        guard running else {
            lock.unlock()
            return
        }
        debounceWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            self?.fireEvent()
        }
        debounceWorkItem = item
        lock.unlock()
        queue.asyncAfter(deadline: .now() + debounceInterval, execute: item)
    }

    private func fireEvent() {
        lock.lock()
        guard running else {
            lock.unlock()
            return
        }
        debounceWorkItem = nil
        let handler = eventHandler
        lock.unlock()
        // Invoke outside the lock so the handler may call back into the
        // monitor (isOnline, onEvent, stop) without deadlocking.
        handler?()
    }

    // MARK: - SCDynamicStore

    /// Creates the dynamic store watching global and per-interface/service
    /// IP/DNS/link keys (route changes surface via the global IPv4/IPv6 keys).
    /// Caller holds `lock`.
    private func makeDynamicStore() -> SCDynamicStore? {
        var context = SCDynamicStoreContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )
        // A non-capturing closure literal converts to the C callout pointer.
        guard let store = SCDynamicStoreCreate(
            kCFAllocatorDefault,
            "dev.nohalla.NoHalla.network-monitor" as CFString,
            { _, _, info in
                guard let info = info else { return }
                let monitor = Unmanaged<NetworkMonitor>.fromOpaque(info).takeUnretainedValue()
                monitor.queue.async { monitor.scheduleEvent() }
            },
            &context
        ) else { return nil }

        let keys = [
            "State:/Network/Global/IPv4",
            "State:/Network/Global/IPv6",
            "State:/Network/Global/DNS"
        ] as CFArray
        let patterns = [
            "State:/Network/Interface/[^/]+/Link",
            "State:/Network/Interface/[^/]+/IPv4",
            "State:/Network/Interface/[^/]+/IPv6",
            "State:/Network/Service/[^/]+/IPv4",
            "State:/Network/Service/[^/]+/IPv6",
            "State:/Network/Service/[^/]+/DNS"
        ] as CFArray
        guard SCDynamicStoreSetNotificationKeys(store, keys, patterns),
              SCDynamicStoreSetDispatchQueue(store, queue) else {
            SCDynamicStoreSetDispatchQueue(store, nil)
            return nil
        }
        return store
    }
}
