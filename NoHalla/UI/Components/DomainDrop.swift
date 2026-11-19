//
//  DomainDrop.swift
//  NoHalla
//
//  Shared drag-and-drop plumbing for domain lists (D37): resolves the first
//  dropped file URL off the main queue so both Blocked sites surfaces can
//  reuse it. Validation stays in DomainListImport.
//

import Foundation
import UniformTypeIdentifiers

enum DomainDrop {
    /// Loads the dropped file URL. The completion may run on a background
    /// queue; callers hop to the main actor before touching UI state.
    static func loadFileURL(from provider: NSItemProvider, completion: @escaping (URL?) -> Void) {
        guard provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) else {
            completion(nil)
            return
        }
        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
            let url: URL?
            switch item {
            case let data as Data:
                url = URL(dataRepresentation: data, relativeTo: nil)
            case let string as String:
                url = URL(string: string)
            case let nsURL as NSURL:
                url = nsURL as URL
            default:
                url = nil
            }
            completion(url)
        }
    }
}