//
//  DNSMessage.swift
//  NoHallaDomainGuard
//
//  Minimal DNS parsing and canned responses (D47). The proxy never rewrites a
//  forwarded packet: it only inspects the question and copies it into an error
//  response. No caching, no compression pointers in questions.
//

import Foundation

enum DNSMessage {
    static let maxPacket = 4096

    struct Question {
        var name: String
        var end: Int
    }

    /// Name and end offset of the single question, or nil for anything this
    /// guard does not understand.
    static func questionName(_ packet: Data) -> Question? {
        guard packet.count >= 12, packet.count <= maxPacket else { return nil }
        let qdcount = (UInt16(packet[4]) << 8) | UInt16(packet[5])
        guard qdcount == 1 else { return nil }

        var offset = 12
        var labels: [String] = []
        while true {
            guard offset < packet.count else { return nil }
            let length = Int(packet[offset])
            if length == 0 {
                offset += 1
                break
            }
            guard length & 0xC0 == 0 else { return nil }
            offset += 1
            guard offset + length <= packet.count else { return nil }
            guard let label = String(data: packet.subdata(in: offset..<(offset + length)), encoding: .utf8) else {
                return nil
            }
            labels.append(label)
            offset += length
            guard labels.count <= 127 else { return nil }
        }
        guard offset + 4 <= packet.count else { return nil }
        let name = labels.joined(separator: ".").lowercased()
        guard !name.isEmpty else { return nil }
        return Question(name: name, end: offset + 4)
    }

    static func nxdomain(for packet: Data) -> Data? {
        response(packet, rcode: 3)
    }

    static func servfail(for packet: Data) -> Data? {
        response(packet, rcode: 2)
    }

    private static func response(_ packet: Data, rcode: UInt8) -> Data? {
        guard let question = questionName(packet), question.end <= packet.count else { return nil }
        var out = packet.prefix(question.end)
        let originalFlags = (UInt16(packet[2]) << 8) | UInt16(packet[3])
        let flags = UInt16(0x8000) | (originalFlags & 0x0100) | UInt16(0x0080) | UInt16(rcode)
        out[2] = UInt8(flags >> 8)
        out[3] = UInt8(flags & 0xFF)
        out[4] = 0
        out[5] = 1
        out[6] = 0
        out[7] = 0
        out[8] = 0
        out[9] = 0
        out[10] = 0
        out[11] = 0
        return Data(out)
    }
}