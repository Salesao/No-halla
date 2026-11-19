//
//  DomainGuardInstallView.swift
//  NoHalla
//
//  Shared install/remove row for the D32 root helper (D41/D42/D43): Install…,
//  Copy command, progress, failure hint, an installed confirmation, and — in
//  Settings only — Uninstall…. Used by Settings → Protection and by the
//  onboarding Blocked sites step.
//

import SwiftUI

struct DomainGuardInstallView: View {
    /// The uninstall action is intentionally Settings-only (owner request).
    var showsUninstall = false

    @State private var installed = DomainGuardInstaller.isInstalled
    @State private var suffixCapable = DomainGuardInstaller.isSuffixCapable
    @State private var installing = false
    @State private var uninstalling = false
    @State private var error: String?
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.spacing1) {
            if installed {
                HStack(spacing: DesignTokens.spacing2) {
                    Text(L10n.string("ui.domain-guard-installed"))
                        .font(.system(size: DesignTokens.typeSmall))
                        .foregroundStyle(DesignTokens.muted)
                    Spacer()
                    if uninstalling {
                        ProgressView().controlSize(.small)
                    } else if showsUninstall {
                        Button(L10n.string("ui.domain-guard-uninstall")) { uninstall() }
                            .buttonStyle(.bordered)
                            .tint(DesignTokens.red)
                    }
                }
                if !suffixCapable {
                    Text(L10n.string("ui.domain-guard-reinstall"))
                        .font(.system(size: DesignTokens.typeSmall))
                        .foregroundStyle(DesignTokens.red)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: DesignTokens.spacing2) {
                        Button(L10n.string("ui.domain-guard-reinstall-action")) { install() }
                            .buttonStyle(.bordered)
                            .disabled(installing)
                        if installing {
                            ProgressView().controlSize(.small)
                        }
                    }
                }
            } else {
                Text(L10n.string("ui.domain-guard-not-installed"))
                    .font(.system(size: DesignTokens.typeSmall))
                    .foregroundStyle(DesignTokens.red)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: DesignTokens.spacing2) {
                    Button(L10n.string("ui.domain-guard-install")) { install() }
                        .buttonStyle(.borderedProminent)
                        .disabled(installing)
                    Button(copied ? L10n.string("ui.domain-guard-copied") : L10n.string("ui.domain-guard-copy-command")) {
                        copyCommand()
                    }
                    .buttonStyle(.bordered)
                    if installing {
                        ProgressView().controlSize(.small)
                    }
                }
                Text(DomainGuardInstaller.command)
                    .font(.system(size: DesignTokens.typeSmall, design: .monospaced))
                    .foregroundStyle(DesignTokens.text)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let error = error {
                Text(error)
                    .font(.system(size: DesignTokens.typeSmall))
                    .foregroundStyle(DesignTokens.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .onAppear {
            installed = DomainGuardInstaller.isInstalled
            suffixCapable = DomainGuardInstaller.isSuffixCapable
        }
    }

    private func install() {
        guard !installing else { return }
        installing = true
        error = nil
        Task {
            let ok = await DomainGuardInstaller.install()
            await MainActor.run {
                installing = false
                if ok {
                    installed = true
                    suffixCapable = DomainGuardInstaller.isSuffixCapable
                } else {
                    error = L10n.string("ui.domain-guard-install-failed")
                }
            }
        }
    }

    private func uninstall() {
        guard !uninstalling else { return }
        uninstalling = true
        error = nil
        Task {
            let ok = await DomainGuardInstaller.uninstall()
            await MainActor.run {
                uninstalling = false
                if ok {
                    installed = false
                } else {
                    error = L10n.string("ui.domain-guard-uninstall-failed")
                }
            }
        }
    }

    private func copyCommand() {
        DomainGuardInstaller.copyCommand()
        copied = true
        Task {
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            await MainActor.run { copied = false }
        }
    }
}

#Preview {
    DomainGuardInstallView(showsUninstall: true)
        .padding()
        .frame(width: 420)
}