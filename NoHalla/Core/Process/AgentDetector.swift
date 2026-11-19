//
//  AgentDetector.swift
//  NoHalla
//
//  Recognizes CLI coding agents for the D30 `.agentTerminals` freeze scope, so
//  only terminal sessions hosting an agent stop while the app and every other
//  terminal keep running. Read-only: libproc data plus KERN_PROCARGS2.
//

import Darwin
import Foundation

/// One supported CLI agent: display name for docs, executable names as they
/// appear in `pbi_comm`/argv, and npm-package fragments for Node installs
/// where argv only shows `node …/cli.js`.
struct AgentCatalogEntry {
    let name: String
    let executables: [String]
    let patterns: [String]
}

enum AgentDetector {
    /// US vendors whose CLIs inherit a regional block on Russia/China
    /// (Anthropic, OpenAI, Google, xAI, GitHub, Cursor) first, then
    /// model-agnostic harnesses that a user may point at a blocked provider.
    /// Checked 2026-11: see README for the per-vendor availability summary.
    static let catalog: [AgentCatalogEntry] = [
        AgentCatalogEntry(name: "Claude Code", executables: ["claude"], patterns: ["claude-code"]),
        AgentCatalogEntry(name: "OpenAI Codex CLI", executables: ["codex"], patterns: ["@openai/codex"]),
        AgentCatalogEntry(name: "Google Antigravity CLI", executables: ["agy"], patterns: ["antigravity-cli"]),
        AgentCatalogEntry(name: "Gemini CLI (legacy)", executables: ["gemini"], patterns: ["@google/gemini-cli"]),
        AgentCatalogEntry(name: "xAI Grok Build", executables: ["grok"], patterns: []),
        AgentCatalogEntry(name: "GitHub Copilot CLI", executables: ["copilot"], patterns: ["@github/copilot"]),
        AgentCatalogEntry(name: "Cursor CLI", executables: ["cursor-agent"], patterns: []),
        AgentCatalogEntry(name: "Factory Droid", executables: ["droid"], patterns: []),
        AgentCatalogEntry(name: "Amp", executables: ["amp"], patterns: ["@sourcegraph/amp"]),
        AgentCatalogEntry(name: "Kiro CLI", executables: ["kiro-cli"], patterns: []),
        AgentCatalogEntry(name: "Aider", executables: ["aider"], patterns: []),
        AgentCatalogEntry(name: "OpenCode", executables: ["opencode"], patterns: []),
        AgentCatalogEntry(name: "Crush", executables: ["crush"], patterns: []),
        AgentCatalogEntry(name: "Goose", executables: ["goose"], patterns: []),
        AgentCatalogEntry(name: "OpenHands", executables: ["openhands"], patterns: [])
    ]

    /// Login shells report "-zsh", so detection strips a leading dash.
    static let shellNames: Set<String> = [
        "sh", "bash", "zsh", "fish", "dash", "ksh", "tcsh", "csh", "nu", "elvish", "xonsh"
    ]

    private static let executables: Set<String> = Set(catalog.flatMap(\.executables))
    private static let patterns: [String] = catalog.flatMap(\.patterns)
    /// Interpreters that run a JS/Python CLI as their first non-flag argument.
    private static let runtimes: Set<String> = [
        "node", "bun", "deno", "npx", "python", "python3", "uv", "uvx"
    ]

    /// True when the process is a catalogued agent CLI attached to a terminal.
    /// The controlling-tty requirement filters out background daemons (for
    /// example Codex's `app-server daemon`, which has no tty), and the
    /// same-uid check keeps detection inside the current user's processes.
    static func isAgent(pid: Int32) -> Bool {
        guard pid > 1, ProcessEnumerator.uid(of: pid) == getuid() else { return false }
        guard ProcessEnumerator.hasControllingTerminal(of: pid) else { return false }
        if let comm = normalizedName(ProcessEnumerator.comm(of: pid)), executables.contains(comm) {
            return true
        }
        let arguments = argv(of: pid)
        guard let executable = arguments.first else { return false }

        // Direct install: argv[0] is the CLI itself (`claude`, `agy`, `grok`).
        let executableName = (executable as NSString).lastPathComponent
        if let name = normalizedName(executableName), executables.contains(name) {
            return true
        }
        // Node/Python install: `node …/claude`, `python -m aider`, `npx …`.
        if let runtime = normalizedName(executableName), runtimes.contains(runtime) {
            for argument in arguments.dropFirst().prefix(2) {
                guard !argument.hasPrefix("-") else { continue }
                let name = (argument as NSString).lastPathComponent
                if let name = normalizedName(name), executables.contains(name) { return true }
            }
        }
        // Package-installed CLIs expose only `…/cli.js`; match the package path.
        let joined = arguments.joined(separator: " ").lowercased()
        return patterns.contains { joined.contains($0) }
    }

    /// True when the process is a shell, the root of one terminal session.
    static func isShell(pid: Int32) -> Bool {
        if let name = normalizedName(ProcessEnumerator.comm(of: pid)), shellNames.contains(name) {
            return true
        }
        guard let path = ProcessEnumerator.path(of: pid) else { return false }
        guard let name = normalizedName((path as NSString).lastPathComponent) else { return false }
        return shellNames.contains(name)
    }

    /// argv of another same-uid process via `KERN_PROCARGS2`, which is the only
    /// public way to tell a Node-based agent from an arbitrary Node process.
    /// Returns [] when the kernel refuses or the buffer cannot be parsed.
    static func argv(of pid: Int32) -> [String] {
        guard pid > 1 else { return [] }
        var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
        var size = 0
        guard sysctl(&mib, 3, nil, &size, nil, 0) == 0, size > 8, size <= 1 << 20 else { return [] }
        var buffer = [UInt8](repeating: 0, count: size)
        guard sysctl(&mib, 3, &buffer, &size, nil, 0) == 0, size > 8 else { return [] }

        let argc = buffer.withUnsafeBytes { $0.load(fromByteOffset: 0, as: Int32.self) }
        guard argc > 0, argc <= 4096 else { return [] }

        // Layout: argc, exec path, NUL padding, argv[0…argc-1], env…
        var index = 4
        while index < size && buffer[index] != 0 { index += 1 }
        while index < size && buffer[index] == 0 { index += 1 }

        var arguments: [String] = []
        var current: [UInt8] = []
        while index < size, arguments.count < Int(argc) {
            if buffer[index] == 0 {
                arguments.append(String(decoding: current, as: UTF8.self))
                current.removeAll(keepingCapacity: true)
            } else {
                current.append(buffer[index])
            }
            index += 1
        }
        return arguments
    }

    /// Lowercased name without a login-shell dash. Empty → nil.
    private static func normalizedName(_ name: String?) -> String? {
        guard var value = name?.lowercased(), !value.isEmpty else { return nil }
        if value.hasPrefix("-") { value.removeFirst() }
        return value.isEmpty ? nil : value
    }
}