//
//  CIDR.swift
//  NoHalla
//
//  IPv4 address parsing and CIDR matching for the trusted-address list
//  (implementation brief §8.3; owner decision: IPv6 removed). Parsing uses
//  inet_pton; matching compares the leading prefix bits of the network-order
//  byte representation (32 bits). A bare IP is treated as /32.
//

import Darwin
import Foundation

/// A parsed IPv4 address (4 bytes) in network byte order.
struct IPAddress: Equatable, CustomStringConvertible {
    /// Network-order bytes: exactly 4.
    let bytes: [UInt8]

    init?(_ string: String) {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        var v4 = in_addr()
        guard inet_pton(AF_INET, trimmed, &v4) == 1 else { return nil }
        self.bytes = withUnsafeBytes(of: &v4) { Array($0) }
    }

    /// Full, unmasked textual address (canonical form via inet_ntop).
    var description: String {
        var buffer = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
        let rendered: String? = bytes.withUnsafeBytes { raw -> String? in
            guard let base = raw.baseAddress,
                  inet_ntop(AF_INET, base, &buffer, socklen_t(INET_ADDRSTRLEN)) != nil else {
                return nil
            }
            let ascii = buffer.prefix(while: { $0 != 0 }).map { UInt8(bitPattern: $0) }
            return String(decoding: ascii, as: UTF8.self)
        }
        // Bytes are validated at init, so rendering cannot fail in practice;
        // fall back to a byte-derived form rather than force-unwrapping.
        return rendered ?? bytes.map { String($0) }.joined(separator: ".")
    }

    /// Log-safe form: last octet replaced with `x` (e.g. `203.0.113.x`).
    /// Full IPs are debug-only (FR-39).
    var masked: String {
        let full = description
        guard let cut = full.lastIndex(of: ".") else { return full }
        return String(full[...cut]) + "x"
    }
}

/// A trusted IP or CIDR block. A bare address becomes a /32 range;
/// `address/prefix` requires a prefix within 0...32.
struct CIDRRange: Equatable {
    let address: IPAddress
    let prefixLength: Int

    init?(_ string: String) {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let parts = trimmed.split(separator: "/", omittingEmptySubsequences: false)
        switch parts.count {
        case 1:
            guard let ip = IPAddress(String(parts[0])) else { return nil }
            self.address = ip
            self.prefixLength = 32
        case 2:
            guard let ip = IPAddress(String(parts[0])) else { return nil }
            let prefixText = String(parts[1])
            guard !prefixText.isEmpty,
                  prefixText.allSatisfy({ $0 >= "0" && $0 <= "9" }),
                  let prefix = Int(prefixText),
                  prefix <= 32
            else { return nil }
            self.address = ip
            self.prefixLength = prefix
        default:
            return nil
        }
    }

    /// Bitwise prefix match. /0 matches every address, /32 matches exactly one.
    func contains(_ ip: IPAddress) -> Bool {
        guard prefixLength >= 0, prefixLength <= 32 else { return false }

        for bit in 0..<prefixLength {
            let byteIndex = bit / 8
            let mask = UInt8(0x80 >> (bit % 8))
            if (address.bytes[byteIndex] & mask) != (ip.bytes[byteIndex] & mask) {
                return false
            }
        }
        return true
    }
}
