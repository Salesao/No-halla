//
//  NotificationCoordinator.swift
//  NoHalla
//
//  Local notifications (implementation brief §8.6, FR-29, spec D13).
//  Registers the FROZEN/RESUMED/UNKNOWN categories with a foreground
//  RESUME_ALL action, throttles posts to at most one per kind per 30 s and
//  honors the config notifications toggle. Permission is requested after
//  onboarding, never at launch; when it is denied, the General settings
//  banner uses `isPermissionDenied()` plus `notificationsSettingsURL` to
//  deep-link into System Settings. The RESUME_ALL action is forwarded to
//  `onResumeAllAction` on the main queue.
//

import Foundation
import OSLog
import UserNotifications

/// Notification service seam consumed by the engine/UI wiring (S2).
protocol NotificationCoordinating: AnyObject {
    func requestPermission() async
    func setEnabled(_ enabled: Bool)
    func post(_ event: NotificationEvent)
    var onResumeAllAction: (() -> Void)? { get set }
    func isPermissionDenied() async -> Bool
}

final class NotificationCoordinator: NSObject, UNUserNotificationCenterDelegate, NotificationCoordinating {
    // MARK: - Identifiers

    static let frozenCategoryIdentifier = "FROZEN"
    static let resumedCategoryIdentifier = "RESUMED"
    static let unknownCategoryIdentifier = "UNKNOWN"
    static let resumeAllActionIdentifier = "RESUME_ALL"

    /// System Settings → Notifications pane (macOS 13+). Opened by the
    /// General banner when notification permission is denied.
    static let notificationsSettingsURL = URL(
        string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension"
    )

    /// At most one notification of each kind per this interval (FR-29).
    private static let throttleInterval: TimeInterval = 30

    // MARK: - State

    private let center: UNUserNotificationCenter
    private let log = Logger(subsystem: AppLog.subsystem, category: "notifications")

    /// Guards `enabled`, `lastPosted` and `resumeAllAction`: `post` arrives
    /// from the engine actor, while the toggle, wiring and delegate callbacks
    /// come from the UI side.
    private let lock = NSLock()
    private var enabled: Bool
    /// Last post time per category identifier (one entry per NotificationKind).
    private var lastPosted: [String: Date] = [:]
    private var resumeAllAction: (() -> Void)?

    var onResumeAllAction: (() -> Void)? {
        get {
            lock.lock()
            defer { lock.unlock() }
            return resumeAllAction
        }
        set {
            lock.lock()
            defer { lock.unlock() }
            resumeAllAction = newValue
        }
    }

    // MARK: - Init

    /// Registers the categories and installs the delegate. Deliberately does
    /// not request permission — that happens after onboarding via
    /// `requestPermission()` (FR-29).
    init(enabled: Bool = true, center: UNUserNotificationCenter = .current()) {
        self.enabled = enabled
        self.center = center
        super.init()
        registerCategories()
        center.delegate = self
    }

    // MARK: - NotificationCoordinating

    func requestPermission() async {
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .sound])
            log.info("Notification permission granted: \(granted, privacy: .public)")
        } catch {
            log.error("Notification permission request failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Mirrors the config notifications toggle; while disabled, `post` is a
    /// no-op and foreground presentation is suppressed.
    func setEnabled(_ enabled: Bool) {
        lock.lock()
        self.enabled = enabled
        lock.unlock()
    }

    func post(_ event: NotificationEvent) {
        let category = Self.categoryIdentifier(for: event.kind)
        guard claimPostSlot(for: category) else { return }

        let content = UNMutableNotificationContent()
        content.categoryIdentifier = category
        content.sound = .default
        let apps = Self.appsDescription(event.frozenCount)
        switch event.kind {
        case .frozen:
            content.title = L10n.string("notification.frozen.title")
            // NotificationEvent carries no address, so the IP slot gets a
            // generic descriptor; the apps slot gets the frozen app count.
            content.body = L10n.string("notification.frozen.body", "a new address", apps)
        case .resumed:
            content.title = L10n.string("notification.resumed.title")
            content.body = L10n.string("notification.resumed.body", apps)
        case .unknown:
            content.title = L10n.string("notification.unknown.title")
            content.body = L10n.string("notification.unknown.body")
        }

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        center.add(request) { [log] error in
            if let error {
                log.error("Failed to deliver \(category, privacy: .public) notification: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    func isPermissionDenied() async -> Bool {
        await withCheckedContinuation { continuation in
            center.getNotificationSettings { settings in
                continuation.resume(returning: settings.authorizationStatus == .denied)
            }
        }
    }

    // MARK: - UNUserNotificationCenterDelegate

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        lock.lock()
        let isEnabled = enabled
        lock.unlock()
        completionHandler(isEnabled ? [.banner, .sound] : [])
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        if response.actionIdentifier == Self.resumeAllActionIdentifier {
            let action = onResumeAllAction
            DispatchQueue.main.async {
                action?()
            }
        }
        completionHandler()
    }

    // MARK: - Helpers

    private func registerCategories() {
        let resumeAll = UNNotificationAction(
            identifier: Self.resumeAllActionIdentifier,
            title: L10n.string("action.resumeAll"),
            options: .foreground
        )
        let frozen = UNNotificationCategory(
            identifier: Self.frozenCategoryIdentifier,
            actions: [resumeAll],
            intentIdentifiers: [],
            options: []
        )
        let resumed = UNNotificationCategory(
            identifier: Self.resumedCategoryIdentifier,
            actions: [],
            intentIdentifiers: [],
            options: []
        )
        // UNKNOWN keeps apps frozen until a check succeeds, so Resume all
        // applies there as well.
        let unknown = UNNotificationCategory(
            identifier: Self.unknownCategoryIdentifier,
            actions: [resumeAll],
            intentIdentifiers: [],
            options: []
        )
        center.setNotificationCategories([frozen, resumed, unknown])
    }

    /// Throttle gate (FR-29): returns true and records the post time only
    /// when notifications are enabled and the kind's 30 s window has passed.
    private func claimPostSlot(for category: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard enabled else { return false }
        let now = Date()
        if let last = lastPosted[category], now.timeIntervalSince(last) < Self.throttleInterval {
            return false
        }
        lastPosted[category] = now
        return true
    }

    private static func categoryIdentifier(for kind: NotificationKind) -> String {
        switch kind {
        case .frozen: return frozenCategoryIdentifier
        case .resumed: return resumedCategoryIdentifier
        case .unknown: return unknownCategoryIdentifier
        }
    }

    private static func appsDescription(_ count: Int) -> String {
        count == 1 ? "1 app" : "\(count) apps"
    }
}
