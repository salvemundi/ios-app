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
    var notificationStatus = "Meldingen nog niet gecontroleerd."
    var notificationOptions: NotificationOptions?
    var notificationOptionsLoading = false
    var notificationOptionsError: String?
    var notificationPreferencesAvailable = false
    var notificationPreferencesSaving = false
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
    var adminAccess: ActivityAdminAccess?
    var adminCollection: AdminActivityCollection?
    var adminAccessLoading = false
    var adminRevision: UInt64 = 0
    private var adminAccessRequest: UInt64 = 0
    var adminPresentation: ActivityAdminPresentation?
    var adminMessage: String?
    private var adminExportURLs: Set<URL> = []
    var canAdminActivities: Bool { signedIn && adminAccess?.canAccess == true }
    private var deviceToken: String?
    private let login = MemberLogin()
    private var sessionGeneration: UInt64 = 0
    private var refreshRequested = false
    private var retryingRevocations = false

    var signedIn: Bool { session != nil && !(session?.isExpired ?? true) }
    var upcoming: [Activity] { activities.filter { ($0.startsAt ?? .distantFuture) >= .now }.sorted { ($0.startsAt ?? .distantFuture) < ($1.startsAt ?? .distantFuture) } }
    var nextTicket: Ticket? { guard signedIn else { return nil }; return tickets.filter { $0.isValid && !ticketIsPast($0) }.sorted { ($0.startsAt ?? .distantFuture) < ($1.startsAt ?? .distantFuture) }.first }

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
        if signedIn { Task { await refreshActivityAdminAccess() } }
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
        clearActivityAdminState()
        adminPresentation = nil
        SecureSessionStore.clear(); LocalCache.clearPrivate()
        session = nil; profile = nil; tickets = []; selectedTicket = nil; checkoutURL = nil
        preferences = NotificationPreferences()
        notificationPreferencesAvailable = false
        notificationOptions = nil
        notificationOptionsError = nil
        notificationStatus = "Log in om meldingen in te stellen."
        UIApplication.shared.unregisterForRemoteNotifications()
        UNUserNotificationCenter.current().removeAllDeliveredNotifications()
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
        writeWidgetSnapshot()
    }

    func register(for activity: Activity) async {
        guard !activity.registrationClosed() else { notice = "Aanmelden voor deze activiteit is gesloten."; return }
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
            notificationPreferencesAvailable = true
        } catch {
            guard generation == sessionGeneration, session?.token == token else { return }
            notificationPreferencesAvailable = false
            notificationStatus = "Meldingen zijn nog niet beschikbaar op de server. Je kunt de rest van de app gebruiken."
            // Notifications are optional; their storage can be unavailable while core member APIs work.
            if let problem = error as? APIProblem, ["unauthorized", "session_expired", "invalid_session"].contains(problem.code) { handle(problem) }
        }
    }

    func loadNotificationOptions() async {
        guard let token = session?.token, signedIn, !isDemo else { notificationOptions = nil; return }
        let generation = sessionGeneration
        notificationOptionsLoading = true
        notificationOptions = nil
        notificationOptionsError = nil
        defer { if generation == sessionGeneration { notificationOptionsLoading = false } }
        await refreshNotificationPreferences(token: token, generation: generation)
        do {
            let loaded: NotificationOptions = try await api.request("notification-preferences/options", token: token)
            guard generation == sessionGeneration, session?.token == token else { return }
            notificationOptions = loaded
        } catch {
            guard generation == sessionGeneration, session?.token == token else { return }
            notificationOptionsError = "Commissies en beheerrechten konden niet worden geladen. Probeer het opnieuw."
            if let problem = error as? APIProblem, ["unauthorized", "session_expired", "invalid_session"].contains(problem.code) { handle(problem) }
        }
    }

    @discardableResult
    func savePreferences(_ value: NotificationPreferences) async -> Bool {
        guard !isDemo, notificationPreferencesAvailable, !notificationPreferencesSaving else { return false }
        guard let token = session?.token else { return false }
        notificationPreferencesSaving = true
        defer { notificationPreferencesSaving = false }
        let old = preferences; preferences = value
        let generation = sessionGeneration
        do {
            let updated: NotificationPreferences = try await api.mutation("notification-preferences", method: "PATCH", token: token, value: value)
            guard generation == sessionGeneration, session?.token == token else { return false }
            preferences = updated
            return true
        } catch {
            guard generation == sessionGeneration, session?.token == token else { return false }
            preferences = old
            if let problem = error as? APIProblem, ["unauthorized", "session_expired", "invalid_session"].contains(problem.code) { handle(problem) }
            else { errorMessage = "Je meldingsvoorkeuren konden niet worden opgeslagen. Probeer het later opnieuw." }
            return false
        }
    }

    func enableNotifications() async {
        do {
            let allowed = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound])
            if allowed { notificationStatus = "Toestemming ontvangen. Deze iPhone wordt gekoppeld…"; UIApplication.shared.registerForRemoteNotifications() }
            else { notificationStatus = "Meldingen staan uit in de iPhone-instellingen."; notice = "Je kunt meldingen inschakelen in de instellingen van je iPhone." }
        } catch { handle(error) }
    }

    func notificationRegistrationFailed() {
        notificationStatus = "Deze iPhone kon niet voor meldingen worden geregistreerd. Probeer het later opnieuw."
    }
    func receivedDeviceToken(_ token: String) async { deviceToken = token; await registerDeviceIfPossible() }
    private func registerDeviceIfPossible() async {
        guard !isDemo, let token = session?.token else { return }
        let generation = sessionGeneration
        guard await NotificationAuthorization.isAllowed() else {
            guard generation == sessionGeneration else { return }
            notificationStatus = "Meldingen staan uit of zijn nog niet toegestaan op deze iPhone."
            return
        }
        guard generation == sessionGeneration, session?.token == token else { return }
        guard let deviceToken else {
            notificationStatus = "Deze iPhone wordt voor meldingen geregistreerd…"
            UIApplication.shared.registerForRemoteNotifications()
            return
        }
        struct Device: Encodable, Sendable { let token: String; let environment: String }
        let environment = Bundle.main.object(forInfoDictionaryKey: "APNS_ENVIRONMENT") as? String ?? "sandbox"
        do {
            let _: MutationAcknowledgement = try await api.mutation("devices", token: token, value: Device(token: deviceToken, environment: environment))
            guard generation == sessionGeneration, session?.token == token else { return }
            notificationStatus = "Deze iPhone is gekoppeld. Bezorging hangt ook af van de meldingsdienst op acceptatie."
        } catch {
            guard generation == sessionGeneration, session?.token == token else { return }
            notificationStatus = "Deze iPhone kon nog niet aan de meldingsdienst worden gekoppeld. We proberen het opnieuw bij verversen."
        }
    }

    func open(_ url: URL) async {
        guard let link = DeepLink(url: url) else { return }
        switch link {
        case .adminActivities(let id): await openActivityAdministration(activityID: id)
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

    // Administration is memory-only; actual scope changes invalidate private screen state.
    @discardableResult
    func refreshActivityAdminAccess() async -> Bool {
        guard signedIn, !isDemo, let token = session?.token else { clearActivityAdminState(); return false }
        adminAccessRequest &+= 1
        let request = adminAccessRequest
        let generation = sessionGeneration
        let previous = adminAccess
        adminAccessLoading = true
        defer { if request == adminAccessRequest { adminAccessLoading = false } }
        do {
            let access: ActivityAdminAccess = try await api.request("admin/activities/access", token: token)
            guard generation == sessionGeneration, request == adminAccessRequest, token == session?.token else { return false }
            if !access.canAccess {
                clearActivityAdminState()
                adminMessage = "Je hebt geen toegang tot activiteitenbeheer."
                return false
            }
            if let previous, previous.scopeVersion != access.scopeVersion || previous.canCreate != access.canCreate {
                clearActivityAdminState()
            }
            adminAccess = access
            adminMessage = nil
            let revision = adminRevision
            Task { await refreshAdminWidgetAccess(token: token, generation: generation, revision: revision) }
            return true
        } catch {
            guard generation == sessionGeneration, request == adminAccessRequest else { return false }
            if let problem = error as? APIProblem, problem.code == "unauthorized" { handle(problem) }
            else { clearActivityAdminState(); adminMessage = "Activiteitenbeheer is niet beschikbaar of je hebt geen toegang." }
        }
        return false
    }

    func openActivityAdministration(activityID: String? = nil) async {
        if !signedIn { await signIn() }
        guard signedIn else { return }
        selectedActivity = nil; selectedTicket = nil; checkoutURL = nil
        _ = await refreshActivityAdminAccess()
        guard signedIn else { return }
        if canAdminActivities {
            selectedTab = .admin
            if activityID != nil { adminPresentation = ActivityAdminPresentation(activityID: activityID) }
        } else { adminPresentation = ActivityAdminPresentation(activityID: activityID) }
    }

    private func clearActivityAdminState() {
        adminRevision &+= 1
        adminAccessRequest &+= 1
        adminAccess = nil; adminCollection = nil; adminMessage = nil; adminAccessLoading = false
        for url in adminExportURLs { try? FileManager.default.removeItem(at: url) }
        adminExportURLs.removeAll()
        AdminWidgetCredentialStore.clear()
        AdminWidgetSnapshotStore.clear()
        WidgetCenter.shared.reloadAllTimelines()
    }

    private func refreshAdminWidgetAccess(token: String, generation: UInt64, revision: UInt64) async {
        do {
            let credential: AdminWidgetCredential = try await api.mutation("admin/widget-session", token: token, value: EmptyPayload())
            let summary: AdminWidgetSummary = try await api.request("admin/widget-activities", token: token)
            guard generation == sessionGeneration, revision == adminRevision, session?.token == token, canAdminActivities else { return }
            try AdminWidgetCredentialStore.save(credential)
            AdminWidgetSnapshotStore.save(summary)
            WidgetCenter.shared.reloadAllTimelines()
        } catch {
            guard generation == sessionGeneration, revision == adminRevision else { return }
            if let problem = error as? APIProblem, problem.code == "unauthorized" { handle(problem) }
            else if let problem = error as? APIProblem, problem.code == "forbidden" { clearActivityAdminState() }
            // Widgets are optional. Never block normal administration on widget provisioning.
        }
    }

    func adminRequest<Value: Decodable & Sendable>(_ path: String, method: String = "GET", body: Data? = nil, query: [URLQueryItem] = [], as type: Value.Type = Value.self) async throws -> Value {
        guard canAdminActivities, let token = session?.token else { throw CancellationError() }
        let generation = sessionGeneration, revision = adminRevision
        do {
            let value: Value = try await api.request(path, method: method, token: token, body: body, query: query)
            guard generation == sessionGeneration, revision == adminRevision, session?.token == token, canAdminActivities else { throw CancellationError() }
            return value
        } catch {
            guard generation == sessionGeneration, revision == adminRevision else { throw CancellationError() }
            if let problem = error as? APIProblem, problem.code == "unauthorized" { handle(problem) }
            else if let problem = error as? APIProblem, problem.code == "forbidden" { clearActivityAdminState(); adminMessage = problem.message }
            else if let problem = error as? APIProblem, problem.code == "not_found", !path.hasSuffix("/scan") { clearActivityAdminState(); adminMessage = "Deze activiteit is niet meer beschikbaar of je hebt geen toegang." }
            else if error is URLError { clearActivityAdminState(); adminMessage = "Activiteitenbeheer is alleen beschikbaar met een internetverbinding." }
            throw error
        }
    }

    func adminMutation<Input: Encodable & Sendable, Output: Decodable & Sendable>(_ path: String, method: String = "POST", value: Input, as type: Output.Type = Output.self) async throws -> Output {
        try await adminRequest(path, method: method, body: JSONCoding.encoder().encode(value))
    }

    @discardableResult
    func loadAdminActivities() async throws -> AdminActivityCollection {
        adminCollection = nil
        let value: AdminActivityCollection = try await adminRequest("admin/activities")
        adminCollection = value
        return value
    }

    func uploadAdminImage(activityID: String, data: Data, mimeType: String = "image/jpeg", filename: String = "activity.jpg") async throws -> AdminActivityDetail {
        guard canAdminActivities, let token = session?.token else { throw CancellationError() }
        let generation = sessionGeneration, revision = adminRevision
        do {
            let detail: AdminActivityDetail = try await api.upload("admin/activities/\(activityID)/image", image: data, token: token, mimeType: mimeType, filename: filename)
            guard generation == sessionGeneration, revision == adminRevision, session?.token == token, canAdminActivities else { throw CancellationError() }
            return detail
        } catch {
            guard generation == sessionGeneration, revision == adminRevision else { throw CancellationError() }
            if let problem = error as? APIProblem, problem.code == "unauthorized" { handle(problem) }
            else if let problem = error as? APIProblem, problem.code == "forbidden" { clearActivityAdminState(); adminMessage = problem.message }
            throw error
        }
    }

    func recordAdminExport(_ data: Data, extension suffix: String) throws -> URL {
        guard canAdminActivities else { throw CancellationError() }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Salve-Mundi-deelnemers-\(UUID().uuidString).\(suffix)")
        try data.write(to: url, options: [.atomic, .completeFileProtection])
        adminExportURLs.insert(url)
        return url
    }
    func removeAdminExport(_ url: URL) { try? FileManager.default.removeItem(at: url); adminExportURLs.remove(url) }

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

enum AppTab: Hashable { case home, activities, tickets, profile, admin }

struct ActivityAdminPresentation: Identifiable { let id = UUID(); let activityID: String? }
