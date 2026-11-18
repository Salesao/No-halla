//
//  LoggingProcessController.swift
//  NoHalla
//
//  Stage-one seam: records process-control intents without touching any
//  process, always reporting an empty frozen list. Replaced by the real
//  SIGSTOP/SIGCONT controller and removed during stage-two wiring.
//

import Foundation
import OSLog

/// No-op process controller for stage one; logs intents via AppLog.process.
final class LoggingProcessController: ProcessControlling {
    func freeze(_ apps: [ProtectedApp]) async -> [FrozenProcess] {
        AppLog.process.info(
            "freeze intent for \(apps.count, privacy: .public) app(s): \(apps.map(\.bundleID).joined(separator: ", "), privacy: .public)"
        )
        return []
    }

    func resumeAll() async -> [FrozenProcess] {
        AppLog.process.info("resumeAll intent")
        return []
    }

    func reconcile(_ apps: [ProtectedApp]) async -> [FrozenProcess] {
        AppLog.process.info(
            "reconcile intent for \(apps.count, privacy: .public) app(s): \(apps.map(\.bundleID).joined(separator: ", "), privacy: .public)"
        )
        return []
    }

    func currentFrozen() async -> [FrozenProcess] {
        AppLog.process.info("currentFrozen query")
        return []
    }
}
