import UIKit
import UserNotifications

/// The parts of an invitation to play again that only an app delegate is told
/// (docs/ONLINE_PLAY.md §6): this phone's notification token from Apple, and a notification
/// arriving or being tapped. Everything is handed to `Invitations`.
final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        Task { @MainActor in await Invitations.shared.gotToken(deviceToken) }
    }

    /// No token (no network, or a simulator without one): the phone simply cannot be notified yet.
    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {}

    /// The app is open. An invitation is shown in the app itself, with Join and Not now; anything
    /// else (the riddle reminder), or an invitation during a game, is shown as the phone would.
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                            withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        let note = Self.plain(notification.request.content.userInfo)
        let done = Done(completionHandler)
        Task { @MainActor in
            let shown = Invitations.shared.show(note.values, playing: Invitations.shared.isPlaying?() ?? false)
            done.call(shown ? [] : [.banner, .list, .sound])
        }
    }

    /// A notification was tapped.
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                            withCompletionHandler completionHandler: @escaping () -> Void) {
        let note = Self.plain(response.notification.request.content.userInfo)
        let done = Done { (_: Void) in completionHandler() }
        Task { @MainActor in
            Invitations.shared.opened(note.values)
            done.call(())
        }
    }

    /// The system's completion handler, carried to the main actor.
    private struct Done<Value>: @unchecked Sendable {
        let call: (Value) -> Void
        init(_ call: @escaping (Value) -> Void) { self.call = call }
    }

    /// Only the text values of a notification, which is all an invitation has, so they can cross
    /// to the main actor.
    private struct Plain: Sendable { let values: [String: String] }

    private nonisolated static func plain(_ info: [AnyHashable: Any]) -> Plain {
        var values: [String: String] = [:]
        for (key, value) in info {
            if let key = key as? String, let value = value as? String { values[key] = value }
        }
        return Plain(values: values)
    }
}
