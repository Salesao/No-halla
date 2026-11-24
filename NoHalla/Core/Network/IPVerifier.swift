//
//  IPVerifier.swift
//  NoHalla
//
//  Public-IPv4 verification (implementation brief §8.2, FR-8/9/13, NFR-8;
//  owner decision: IPv6 checks removed, tunnel-routed main endpoint).
//  Every configured main HTTPS endpoint is queried in parallel and ALL valid
//  answers are kept: a split-tunnel host may legitimately expose several
//  public addresses, and the engine checks each observed address against the
//  trusted list (all trusted → allowed, any untrusted → disallowed). Only when
//  no main endpoint answers are the fallback endpoints queried, again in
//  parallel with all valid answers kept. Zero answers in both groups yields
//  `noQuorum`. Offline produces `noQuorum` without any request. Batches are
//  throttled to one per 3 s and backed off 5→60 s while endpoints keep failing.
//  Only HTTPS is used and cross-host redirects are blocked. Logs mask IPs.
//
//  Requests keep the endpoint hostname in the URL so URLSession performs
//  normal SNI and certificate name validation. `IPAddress` parses IPv4 only,
//  so an IPv6 answer from a dual-stack endpoint is discarded before it can
//  influence the verdict. Forcing the transport family via a numeric IP
//  literal was rejected because it breaks SNI/name validation (see project
//  memory).
//

import Foundation
import OSLog

/// Verification outcome for the IPv4 check.
enum FamilyResult {
    /// One or more valid IPv4 answers.
    case answers([IPAddress])
    case noQuorum

    /// Verified addresses, empty unless at least one endpoint answered.
    var verifiedAddresses: [IPAddress] {
        if case .answers(let addresses) = self { return addresses }
        return []
    }
}

/// Verification result. `currentIPv4` carries the first valid answer (for the
/// UI and "Add current IP") even when no endpoint answered — then it is nil.
struct IPVerificationResult {
    let ipv4: FamilyResult
    let currentIPv4: IPAddress?

    /// All observed IPv4 answers.
    var allIPv4: [IPAddress] { ipv4.verifiedAddresses }
}

/// Session delegate: blocks cross-host and non-HTTPS redirects (NFR-8, R27).
/// TLS server-trust validation uses URLSession's default handling against the
/// endpoint hostname (SNI and name check stay intact).
private final class IPCheckSessionDelegate: NSObject, URLSessionTaskDelegate {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        let originalHost = task.originalRequest?.url?.host?.lowercased()
        let newHost = request.url?.host?.lowercased()
        let isHTTPS = request.url?.scheme?.lowercased() == "https"
        if isHTTPS && originalHost == newHost {
            completionHandler(request)
        } else {
            AppLog.network.debug("Blocked cross-host or non-HTTPS redirect for IP check")
            completionHandler(nil)
        }
    }
}

