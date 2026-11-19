//
//  DNSProxy.swift
//  NoHallaDomainGuard
//
//  Loopback DNS proxy (D47). Blocked suffixes get NXDOMAIN; everything else is
//  forwarded byte-for-byte to the saved upstream servers. Never listens beyond
//  127.0.0.1 and never caches.
//

import Foundation
import Network
import os

final class DNSProxy {
    enum ProxyError: Error {
        case invalidPort
        case bindFailed(String)
    }

    private let port: UInt16
    private let upstreamPort: UInt16
    private let queue = DispatchQueue(label: "dev.nohalla.NoHalla.dns-proxy")
    private let logger = Logger(subsystem: "dev.nohalla.NoHalla", category: "dns-proxy")
    private var suffixes: [String]
    private var upstreams: [String]
    private var udpListener: NWListener?
    private var tcpListener: NWListener?

    init(port: UInt16, upstreamPort: UInt16 = 53, suffixes: [String], upstreams: [String]) {
        self.port = port
        self.upstreamPort = upstreamPort
        self.suffixes = suffixes
        self.upstreams = upstreams
    }

    func start() throws {
        guard let localPort = NWEndpoint.Port(rawValue: port) else { throw ProxyError.invalidPort }

        let udpParameters = NWParameters.udp
        udpParameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: localPort)
        let tcpParameters = NWParameters.tcp
        tcpParameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: localPort)

        let udp = try NWListener(using: udpParameters)
        let tcp: NWListener
        do {
            tcp = try NWListener(using: tcpParameters)
        } catch {
            udp.cancel()
            throw ProxyError.bindFailed(String(describing: error))
        }

        let udpWaiter = ReadyWaiter()
        let tcpWaiter = ReadyWaiter()
        udp.stateUpdateHandler = { udpWaiter.record($0) }
        tcp.stateUpdateHandler = { tcpWaiter.record($0) }
        udp.newConnectionHandler = { [weak self] connection in self?.acceptUDP(connection) }
        tcp.newConnectionHandler = { [weak self] connection in self?.acceptTCP(connection) }
        udp.start(queue: queue)
        tcp.start(queue: queue)

        if let failure = udpWaiter.wait() {
            udp.cancel()
            tcp.cancel()
            throw ProxyError.bindFailed(failure)
        }
        if let failure = tcpWaiter.wait() {
            udp.cancel()
            tcp.cancel()
            throw ProxyError.bindFailed(failure)
        }
        udpListener = udp
        tcpListener = tcp
        logger.notice("DNS proxy listening on 127.0.0.1:\(self.port, privacy: .public)")
    }

    func update(suffixes: [String], upstreams: [String]) {
        queue.sync {
            self.suffixes = suffixes
            self.upstreams = upstreams
        }
    }

    func stop() {
        queue.sync {
            udpListener?.cancel()
            tcpListener?.cancel()
            udpListener = nil
            tcpListener = nil
        }
    }

    // MARK: - Clients

    private func acceptUDP(_ connection: NWConnection) {
        connection.start(queue: queue)
        receiveUDP(connection)
    }

    private func receiveUDP(_ connection: NWConnection) {
        connection.receiveMessage { [weak self] data, _, isComplete, error in
            guard let self else { return }
            if let data, !data.isEmpty {
                self.respond(to: data) { response in
                    if let response {
                        connection.send(content: response, completion: .contentProcessed { _ in })
                    }
                }
                self.receiveUDP(connection)
                return
            }
            if error != nil || isComplete {
                connection.cancel()
                return
            }
            self.receiveUDP(connection)
        }
    }

    private func acceptTCP(_ connection: NWConnection) {
        connection.start(queue: queue)
        receiveTCP(connection, buffer: Data())
    }

    private func receiveTCP(_ connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: DNSMessage.maxPacket) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            var pending = buffer
            if let data { pending.append(data) }

            while pending.count >= 2 {
                let length = (Int(pending[pending.startIndex]) << 8) | Int(pending[pending.startIndex + 1])
                guard length > 0, length <= DNSMessage.maxPacket else {
                    connection.cancel()
                    return
                }
                guard pending.count >= 2 + length else { break }
                let query = pending.subdata(in: 2..<(2 + length))
                pending.removeFirst(2 + length)
                self.respond(to: query) { response in
                    guard let response else { return }
                    var framed = Data([UInt8(response.count >> 8), UInt8(response.count & 0xFF)])
                    framed.append(response)
                    connection.send(content: framed, completion: .contentProcessed { _ in })
                }
            }

            if isComplete || error != nil {
                connection.cancel()
                return
            }
            self.receiveTCP(connection, buffer: pending)
        }
    }

    // MARK: - Resolution

    private func respond(to query: Data, completion: @escaping (Data?) -> Void) {
        guard let question = DNSMessage.questionName(query) else {
            completion(nil)
            return
        }
        let blocked = suffixes.contains {
            question.name == $0 || question.name.hasSuffix("." + $0)
        }
        if blocked {
            completion(DNSMessage.nxdomain(for: query))
            return
        }
        forward(query, index: 0, completion: completion)
    }

    private func forward(_ query: Data, index: Int, completion: @escaping (Data?) -> Void) {
        guard index < upstreams.count,
              let port = NWEndpoint.Port(rawValue: upstreamPort) else {
            completion(DNSMessage.servfail(for: query))
            return
        }
        let connection = NWConnection(host: NWEndpoint.Host(upstreams[index]), port: port, using: .udp)
        let once = CompletionOnce()
        let finish: (Data?) -> Void = { [weak self] answer in
            once.run {
                connection.cancel()
                if let answer, !answer.isEmpty {
                    completion(answer)
                } else {
                    self?.forward(query, index: index + 1, completion: completion)
                }
            }
        }
        connection.stateUpdateHandler = { state in
            switch state {
            case .ready:
                connection.send(content: query, completion: .contentProcessed { _ in })
            case .failed, .cancelled:
                finish(nil)
            default:
                break
            }
        }
        connection.receiveMessage { data, _, _, _ in
            finish(data)
        }
        connection.start(queue: queue)
        queue.asyncAfter(deadline: .now() + 2) { finish(nil) }
    }
}

/// Signals at most once; all callers run on the listener queue.
private final class CompletionOnce {
    private var done = false

    func run(_ body: () -> Void) {
        guard !done else { return }
        done = true
        body()
    }
}

/// Collects the first ready/failed state without racing the caller.
private final class ReadyWaiter {
    private let lock = NSLock()
    private let semaphore = DispatchSemaphore(value: 0)
    private var failure: String?

    func record(_ state: NWListener.State) {
        switch state {
        case .ready:
            semaphore.signal()
        case .failed(let error):
            lock.lock()
            failure = String(describing: error)
            lock.unlock()
            semaphore.signal()
        default:
            break
        }
    }

    /// nil on ready; an explanation on failure or timeout.
    func wait() -> String? {
        guard semaphore.wait(timeout: .now() + 2) == .success else {
            return "listener did not become ready"
        }
        lock.lock()
        defer { lock.unlock() }
        return failure
    }
}