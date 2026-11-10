import AuthenticationServices
import Foundation
import Observation
import UIKit
import UserNotifications
import WidgetKit

@MainActor @Observable
final class AppModel {
    static let shared = AppModel()
    let server: URL
    let api: APIClient
    var activities: [Activity] = []
    var tickets: [Ticket] = []
    var profile: MemberProfile?
    var preferences = NotificationPreferences()
    var session: AppSession?
    var isLoading = false
    var isSigningIn = false
    var isSaving = false
    var errorMessage: String?
    var backendUnavailableMessage: String?
    var notice: String?
    var lastUpdated: Date?
    var isOffline = false
    var selectedTab: AppTab = .home
    var selectedActivity: Activity?
    var selectedTicket: Ticket?
    var registrationInProgress: String?
    var checkoutURL: URL?
    var isDemo = false
    private var deviceToken: String?
    private let login = MemberLogin()
    private var sessionGeneration: UInt64 = 0
    private var refreshRequested = false
    private var retryingRevocations = false

    var signedIn: Bool { session != nil && !(session?.isExpired ?? true) }
    var upcoming: [Activity] { activities.filter { ($0.startsAt ?? .distantFuture) >= .now }.sorted { ($0.startsAt ?? .distantFuture) < ($1.startsAt ?? .distantFuture) } }
    var nextTicket: Ticket? { guard signedIn else { return nil }; return tickets.filter { $0.isValid && ($0.startsAt ?? .distantPast) >= .now }.sorted { ($0.startsAt ?? .distantFuture) < ($1.startsAt ?? .distantFuture) }.first }

