//
//  HTTPProxy.swift
//  NoHallaDomainGuard
//
//  Loopback HTTP/HTTPS forward proxy (D48). A blocked suffix answers 403 and
//  closes; everything else is tunnelled byte-for-byte. No decryption, no cache,
//  no authentication, loopback only.
//

import Foundation
import Network
import os

final class HTTPProxy {
    enum ProxyError: Error {
        case invalidPort
        case bindFailed(String)
    }

    private struct Request {
        var method: String
        var host: String
        var port: UInt16
        var path: String?
        var isConnect: Bool
        var head: String
        var extra: Data
    }

    private let port: UInt16
    private let queue = DispatchQueue(label: "dev.nohalla.NoHalla.http-proxy")
    private let logger = Logger(subsystem: "dev.nohalla.NoHalla", category: "http-proxy")
    private var suffixes: [String]
    private var listener: NWListener?

    init(port: UInt16, suffixes: [String]) {
        self.port = port
        self.suffixes = suffixes
    }

    func start() throws {
        guard let localPort = NWEndpoint.Port(rawValue: port) else { throw ProxyError.invalidPort }
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: localPort)
        let listener = try NWListener(using: parameters)
        let waiter = ReadyWaiter()
        listener.stateUpdateHandler = { waiter.record($0) }
        listener.newConnectionHandler = { [weak self] connection in self?.accept(connection) }
        listener.start(queue: queue)
        if let failure = waiter.wait() {
            listener.cancel()
            throw ProxyError.bindFailed(failure)
        }
        self.listener = listener
        logger.notice("HTTP proxy listening on 127.0.0.1:\(self.port, privacy: .public)")
    }

    func update(suffixes: [String]) {
        queue.sync { self.suffixes = suffixes }
    }

    func stop() {
        queue.sync {
            listener?.cancel()
            listener = nil
        }
    }

    // MARK: - Connections

    private func accept(_ connection: NWConnection) {
        connection.start(queue: queue)
        readHeader(connection, buffer: Data())
    }

    private func readHeader(_ connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16_384) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            var pending = buffer
            if let data { pending.append(data) }
            if pending.count > 64 * 1024 {
                self.reject(connection, status: "431 Request Header Fields Too Large")
                return
            }
            if let range = pending.range(of: Data("\r\n\r\n".utf8)) {
                let headEnd = range.upperBound
                let head = String(decoding: pending[..<headEnd], as: UTF8.self)
                let extra = Data(pending[headEnd...])
                self.handle(connection, head: head, extra: extra)
                return
            }
            if isComplete || error != nil {
                connection.cancel()
                return
            }
            self.readHeader(connection, buffer: pending)
        }
    }

    private func handle(_ connection: NWConnection, head: String, extra: Data) {
        guard let request = parse(head: head, extra: extra) else {
            reject(connection, status: "400 Bad Request")
            return
        }
        if DomainBlocklist.isBlocked(host: request.host, suffixes: suffixes) {
            reject(connection, status: "403 Forbidden")
            return
        }
        openUpstream(host: request.host, port: request.port, client: connection) { [weak self] upstream in
            guard let self else { return }
            if request.isConnect {
                let established = "HTTP/1.1 200 Connection Established\r\n\r\n"
                connection.send(content: Data(established.utf8), completion: .contentProcessed { _ in })
                if !request.extra.isEmpty {
                    upstream.send(content: request.extra, completion: .contentProcessed { _ in })
                }
            } else {
                let lineEnd = request.head.range(of: "\r\n")!.upperBound
                let rest = String(request.head[lineEnd...])
                var payload = Data("\(request.method) \(request.path ?? "/") HTTP/1.1\r\n\(rest)".utf8)
                payload.append(request.extra)
                upstream.send(content: payload, completion: .contentProcessed { _ in })
            }
            let idle = IdleTimeout(queue: self.queue) {
                connection.cancel()
                upstream.cancel()
            }
            idle.touch()
            self.relay(from: connection, to: upstream, idle: idle)
            self.relay(from: upstream, to: connection, idle: idle)
        }
    }

    private func openUpstream(host: String, port: UInt16, client: NWConnection, onReady: @escaping (NWConnection) -> Void) {
        guard let port = NWEndpoint.Port(rawValue: port) else {
            reject(client, status: "400 Bad Request")
            return
        }
        let upstream = NWConnection(host: NWEndpoint.Host(host), port: port, using: .tcp)
        let once = CompletionOnce()
        upstream.stateUpdateHandler = { state in
            switch state {
            case .ready:
                once.run { onReady(upstream) }
            case .failed, .cancelled:
                once.run {
                    upstream.cancel()
                    client.cancel()
                }
            default:
                break
            }
        }
        upstream.start(queue: queue)
        queue.asyncAfter(deadline: .now() + 10) {
            once.run {
                upstream.cancel()
                client.cancel()
            }
        }
    }

    private func relay(from source: NWConnection, to destination: NWConnection, idle: IdleTimeout) {
        source.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            if let data, !data.isEmpty {
                idle.touch()
                destination.send(content: data, completion: .contentProcessed { _ in })
            }
            if isComplete || error != nil {
                idle.cancel()
                source.cancel()
                destination.cancel()
                return
            }
            self.relay(from: source, to: destination, idle: idle)
        }
    }

    private func reject(_ connection: NWConnection, status: String) {
        let response = "HTTP/1.1 \(status)\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
        connection.send(content: Data(response.utf8), completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    // MARK: - Parsing

    private func parse(head: String, extra: Data) -> Request? {
        guard let firstLineEnd = head.range(of: "\r\n") else { return nil }
        let firstLine = String(head[..<firstLineEnd.lowerBound])
        let parts = firstLine.split(separator: " ")
        guard parts.count == 3 else { return nil }
        let method = String(parts[0])
        let target = String(parts[1])

        if method == "CONNECT" {
            guard let authority = splitAuthority(target) else { return nil }
            return Request(
                method: method,
                host: authority.host,
                port: authority.port,
                path: nil,
                isConnect: true,
                head: head,
                extra: extra
            )
        }

        guard target.hasPrefix("http://") else { return nil }
        let rest = String(target.dropFirst("http://".count))
        guard let slash = rest.firstIndex(of: "/") else { return nil }
        let authorityText = String(rest[..<slash])
        let path = String(rest[slash...])
        guard let authority = splitAuthority(authorityText, defaultPort: 80) else { return nil }
        return Request(
            method: method,
            host: authority.host,
            port: authority.port,
            path: path,
            isConnect: false,
            head: head,
            extra: extra
        )
    }

    private func splitAuthority(_ value: String, defaultPort: UInt16 = 443) -> (host: String, port: UInt16)? {
        var host = value
        var port = defaultPort
        if let colon = value.lastIndex(of: ":") {
            let portText = value[value.index(after: colon)...]
            if !portText.isEmpty, let parsed = UInt16(portText) {
                port = parsed
                host = String(value[..<colon])
            }
        }
        host = host.trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
        guard !host.isEmpty else { return nil }
        return (host.lowercased(), port)
    }
}

/// Resets on activity; fires after five idle minutes.
private final class IdleTimeout {
    private let queue: DispatchQueue
    private let handler: () -> Void
    private var item: DispatchWorkItem?

    init(queue: DispatchQueue, handler: @escaping () -> Void) {
        self.queue = queue
        self.handler = handler
    }

    func touch() {
        item?.cancel()
        let work = DispatchWorkItem(block: handler)
        item = work
        queue.asyncAfter(deadline: .now() + 300, execute: work)
    }

    func cancel() {
        item?.cancel()
        item = nil
    }
}

/// Signals at most once; callers run on the proxy queue.
private final class CompletionOnce {
    private var done = false

    func run(_ body: () -> Void) {
        guard !done else { return }
        done = true
        body()
    }
}

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

    func wait() -> String? {
        guard semaphore.wait(timeout: .now() + 2) == .success else {
            return "listener did not become ready"
        }
        lock.lock()
        defer { lock.unlock() }
        return failure
    }
}