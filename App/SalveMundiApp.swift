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
                .tint(Brand.purple)
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
        Task {
            let settings = await UNUserNotificationCenter.current().notificationSettings()
            if AppModel.shared.signedIn, settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional { application.registerForRemoteNotifications() }
        }
        return true
    }
    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        let token = deviceToken.map { String(format: "%02x", $0) }.joined()
        Task { await AppModel.shared.receivedDeviceToken(token) }
    }
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions { [.banner, .sound, .badge] }
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let payload = response.notification.request.content.userInfo
        let link = payload["url"] as? String
        let activityID = payload["activityID"] as? String
        await MainActor.run {
            var destination = link.flatMap(URL.init(string:))
            if destination == nil, let activityID {
                var components = URLComponents()
                components.scheme = "salvemundi"; components.host = "activities"; components.path = "/\(activityID)"
                destination = components.url
            }
            if let destination { Task { await AppModel.shared.open(destination) } }
        }
    }
}
