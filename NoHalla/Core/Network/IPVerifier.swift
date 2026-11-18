//
//  IPVerifier.swift
//  NoHalla
//
//  Public-IP verification (implementation brief §8.2, FR-8/9/13, NFR-8).
//  Each address family is checked in parallel across its HTTPS endpoints; a
//  family is `verified` only when at least `quorum` endpoints agree on the same
//  valid IP of that family. Disagreement or too few answers yields `noQuorum`.
//  IPv6 is skipped (`notApplicable`) when disabled or when there is no IPv6
//  egress. Offline produces `noQuorum` without any request. Batches are
//  throttled to one per 3 s and backed off 5→60 s while endpoints keep failing.
//  Only HTTPS is used and cross-host redirects are blocked. Logs mask IPs
//  (FR-39).
//
//  R4: each branch is queried over its own address family. The hostname is
//  resolved with getaddrinfo restricted to AF_INET/AF_INET6 and the request
//  targets that numeric address (Host header keeps the original name; TLS trust
//  is evaluated against it). Answers of the wrong family are discarded before
//  quorum, so a dual-stack endpoint reached over IPv6 can never masquerade as
//  the IPv4 verdict.
//

import Darwin
import Foundation
import OSLog
import Security

/// Per-family verification outcome.
enum FamilyResult {
    case verified(IPAddress)
    case noQuorum
    case notApplicable
}

/// Combined verification result. `currentIPv4`/`currentIPv6` carry the first
/// valid answer of each family (for the UI and "Add current IP") even when the
/// family did not reach quorum.
struct IPVerificationResult {
    let ipv4: FamilyResult
    let ipv6: FamilyResult
    let currentIPv4: IPAddress?
    let currentIPv6: IPAddress?
}

/// Session delegate: blocks cross-host redirects (NFR-8) and evaluates TLS
/// trust against the original hostname when we connect via a numeric IP literal
/// to force the address family (R4).
private final class IPCheckSessionDelegate: NSObject, URLSessionTaskDelegate {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        let originalHost = task.originalRequest?.value(forHTTPHeaderField: "Host")
            ?? task.originalRequest?.url?.host
        let newHost = request.url?.host
        if originalHost?.lowercased() == newHost?.lowercased() {
            completionHandler(request)
        } else {
            AppLog.network.debug("Blocked cross-host redirect for IP check")
            completionHandler(nil)
        }
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let serverTrust = challenge.protectionSpace.serverTrust else {
            completionHandler(.performDefaultHandling, nil)
            return
        }
        let host = task.originalRequest?.value(forHTTPHeaderField: "Host")
            ?? challenge.protectionSpace.host
        let policy = SecPolicyCreateSSL(true, host as CFString)
        SecTrustSetPolicies(serverTrust, policy)
        var error: CFError?
        if SecTrustEvaluateWithError(serverTrust, &error) {
            completionHandler(.useCredential, URLCredential(trust: serverTrust))
        } else {
            AppLog.network.debug("IP check TLS trust failed for \(host, privacy: .public)")
            completionHandler(.cancelAuthenticationChallenge, nil)
        }
    }
}

