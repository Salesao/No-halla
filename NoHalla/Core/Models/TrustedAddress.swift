//
//  TrustedAddress.swift
//  NoHalla
//
//  A trusted IP or CIDR entry from the config. Parsing and bit-prefix
//  matching are delegated to CIDRRange (s1-cidr, brief §8.3): a bare address
//  is a /32 range.
//

import Foundation

/// One entry of the trusted-address list, kept in raw string form.
struct TrustedAddress: Codable, Equatable {
    let raw: String

    /// True when the raw string parses as an IP or CIDR range.
    var isValid: Bool {
        CIDRRange(raw) != nil
    }

    /// Bit-prefix match against a parsed address. Invalid entries never match.
    func matches(_ ip: IPAddress) -> Bool {
        guard let range = CIDRRange(raw) else { return false }
        return range.contains(ip)
    }
}