    private init() {
        let configured = Bundle.main.object(forInfoDictionaryKey: "API_BASE_URL") as? String ?? "https://acc.salvemundi.nl"
        server = URL(string: configured) ?? URL(string: "https://acc.salvemundi.nl")!
        api = APIClient(baseURL: server)
        session = SecureSessionStore.read()
        activities = LocalCache.read("activities.json", as: [Activity].self) ?? []
        if session?.isExpired == false {
            tickets = LocalCache.read("tickets.json", as: [Ticket].self) ?? []
            profile = LocalCache.read("profile.json", as: MemberProfile.self)
            lastUpdated = LocalCache.read("updated.json", as: Date.self)
        } else {
            session = nil; SecureSessionStore.clear(); LocalCache.clearPrivate()
        }
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--demo") {
            isDemo = true
            activities = PreviewData.activities
            profile = PreviewData.profile
            tickets = PreviewData.tickets
            session = AppSession(token: "demo-not-a-real-session", expiresAt: .now.addingTimeInterval(86400))
        }
        #endif
        writeWidgetSnapshot()
    }

    func refresh() async {
        guard !isLoading else { refreshRequested = true; return }
        if isDemo { return }
        if session?.isExpired == true { clearSession() }
        isLoading = true
        Task { await retryPendingRevocations() }
        let generation = sessionGeneration
        defer {
            isLoading = false
            if refreshRequested {
                refreshRequested = false
                Task { await self.refresh() }
            }
        }
        do {
            let loadedActivities: [Activity] = try await api.request("activities")
            guard generation == sessionGeneration else { return }
            activities = loadedActivities
            backendUnavailableMessage = nil
            LocalCache.save(activities, name: "activities.json")
            isOffline = false
            if signedIn, let token = session?.token {
                async let loadedProfile: MemberProfile = api.request("me", token: token)
                async let loadedTickets: [Ticket] = api.request("me/tickets", token: token)
                let result = try await (loadedProfile, loadedTickets)
                guard generation == sessionGeneration, session?.token == token else { return }
                profile = result.0; tickets = result.1
                Task { await refreshNotificationPreferences(token: token, generation: generation) }
                LocalCache.save(tickets, name: "tickets.json")
                LocalCache.save(profile, name: "profile.json")
                await registerDeviceIfPossible()
                guard generation == sessionGeneration else { return }
            } else if session != nil { await logout(); return }
            lastUpdated = .now
            LocalCache.save(lastUpdated, name: "updated.json")
            writeWidgetSnapshot()
        } catch { if generation == sessionGeneration { handle(error) } }
    }

    func signIn() async {
        guard !isSigningIn else { return }
        isSigningIn = true; errorMessage = nil
        defer { isSigningIn = false }
        do {
            let result = try await login.signIn(server: server, api: api)
            backendUnavailableMessage = nil
            clearSession()
            try SecureSessionStore.save(result)
            session = result
            if await NotificationAuthorization.isAllowed() { UIApplication.shared.registerForRemoteNotifications() }
            await refresh()
        } catch let error as ASWebAuthenticationSessionError where error.code == .canceledLogin { }
        catch { handle(error) }
    }

    func logout() async {
        let previous = session
        let demo = isDemo
        if !demo, let previous {
            do { try SecureSessionStore.enqueueRevocation(PendingRevocation(token: previous.token, expiresAt: previous.expiresAt, deviceToken: deviceToken)) }
            catch { errorMessage = error.localizedDescription }
        }
        clearSession()
        isDemo = false
        notice = "Je bent uitgelogd."
        if !demo { await retryPendingRevocations() }
    }

    /// Revocation-only credentials are isolated from the active login and are never sent to widgets.
    private func retryPendingRevocations() async {
        guard !retryingRevocations, !isDemo else { return }
        retryingRevocations = true
        defer { retryingRevocations = false }
        let client = APIClient(baseURL: server, timeout: 5)
        for pending in SecureSessionStore.pendingRevocations() {
            do {
                if let device = pending.deviceToken {
                    let _: MutationAcknowledgement = try await client.request("devices/\(device)", method: "DELETE", token: pending.token)
                }
                let _: MutationAcknowledgement = try await client.mutation("auth/logout", token: pending.token, value: EmptyPayload())
                try SecureSessionStore.removeRevocation(token: pending.token)
            } catch let problem as APIProblem where problem.code == "unauthorized" {
                try? SecureSessionStore.removeRevocation(token: pending.token)
            } catch { break } // Retry on the next launch/foreground; never block normal app loading.
        }
    }

    private func clearSession() {
        sessionGeneration &+= 1
        SecureSessionStore.clear(); LocalCache.clearPrivate()
        session = nil; profile = nil; tickets = []; selectedTicket = nil; checkoutURL = nil
        preferences = NotificationPreferences()
        UIApplication.shared.unregisterForRemoteNotifications()
        UNUserNotificationCenter.current().removeAllDeliveredNotifications()
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
        writeWidgetSnapshot()
    }

    func register(for activity: Activity) async {
        guard !isDemo else { notice = "Dit is een demonstratie. Er wordt geen echte inschrijving gemaakt."; return }
        guard signedIn, let token = session?.token else { await signIn(); return }
        guard registrationInProgress == nil else { return }
        registrationInProgress = activity.id
        let generation = sessionGeneration
        defer { registrationInProgress = nil }
        do {
            let registration: Registration = try await api.mutation("activities/\(activity.id)/registrations", token: token, value: EmptyPayload())
            guard generation == sessionGeneration, session?.token == token else { return }
            if let url = registration.checkoutURL {
                guard url.scheme == "https", let host = url.host,
                      host == "mollie.com" || host.hasSuffix(".mollie.com") || host == server.host else {
                    throw APIProblem(code: "invalid_checkout", message: "De betaalpagina kon niet veilig worden geopend.")
                }
                checkoutURL = url
            } else { notice = "Je inschrijving is bevestigd. Je ticket staat bij Tickets." }
            await refresh()
        } catch { if generation == sessionGeneration { handle(error) } }
    }

    func saveProfile(phone: String) async -> Bool {
        guard !isDemo else { notice = "Demonstratie: er worden geen gegevens opgeslagen."; return false }
        guard let token = session?.token else { return false }
        isSaving = true; defer { isSaving = false }
        let generation = sessionGeneration
        do {
            let updated: MemberProfile = try await api.mutation("me", method: "PATCH", token: token, value: ProfileUpdate(phoneNumber: phone.trimmingCharacters(in: .whitespaces)))
            guard generation == sessionGeneration, session?.token == token else { return false }
            profile = updated; LocalCache.save(updated, name: "profile.json"); notice = "Je gegevens zijn opgeslagen."
            return true
        } catch { if generation == sessionGeneration { handle(error) }; return false }
    }

    private func refreshNotificationPreferences(token: String, generation: UInt64) async {
        do {
            let loaded: NotificationPreferences = try await api.request("notification-preferences", token: token)
            guard generation == sessionGeneration, session?.token == token else { return }
            preferences = loaded
        } catch {
            guard generation == sessionGeneration, session?.token == token else { return }
            // Notifications are optional; their storage can be unavailable while core member APIs work.
            if let problem = error as? APIProblem, ["unauthorized", "session_expired", "invalid_session"].contains(problem.code) { handle(problem) }
        }
    }

    func savePreferences(_ value: NotificationPreferences) async {
        guard !isDemo else { return }
        guard let token = session?.token else { return }
        let old = preferences; preferences = value
        let generation = sessionGeneration
        do {
            let updated: NotificationPreferences = try await api.mutation("notification-preferences", method: "PATCH", token: token, value: value)
            guard generation == sessionGeneration, session?.token == token else { return }
            preferences = updated
        } catch {
            guard generation == sessionGeneration, session?.token == token else { return }
            preferences = old
            if let problem = error as? APIProblem, ["unauthorized", "session_expired", "invalid_session"].contains(problem.code) { handle(problem) }
            else { errorMessage = "Je meldingsvoorkeuren konden niet worden opgeslagen. Probeer het later opnieuw." }
        }
    }

    func enableNotifications() async {
        do {
            let allowed = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound])
            if allowed { UIApplication.shared.registerForRemoteNotifications(); notice = "Meldingen zijn ingeschakeld." }
            else { notice = "Je kunt meldingen inschakelen in de instellingen van je iPhone." }
        } catch { handle(error) }
    }

    func receivedDeviceToken(_ token: String) async { deviceToken = token; await registerDeviceIfPossible() }
    private func registerDeviceIfPossible() async {
        guard !isDemo, let deviceToken, let token = session?.token else { return }
        struct Device: Encodable, Sendable { let token: String; let environment: String }
        let environment = Bundle.main.object(forInfoDictionaryKey: "APNS_ENVIRONMENT") as? String ?? "sandbox"
        do { let _: MutationAcknowledgement = try await api.mutation("devices", token: token, value: Device(token: deviceToken, environment: environment)) }
        catch { /* Retry after the next successful foreground refresh. */ }
    }

    func open(_ url: URL) async {
        guard let link = DeepLink(url: url) else { return }
        switch link {
        case .activities: selectedTab = .activities
        case .activity(let id):
            selectedTab = .activities
            if let activity = activities.first(where: { $0.id == id }) { selectedActivity = activity }
            else {
                do { selectedActivity = try await api.request("activities/\(id)", token: session?.token) }
                catch { handle(error) }
            }
        case .ticket(let id):
            selectedTab = .tickets; await refresh(); selectedTicket = tickets.first(where: { $0.id == id })
        case .tickets, .paymentReturn: selectedTab = .tickets; checkoutURL = nil; await refresh()
        }
    }

    private func handle(_ error: Error) {
        if let problem = error as? APIProblem, problem.code == "backend_unavailable" {
            backendUnavailableMessage = problem.message
            isOffline = false
            errorMessage = nil
        } else if let problem = error as? APIProblem, ["unauthorized", "session_expired", "invalid_session"].contains(problem.code) {
            clearSession(); errorMessage = "Je sessie is verlopen. Log opnieuw in."
        } else if error is URLError {
            isOffline = true
            errorMessage = "Geen verbinding. Je eerder geladen activiteiten en tickets blijven beschikbaar."
        } else { errorMessage = error.localizedDescription }
    }

    private func writeWidgetSnapshot() {
        let summaries = upcoming.prefix(4).map { WidgetEvent(id: $0.id, title: $0.title, startsAt: $0.startsAt, location: $0.location) }
        let booking = nextTicket.map { WidgetEvent(id: $0.activityID ?? $0.id, title: $0.title, startsAt: $0.startsAt, location: $0.location) }
        guard !isDemo else { return }
        let snapshot = WidgetSnapshot(events: summaries, nextBooking: signedIn ? booking : nil, signedIn: signedIn)
        if let directory = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: WidgetSnapshot.appGroup), let data = try? JSONCoding.encoder().encode(snapshot) {
            try? data.write(to: directory.appendingPathComponent(WidgetSnapshot.fileName), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        }
        WidgetCenter.shared.reloadAllTimelines()
    }
}

enum AppTab: Hashable { case home, activities, tickets, profile }
