//
//  ProtectedApp.swift
//  NoHalla
//
//  An application selected for protection, identified by its bundle ID
//  (implementation brief §5.4).
//

import Foundation

/// A user-selected app whose processes are frozen on an untrusted IP.
struct ProtectedApp: Codable, Equatable, Identifiable {
    var bundleID: String
    var name: String
    var enabled: Bool

    var id: String { bundleID }
}
