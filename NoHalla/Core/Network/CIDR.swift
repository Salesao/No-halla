//
//  CIDR.swift
//  NoHalla
//
//  IPv4/IPv6 address parsing and CIDR matching for the trusted-address list
//  (implementation brief §8.3). Parsing uses inet_pton; matching compares the
//  leading prefix bits of the network-order byte representation (32 bits for
//  IPv4, 128 bits for IPv6). A bare IP is treated as /32 or /128.
//

import Darwin
import Foundation

/// Address family of a parsed IP address.
enum IPFamily {
    case v4
    case v6
}

/// A parsed IPv4 (4 bytes) or IPv6 (16 bytes) address in network byte order.
struct IPAddress: Equatable, CustomStringConvertible {
    /// Network-order bytes: exactly 4 for IPv4, exactly 16 for IPv6.
    let bytes: [UInt8]

    init?(_ string: String) {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        var v4 = in_addr()
        if inet_pton(AF_INET, trimmed, &v4) == 1 {
            self.bytes = withUnsafeBytes(of: &v4) { Array($0) }
            return
        }

        var v6 = in6_addr()
        if inet_pton(AF_INET6, trimmed, &v6) == 1 {
            self.bytes = withUnsafeBytes(of: &v6) { Array($0) }
            return
        }

        return nil
    }

    var family: IPFamily {
        bytes.count == 4 ? .v4 : .v6
    }

    /// Full, unmasked textual address (canonical form via inet_ntop).
    var description: String {
        let capacity = family == .v4 ? Int(INET_ADDRSTRLEN) : Int(INET6_ADDRSTRLEN)
        var buffer = [CChar](repeating: 0, count: capacity)
        let rendered: String? = bytes.withUnsafeBytes { raw -> String? in
            guard let base = raw.baseAddress else { return nil }
            let addressFamily = family == .v4 ? AF_INET : AF_INET6
            guard inet_ntop(addressFamily, base, &buffer, socklen_t(capacity)) != nil else {
                return nil
            }
            let ascii = buffer.prefix(while: { $0 != 0 }).map { UInt8(bitPattern: $0) }
            return String(decoding: ascii, as: UTF8.self)
        }
        // Bytes are validated at init, so rendering cannot fail in practice;
        // fall back to a byte-derived form rather than force-unwrapping.
        return rendered ?? expandedDescription
    }

    /// Log-safe form: last IPv4 octet or last IPv6 group replaced with `x`
    /// (e.g. `203.0.113.x`, `2001:db8::x`). Full IPs are debug-only (FR-39).
    var masked: String {
        let full = description
        let separator: Character = family == .v4 ? "." : ":"
        guard let cut = full.lastIndex(of: separator) else { return full }
        return String(full[...cut]) + "x"
    }

    /// Byte-derived rendering used only if inet_ntop unexpectedly fails.
    private var expandedDescription: String {
        switch family {
        case .v4:
            return bytes.map { String($0) }.joined(separator: ".")
        case .v6:
            return stride(from: 0, to: bytes.count, by: 2).map { index in
                let group = (UInt16(bytes[index]) << 8) | UInt16(bytes[index + 1])
                return String(group, radix: 16)
            }.joined(separator: ":")
        }
    }
}

/// A trusted IP or CIDR block. A bare address becomes a /32 (IPv4) or /128
/// (IPv6) range; `address/prefix` requires a prefix within the family's range.
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
            self.prefixLength = ip.family == .v4 ? 32 : 128
        case 2:
            guard let ip = IPAddress(String(parts[0])) else { return nil }
            let prefixText = String(parts[1])
            guard !prefixText.isEmpty,
                  prefixText.allSatisfy({ $0 >= "0" && $0 <= "9" }),
                  let prefix = Int(prefixText)
            else { return nil }
            let maxPrefix = ip.family == .v4 ? 32 : 128
            guard prefix <= maxPrefix else { return nil }
            self.address = ip
            self.prefixLength = prefix
        default:
            return nil
        }
    }

    /// Bitwise prefix match. Cross-family comparisons never match; /0 matches
    /// every address of the same family, /32 and /128 match exactly one.
    func contains(_ ip: IPAddress) -> Bool {
        guard ip.family == address.family,
              ip.bytes.count == address.bytes.count
        else { return false }

        let bitCount = address.bytes.count * 8
        guard prefixLength >= 0, prefixLength <= bitCount else { return false }

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
