import SwiftUI
import UserNotifications

@main
struct GridletApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @UIApplicationDelegateAdaptor private var appDelegate: AppDelegate

    var body: some Scene {
        WindowGroup {
            HomeView()
        }
        .onChange(of: scenePhase) { _, newPhase in
            switch newPhase {
            case .background:
                // Schedule a reminder for this evening if the daily isn't done
                // and the user has opted in.
                if UserDefaults.standard.bool(forKey: "dailyReminderEnabled") {
                    let stats = PersistenceService.shared.loadPlayerStats()
                    NotificationService.shared.scheduleDailyReminderIfNeeded(stats: stats)
                }
            case .active:
                // Cancel any pending reminder — the user is in the app.
                NotificationService.shared.cancelDailyReminder()
                Task {
                    await PuzzleWarmupService.shared.startWarmup()
                }
            default:
                break
            }
        }
    }
}

// MARK: - App Delegate (Notification handling)

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate,
    @unchecked Sendable
{
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self

        // Request notification permission on first launch if reminder is enabled.
        if UserDefaults.standard.object(forKey: "dailyReminderEnabled") == nil
            || UserDefaults.standard.bool(forKey: "dailyReminderEnabled")
        {
            Task {
                let granted = await NotificationService.shared.requestPermission()
                if !granted {
                    await MainActor.run {
                        UserDefaults.standard.set(false, forKey: "dailyReminderEnabled")
                    }
                }
            }
        }

        return true
    }

    // Show banner + sound even when the app is in the foreground.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}