/// Actor-isolated IP verifier: at most one batch in flight, throttle + backoff.
actor IPVerifier {
    private let session: URLSession
    private var inFlight = false
    private var lastBatchStart: Date?
    private var backoffSeconds: Double = 5
    private var backoffUntil: Date?

    private let minimumBatchInterval: TimeInterval = 3
    private let maximumBackoff: Double = 60
    private let initialBackoff: Double = 5

    init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 2.5
        configuration.timeoutIntervalForResource = 4
        configuration.waitsForConnectivity = false
        self.session = URLSession(configuration: configuration, delegate: IPCheckSessionDelegate(), delegateQueue: nil)
    }

    /// Runs one verification batch, or returns nil when throttled/backed off so
    /// the engine keeps its current state. Offline returns `noQuorum` without
    /// sending requests (FR-11).
    func check(config: AppConfig, online: Bool) async -> IPVerificationResult? {
        let now = Date()
        guard !inFlight else { return nil }
        if let backoffUntil = backoffUntil, now < backoffUntil { return nil }
        if let lastBatchStart = lastBatchStart, now.timeIntervalSince(lastBatchStart) < minimumBatchInterval {
            return nil
        }

        let checkIPv6 = config.protection.checkIPv6

        if !online {
            // No network path: unknown without any request (FR-11).
            let ipv6: FamilyResult = checkIPv6 ? .noQuorum : .notApplicable
            return IPVerificationResult(ipv4: .noQuorum, ipv6: ipv6, currentIPv4: nil, currentIPv6: nil)
        }

        inFlight = true
        lastBatchStart = now
        defer { inFlight = false }

        let quorum = max(1, config.ipCheck.quorum)
        let timeout = config.ipCheck.timeoutSeconds > 0 ? config.ipCheck.timeoutSeconds : 2.5

        async let ipv4 = verifyFamily(endpoints: config.ipCheck.endpointsV4, family: .v4, quorum: quorum, timeout: timeout)
        async let ipv6 = verifyIPv6(config: config, quorum: quorum, timeout: timeout)
        let (v4Result, v4Address) = await ipv4
        let (v6Result, v6Address) = await ipv6

        applyBackoff(v4Address: v4Address, v6Address: v6Address, v6Result: v6Result)

        return IPVerificationResult(ipv4: v4Result, ipv6: v6Result, currentIPv4: v4Address, currentIPv6: v6Address)
    }

    // MARK: - Families

    private func verifyIPv6(config: AppConfig, quorum: Int, timeout: Double) async -> (FamilyResult, IPAddress?) {
        guard config.protection.checkIPv6 else { return (.notApplicable, nil) }
        guard hasIPv6Egress() else {
            AppLog.network.debug("IPv6 enabled but no egress; marking notApplicable")
            return (.notApplicable, nil)
        }
        return await verifyFamily(endpoints: config.ipCheck.endpointsV6, family: .v6, quorum: quorum, timeout: timeout)
    }

    private func verifyFamily(endpoints: [String], family: IPFamily, quorum: Int, timeout: Double) async -> (FamilyResult, IPAddress?) {
        let httpsEndpoints = endpoints.filter { endpoint in
            guard let url = URL(string: endpoint) else { return false }
            return url.scheme?.lowercased() == "https"
        }
        guard !httpsEndpoints.isEmpty else { return (.noQuorum, nil) }

        let answers: [IPAddress] = await withTaskGroup(of: IPAddress?.self) { group in
            for endpoint in httpsEndpoints {
                group.addTask { await self.fetchIP(from: endpoint, family: family, timeout: timeout) }
            }
            var collected: [IPAddress] = []
            for await answer in group {
                if let answer = answer { collected.append(answer) }
            }
            return collected
        }

        // R4: only answers of the expected family count toward quorum.
        let matching = answers.filter { $0.family == family }
        let first = matching.first
        guard matching.count >= quorum, let reference = matching.first else {
            return (.noQuorum, first)
        }
        // Quorum reached: any disagreement between successful answers is unknown
        // (split tunnel / anycast), per brief §8.2.
        let agrees = matching.allSatisfy { $0 == reference }
        return agrees ? (.verified(reference), first) : (.noQuorum, first)
    }

    private func fetchIP(from endpoint: String, family: IPFamily, timeout: Double) async -> IPAddress? {
        guard let url = URL(string: endpoint),
              url.scheme?.lowercased() == "https",
              let host = url.host else { return nil }

        // Force the address family by connecting to a numeric address resolved
        // for that family (R4). Keep the original hostname in the Host header.
        guard let numericHost = resolveAddress(host: host, family: family) else { return nil }
        let hostPart = family == .v6 ? "[\(numericHost)]" : numericHost
        let queryPart = url.query.map { "?\($0)" } ?? ""
        guard let targetURL = URL(string: "https://\(hostPart)\(url.path)\(queryPart)") else { return nil }

        var request = URLRequest(url: targetURL)
        request.httpMethod = "GET"
        request.timeoutInterval = timeout
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue(host, forHTTPHeaderField: "Host")

        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                return nil
            }
            guard let text = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else {
                return nil
            }
            // Plain-text IP first, then a JSON object with an `ip` field.
            if let address = IPAddress(text), address.family == family {
                AppLog.network.debug("IP check \(host, privacy: .public) -> \(address.masked, privacy: .public)")
                return address
            }
            if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let ipString = object["ip"] as? String,
               let address = IPAddress(ipString.trimmingCharacters(in: .whitespacesAndNewlines)),
               address.family == family {
                AppLog.network.debug("IP check \(host, privacy: .public) -> \(address.masked, privacy: .public)")
                return address
            }
            return nil
        } catch {
            AppLog.network.debug("IP check \(host, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    // MARK: - DNS resolution restricted to a family

    /// Resolves a hostname to the first numeric address of the requested family
    /// using getaddrinfo (AF_INET or AF_INET6), forcing the verification stack.
    private func resolveAddress(host: String, family: IPFamily) -> String? {
        var hints = addrinfo()
        hints.ai_family = family == .v4 ? AF_INET : AF_INET6
        hints.ai_socktype = SOCK_STREAM
        var result: UnsafeMutablePointer<addrinfo>?
        guard getaddrinfo(host, nil, &hints, &result) == 0, let head = result else { return nil }
        defer { freeaddrinfo(head) }

        var cursor: UnsafeMutablePointer<addrinfo>? = head
        while let current = cursor {
            let entry = current.pointee
            cursor = entry.ai_next
            guard let addr = entry.ai_addr else { continue }
            let buffer = UnsafeMutablePointer<CChar>.allocate(capacity: Int(INET6_ADDRSTRLEN))
            defer { buffer.deallocate() }
            var rendered: UnsafePointer<CChar>?
            if entry.ai_family == AF_INET {
                addr.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { sa in
                    rendered = inet_ntop(AF_INET, &sa.pointee.sin_addr, buffer, socklen_t(INET_ADDRSTRLEN))
                }
            } else if entry.ai_family == AF_INET6 {
                addr.withMemoryRebound(to: sockaddr_in6.self, capacity: 1) { sa in
                    rendered = inet_ntop(AF_INET6, &sa.pointee.sin6_addr, buffer, socklen_t(INET6_ADDRSTRLEN))
                }
            }
            if rendered != nil { return String(cString: buffer) }
        }
        return nil
    }

    // MARK: - IPv6 egress probe

    /// A UDP `connect` to a public IPv6 address checks routing without sending
    /// a packet; success means an IPv6 egress path exists.
    private func hasIPv6Egress() -> Bool {
        let sock = socket(AF_INET6, SOCK_DGRAM, IPPROTO_UDP)
        guard sock >= 0 else { return false }
        defer { close(sock) }

        var address = sockaddr_in6()
        address.sin6_len = UInt8(MemoryLayout<sockaddr_in6>.stride)
        address.sin6_family = sa_family_t(AF_INET6)
        address.sin6_port = UInt16(53).bigEndian
        guard inet_pton(AF_INET6, "2001:4860:4860::8888", &address.sin6_addr) == 1 else { return false }

        let result = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPointer in
                connect(sock, sockaddrPointer, socklen_t(MemoryLayout<sockaddr_in6>.stride))
            }
        }
        return result == 0
    }

    // MARK: - Backoff

    /// Grow backoff while no endpoint answered at all; reset on any success.
    /// R13: measure the pause from batch completion, not from the pre-batch
    /// timestamp, so timeouts do not shorten the declared backoff.
    private func applyBackoff(v4Address: IPAddress?, v6Address: IPAddress?, v6Result: FamilyResult) {
        let v6Applicable: Bool
        if case .notApplicable = v6Result { v6Applicable = false } else { v6Applicable = true }
        let anyAnswer = v4Address != nil || (v6Applicable && v6Address != nil)
        let completed = Date()

        if anyAnswer {
            backoffSeconds = initialBackoff
            backoffUntil = nil
        } else {
            backoffUntil = completed.addingTimeInterval(backoffSeconds)
            backoffSeconds = min(backoffSeconds * 2, maximumBackoff)
            AppLog.network.debug("IP check backoff \(self.backoffSeconds, privacy: .public)s")
        }
    }
}