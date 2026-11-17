import SwiftUI
import UserNotifications

@main
struct SalveMundiApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var model = AppModel.shared
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .tint(Brand.accent)
                .task { await model.refresh() }
                .onOpenURL { url in Task { await model.open(url) } }
                .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { activity in
                    if let url = activity.webpageURL { Task { await model.open(url) } }
                }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active { Task { await model.refresh() } }
                }
        }
    }
}

@MainActor
final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        Diagnostics.shared.start()
        AppModel.shared.startConnectivityWatch()
        Task {
            if AppModel.shared.signedIn, await NotificationAuthorization.isAllowed() { application.registerForRemoteNotifications() }
        }
        return true
    }
    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        let token = deviceToken.map { String(format: "%02x", $0) }.joined()
        Task { await AppModel.shared.receivedDeviceToken(token) }
    }
    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        AppModel.shared.notificationRegistrationFailed()
    }
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions { [.banner, .sound, .badge] }
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let destination = NotificationRoute.destination(response.notification.request.content.userInfo)
        await MainActor.run {
            if let destination { Task { await AppModel.shared.open(destination) } }
        }
    }
}
