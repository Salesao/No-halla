//
//  ProcessControlling.swift
//  NoHalla
//
//  Boundary between the protection engine and process freeze/resume
//  (implementation brief §5.4, FR-15…19). Every method returns the current
//  list of frozen processes so the engine can persist it via StateStore.
//

import Foundation

/// Freezes and resumes the processes of protected apps.
protocol ProcessControlling: AnyObject {
    /// Freeze the processes of the given apps; returns the current frozen list.
    func freeze(_ apps: [ProtectedApp]) async -> [FrozenProcess]
    /// Resume every frozen process; returns the current (remaining) frozen list.
    func resumeAll() async -> [FrozenProcess]
    /// Align the frozen set with the given apps (freeze new, resume removed);
    /// returns the current frozen list.
    func reconcile(_ apps: [ProtectedApp]) async -> [FrozenProcess]
    /// The current list of frozen processes, without side effects.
    func currentFrozen() async -> [FrozenProcess]
}
