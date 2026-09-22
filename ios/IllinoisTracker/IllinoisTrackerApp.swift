import SwiftUI
import UserNotifications

@MainActor final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    weak var model: AppModel?
    private var pendingSequence: Int?
    private var pendingToken: String?
    func attach(_ model: AppModel) {
        self.model = model
        if let pendingToken { Task { await model.registerPush(pendingToken) }; self.pendingToken = nil }
        if let pendingSequence { Task { await model.openNotification(pendingSequence) }; self.pendingSequence = nil }
    }
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }
    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        let token = deviceToken.map { String(format: "%02x", $0) }.joined()
        if let model { Task { await model.registerPush(token) } } else { pendingToken = token }
    }
    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        model?.error = "Push registration failed. Check signing and the Push Notifications capability in Xcode. \(error.localizedDescription)"
    }
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list, .sound])
    }
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        let seq = response.notification.request.content.userInfo["filing_seq"] as? Int
        Task { @MainActor in
            if let seq {
                if let model = self.model { await model.openNotification(seq) } else { self.pendingSequence = seq }
            }
            completionHandler()
        }
    }
}
@main struct IllinoisTrackerApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject private var model = AppModel()
    @Environment(\.scenePhase) private var scenePhase
    var body: some Scene {
        WindowGroup {
            RootView().environmentObject(model)
                .task { delegate.attach(model); await model.refresh() }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active { Task { await model.refreshIfNeeded(); await model.refreshPermission() } }
                }
        }
    }
}