/// Actor-isolated IP verifier: at most one batch in flight, throttle + backoff.
actor IPVerifier {
    private let session: URLSession
    private var inFlight = false
    /// Wall-clock start of the in-flight batch; its result is ignored once the
    /// batch is declared stale after sleep.
    private var inFlightSince: Date?
    private var inFlightBatchTimeout: TimeInterval = 4
    /// Set on wake; one new batch is permitted once the old one exceeds its
    /// timeout plus a margin. The stale batch's late completion never lands.
    private var wakeRecoveryPending = false
    private var activeBatchToken = 0
    private var lastBatchStart: Date?
    private var backoffSeconds: Double = 5
    private var backoffUntil: Date?

    private let minimumBatchInterval: TimeInterval = 3
    private let maximumBackoff: Double = 60
    private let initialBackoff: Double = 5
    /// Slack on top of the batch timeout before a post-wake batch is stale.
    private let staleBatchMargin: TimeInterval = 2
    /// Hard ceiling on any single batch, independent of the configured timeout
    /// (per-request timeout plus URLSession's resource timeout).
    private static let maximumBatchTimeout: TimeInterval = 30

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
    func check(config: AppConfig, online: Bool, force: Bool = false) async -> IPVerificationResult? {
        let now = Date()
        if inFlight {
            // Sleep recovery (FR-12/44): a batch stuck across sleep must not
            // block the first post-wake check beyond its own timeout + margin.
            // Permit exactly one new batch; the stale one's completion is
            // discarded by its token, so batches never overlap semantically.
            guard wakeRecoveryPending,
                  let since = inFlightSince,
                  now.timeIntervalSince(since) > inFlightBatchTimeout + staleBatchMargin else { return nil }
            wakeRecoveryPending = false
            AppLog.network.info("Discarding stale pre-sleep IP batch; starting a new one")
        }
        // A user-initiated detection ignores the periodic throttle and the
        // failure backoff (D35): onboarding must not wait up to 60 s.
        if !force {
            if let backoffUntil = backoffUntil, now < backoffUntil { return nil }
            if let lastBatchStart = lastBatchStart, now.timeIntervalSince(lastBatchStart) < minimumBatchInterval {
                return nil
            }
        }

        if !online {
            // No network path: unknown without any request (FR-11).
            return IPVerificationResult(ipv4: .noQuorum, currentIPv4: nil)
        }

        let timeout = config.ipCheck.timeoutSeconds > 0 ? config.ipCheck.timeoutSeconds : 2.5
        activeBatchToken += 1
        let token = activeBatchToken
        inFlight = true
        inFlightSince = now
        // URLSession clamps per-request timeouts to its own resource timeout;
        // bound the stale check by the same ceiling regardless of config.
        inFlightBatchTimeout = min(max(timeout, 2.5) + 4, Self.maximumBatchTimeout)
        lastBatchStart = now

        let (mainResult, mainAddress) = await verify(endpoints: config.ipCheck.endpointsV4, timeout: timeout)
        var result = mainResult
        var address = mainAddress
        if mainResult.verifiedAddresses.isEmpty, !config.ipCheck.fallbackEndpointsV4.isEmpty {
            let (fallbackResult, fallbackAddress) = await verify(
                endpoints: config.ipCheck.fallbackEndpointsV4,
                timeout: timeout
            )
            if !fallbackResult.verifiedAddresses.isEmpty {
                result = fallbackResult
                address = fallbackAddress
            }
        }

        // Only the newest batch may land: a stale pre-sleep batch must not
        // release the in-flight slot of the recovery batch nor feed backoff.
        guard token == activeBatchToken else { return nil }
        inFlight = false
        inFlightSince = nil
        applyBackoff(address: address)

        return IPVerificationResult(ipv4: result, currentIPv4: address)
    }

    /// Called by the engine on wake (FR-12): the next check may abandon a
    /// batch that was in flight across sleep once it outlives its timeout.
    /// Throttle and backoff are untouched.
    func noteWake() {
        wakeRecoveryPending = true
    }

    // MARK: - Verification

    private func verify(endpoints: [String], timeout: Double) async -> (FamilyResult, IPAddress?) {
        let httpsEndpoints = endpoints.filter { endpoint in
            guard let url = URL(string: endpoint) else { return false }
            return url.scheme?.lowercased() == "https"
        }
        guard !httpsEndpoints.isEmpty else { return (.noQuorum, nil) }

        let answers: [IPAddress] = await withTaskGroup(of: IPAddress?.self) { group in
            for endpoint in httpsEndpoints {
                group.addTask { await self.fetchIP(from: endpoint, timeout: timeout) }
            }
            var collected: [IPAddress] = []
            for await answer in group {
                if let answer = answer { collected.append(answer) }
            }
            return collected
        }

        guard let first = answers.first else { return (.noQuorum, nil) }
        // Split-tunnel hosts legitimately expose several public addresses.
        // Keep every observed answer so the engine can require ALL of them to
        // be trusted; disagreement alone says nothing about trust.
        return (.answers(answers), first)
    }

    private func fetchIP(from endpoint: String, timeout: Double) async -> IPAddress? {
        // Keep the hostname in the URL: URLSession performs normal SNI and
        // certificate name validation. Only IPv4 answers are accepted below.
        guard let url = URL(string: endpoint), url.scheme?.lowercased() == "https" else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = timeout
        request.cachePolicy = .reloadIgnoringLocalCacheData

        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                return nil
            }
            guard let text = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else {
                return nil
            }
            let host = url.host ?? ""
            // Plain-text IP first, then a JSON object with an `ip` field.
            if let address = IPAddress(text) {
                AppLog.network.debug("IP check \(host, privacy: .public) -> \(address.masked, privacy: .public)")
                return address
            }
            if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let ipString = object["ip"] as? String,
               let address = IPAddress(ipString.trimmingCharacters(in: .whitespacesAndNewlines)) {
                AppLog.network.debug("IP check \(host, privacy: .public) -> \(address.masked, privacy: .public)")
                return address
            }
            return nil
        } catch {
            AppLog.network.debug("IP check \(url.host ?? "", privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    // MARK: - Backoff

    /// Grow backoff while no endpoint answered at all; reset on any success.
    /// R13: measure the pause from batch completion, not from the pre-batch
    /// timestamp, so timeouts do not shorten the declared backoff.
    private func applyBackoff(address: IPAddress?) {
        let completed = Date()
        if address != nil {
            backoffSeconds = initialBackoff
            backoffUntil = nil
        } else {
            backoffUntil = completed.addingTimeInterval(backoffSeconds)
            backoffSeconds = min(backoffSeconds * 2, maximumBackoff)
            AppLog.network.debug("IP check backoff \(self.backoffSeconds, privacy: .public)s")
        }
    }
}
