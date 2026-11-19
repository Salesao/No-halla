//
//  InstalledAppCatalog.swift
//  NoHalla
//
//  Shared app discovery for the onboarding list and the Settings picker (D40):
//  running regular apps plus installed bundles from /Applications and
//  ~/Applications, recursively, without descending into app packages.
//  System apps are intentionally left out (they are deny-listed).
//

import AppKit
import Foundation

struct AppCatalogEntry: Identifiable, Hashable {
    let bundleID: String
    let name: String
    let path: String

    var id: String { bundleID }
}

enum InstalledAppCatalog {
    /// Regular running apps, sorted by name.
    static func running(excluding selfBundleID: String) -> [AppCatalogEntry] {
        NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && $0.bundleIdentifier != selfBundleID }
            .compactMap { app in
                guard let bundleID = app.bundleIdentifier, let url = app.bundleURL else { return nil }
                return AppCatalogEntry(bundleID: bundleID, name: app.localizedName ?? bundleID, path: url.path)
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// Installed apps under /Applications and ~/Applications, deduped by bundle
    /// ID, sorted by display name. Nested `.app` bundles inside other apps are
    /// skipped by `skipsPackageDescendants`.
    static func installed() -> [AppCatalogEntry] {
        var roots = [URL(fileURLWithPath: "/Applications", isDirectory: true)]
        if let userApplications = FileManager.default.urls(for: .applicationDirectory, in: .userDomainMask).first {
            roots.append(userApplications)
        }

        var seen = Set<String>()
        var result: [AppCatalogEntry] = []
        for root in roots {
            for entry in scan(root) where seen.insert(entry.bundleID).inserted {
                result.append(entry)
                if result.count >= 1000 { break }
            }
        }
        return result.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private static func scan(_ root: URL) -> [AppCatalogEntry] {
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return [] }

        var result: [AppCatalogEntry] = []
        for case let url as URL in enumerator {
            guard url.pathExtension == "app" else { continue }
            guard let bundle = Bundle(url: url), let bundleID = bundle.bundleIdentifier else { continue }
            let name = (bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
                ?? (bundle.object(forInfoDictionaryKey: "CFBundleName") as? String)
                ?? url.deletingPathExtension().lastPathComponent
            result.append(AppCatalogEntry(bundleID: bundleID, name: name, path: url.path))
            if result.count >= 1000 { break }
        }
        return result
    }
}