import Combine
import Foundation
#if canImport(MacThermalCore)
import MacThermalCore
#endif

@MainActor
final class ThermalMonitor: ObservableObject {
    let liveState = ThermalLiveState()
    let archiveState = ThermalArchiveState()
    let recordingState = IncidentRecordingState()
    let statusState = AppStatusState()

    private(set) var launchAtLogin: Bool {
        get { statusState.launchAtLogin }
        set { statusState.launchAtLogin = newValue }
    }
    private var history: [ThermalSample] { archiveState.history }
    private var incidents: [ThermalIncident] { archiveState.incidents }
    private(set) var isRecordingIncident: Bool {
        get { recordingState.isRecording }
        set { recordingState.isRecording = newValue }
    }
    private(set) var incidentStartedAt: Date? {
        get { recordingState.startedAt }
        set { recordingState.startedAt = newValue }
    }
    private(set) var incidentSampleCount: Int {
        get { recordingState.sampleCount }
        set { recordingState.sampleCount = newValue }
    }
    private(set) var recordingTrigger: ThermalIncidentTrigger? {
        get { recordingState.trigger }
        set { recordingState.trigger = newValue }
    }
    private(set) var notificationsAuthorized: Bool {
        get { statusState.notificationsAuthorized }
        set { statusState.notificationsAuthorized = newValue }
    }
    var presentedError: UserFacingError? {
        get { statusState.presentedError }
        set { statusState.presentedError = newValue }
    }

    let settings: AppSettings

    private let reader = SMCReader()
    private let processSampler = ProcessSampler()
    private let historyStore = HistoryStore()
    private let notificationManager = LocalNotificationManager()
    private let loginItemManager = LoginItemManager()
    private var alertEvaluator = ThermalAlertEvaluator()
    private var automaticIncidentDetector = AutomaticIncidentDetector()
    private var timer: Timer?
    private var refreshing = false
    private var lastHistoryAt: Date?
    private var lastProcessAt: Date?
    private var cachedProcesses: [ProcessUsage] = []
    private var cachedProcessSnapshotID: UUID?
    private var cachedProcessSampledAt: Date?
    private var incidentSamples: [ThermalSample] = []
    private var activeIncidentID: UUID?
    private var activeIncidentName: String?
    private var activeIncidentJournalAvailable = false
    private var incidentRevision = 0
    private var incidentPersistenceTask: Task<Void, Never>?
    private var loginItemRequestID = UUID()
    private var userChangedLoginItem = false
    private var panelPresented = false
    private var dashboardPresented = false
    private let processInterval: TimeInterval = 15
    private let backgroundRefreshInterval: TimeInterval = 9
    private let interactiveRefreshInterval: TimeInterval = 3
    private let elevatedRefreshInterval: TimeInterval = 2
    private let automaticIncidentPreRoll: TimeInterval = 2 * 60
    private let maximumInMemoryHistoryDays = 14
    private let memoryTrimInterval: TimeInterval = 60 * 60
    private var lastMemoryTrimAt: Date?

    init(settings: AppSettings) {
        self.settings = settings

        Task(priority: .utility) { [weak self] in
            await self?.initialize()
        }
    }

    var hottest: TempReading? { liveState.hottest }
    var averageCelsius: Double { liveState.averageCelsius }
    var menuBarSeverity: Severity { liveState.menuBarSeverity }
    var menuBarSymbol: String { liveState.menuBarSymbol }
    var throttleAssessment: ThrottleAssessment { liveState.throttleAssessment }

    func refresh() {
        beginRefresh(priority: .userInitiated)
    }

    func setPanelPresented(_ presented: Bool) {
        guard panelPresented != presented else { return }
        panelPresented = presented
        presentationDidChange(presented: presented)
    }

    func setDashboardPresented(_ presented: Bool) {
        guard dashboardPresented != presented else { return }
        dashboardPresented = presented
        presentationDidChange(presented: presented)
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        userChangedLoginItem = true
        let requestID = UUID()
        loginItemRequestID = requestID
        launchAtLogin = enabled
        Task {
            let actualValue = await loginItemManager.setEnabled(enabled)
            guard loginItemRequestID == requestID else { return }
            launchAtLogin = actualValue
        }
    }

    func toggleIncidentRecording() {
        Task {
            if isRecordingIncident {
                await stopIncidentRecording()
                if !refreshing { scheduleNextRefresh() }
            } else {
                await startIncidentRecording(trigger: .manual, at: .now)
                beginRefresh(priority: .userInitiated)
            }
        }
    }

    func renameIncident(_ incident: ThermalIncident, to proposedName: String) {
        let name = proposedName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty,
              incidents.contains(where: { $0.id == incident.id }) else { return }
        archiveState.renameIncident(id: incident.id, to: name)
        scheduleIncidentPersistence()
    }

    func deleteIncident(_ incident: ThermalIncident) {
        archiveState.removeIncident(id: incident.id)
        scheduleIncidentPersistence()
    }

    func clearHistory() {
        Task {
            do {
                try await historyStore.clearHistory()
                archiveState.clearHistory()
            } catch {
                presentedError = UserFacingError(message: "History could not be cleared: \(error.localizedDescription)")
            }
        }
    }

    func requestNotificationAuthorization() {
        Task {
            do {
                notificationsAuthorized = try await notificationManager.requestAuthorization()
            } catch {
                presentedError = UserFacingError(message: "Notification permission failed: \(error.localizedDescription)")
            }
        }
    }

    private func initialize() async {
        liveState.setAvailable(await reader.available)
        let storedLaunchAtLogin = await loginItemManager.isEnabled()
        if !userChangedLoginItem { launchAtLogin = storedLaunchAtLogin }
        notificationsAuthorized = await notificationManager.authorizationStatus() == .authorized
        let stored = await historyStore.load(
            retentionDays: settings.retentionDays,
            inMemoryDays: min(settings.retentionDays, maximumInMemoryHistoryDays),
            incidentRetentionDays: settings.incidentRetentionDays,
            maximumStoredIncidents: settings.maximumStoredIncidents
        )
        archiveState.replaceHistory(with: stored.samples)
        archiveState.replaceIncidents(with: stored.incidents)
        beginRefresh(priority: .utility)
    }

    private func performRefresh() async {
        guard let snapshot = await reader.capture() else {
            liveState.setAvailable(false)
            return
        }
        liveState.apply(snapshot)

        let now = Date.now
        let historyDue = lastHistoryAt.map {
            now.timeIntervalSince($0) >= settings.historyInterval
        } ?? true
        let incidentWasActive = isRecordingIncident && (incidentStartedAt ?? .distantFuture) <= now
        let processDue = lastProcessAt.map {
            now.timeIntervalSince($0) >= processInterval
        } ?? true

        if processDue && (historyDue || incidentWasActive) {
            cachedProcesses = await processSampler.capture()
            lastProcessAt = now
            cachedProcessSnapshotID = UUID()
            cachedProcessSampledAt = now
        }

        let sample = ThermalSample(
            snapshot: snapshot,
            processes: cachedProcesses,
            processSnapshotID: cachedProcessSnapshotID,
            processSampledAt: cachedProcessSampledAt,
            timestamp: now
        )
        if let reason = alertEvaluator.evaluate(
            sample: sample,
            configuration: settings.alertConfiguration,
            now: now
        ), notificationsAuthorized {
            await notificationManager.send(reason)
        }

        let automaticTransition = automaticIncidentDetector.evaluate(
            sample: sample,
            pressureEnabled: settings.autoRecordPressureIncidents,
            temperatureEnabled: settings.autoRecordTemperatureIncidents,
            thresholdCelsius: settings.alertThresholdCelsius,
            sustainedDuration: settings.sustainedAlertSeconds,
            recoveryDuration: settings.automaticIncidentRecoverySeconds,
            now: now
        )
        await handleAutomaticIncidentTransition(automaticTransition, now: now)

        let incidentIsActive = isRecordingIncident && (incidentStartedAt ?? .distantFuture) <= now
        if historyDue {
            archiveState.appendHistory(sample)
            trimInMemoryHistoryIfNeeded(now: now)
            lastHistoryAt = now
            do {
                try await historyStore.append(sample, retentionDays: settings.retentionDays)
            } catch {
                presentedError = UserFacingError(message: "History could not be saved: \(error.localizedDescription)")
            }
        }

        guard incidentIsActive else { return }
        incidentSamples.append(sample)
        incidentSampleCount = incidentSamples.count
        if activeIncidentJournalAvailable {
            do {
                try await historyStore.appendActiveIncident(sample)
            } catch {
                activeIncidentJournalAvailable = false
                presentedError = UserFacingError(message: "The active incident journal could not be saved: \(error.localizedDescription)")
            }
        }

        if let startedAt = incidentStartedAt,
           now.timeIntervalSince(startedAt) >= settings.maximumIncidentDuration {
            let trigger = recordingTrigger ?? .manual
            await stopIncidentRecording(endedAt: now)
            await startIncidentRecording(trigger: trigger, at: now, includesPreRoll: false)
        }
    }

    private func beginRefresh(priority: TaskPriority) {
        guard !refreshing else { return }
        timer?.invalidate()
        timer = nil
        refreshing = true

        Task(priority: priority) { [weak self] in
            guard let self else { return }
            await self.performRefresh()
            self.refreshing = false
            self.scheduleNextRefresh()
        }
    }

    private func scheduleNextRefresh() {
        timer?.invalidate()
        let interval = currentRefreshInterval
        let nextTimer = Timer(timeInterval: interval, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.beginRefresh(priority: .utility)
            }
        }
        nextTimer.tolerance = min(1.5, interval * 0.25)
        RunLoop.main.add(nextTimer, forMode: .common)
        timer = nextTimer
    }

    private func presentationDidChange(presented: Bool) {
        if presented {
            beginRefresh(priority: .utility)
        } else if !refreshing {
            scheduleNextRefresh()
        }
    }

    private var currentRefreshInterval: TimeInterval {
        let activityInterval: TimeInterval
        if isRecordingIncident || isElevated(liveState.menuBarSeverity) || isElevated(liveState.thermal.severity) {
            activityInterval = elevatedRefreshInterval
        } else if panelPresented || dashboardPresented {
            activityInterval = interactiveRefreshInterval
        } else {
            activityInterval = backgroundRefreshInterval
        }

        guard let lastHistoryAt else { return activityInterval }
        let historyRemaining = settings.historyInterval - Date.now.timeIntervalSince(lastHistoryAt)
        return min(activityInterval, max(0.5, historyRemaining))
    }

    private func isElevated(_ severity: Severity) -> Bool {
        switch severity {
        case .warn, .hot, .critical: true
        case .ok, .normal: false
        }
    }

    private func startIncidentRecording(
        trigger: ThermalIncidentTrigger,
        at date: Date,
        includesPreRoll: Bool = true
    ) async {
        guard !isRecordingIncident else { return }
        let preRoll = trigger.isAutomatic && includesPreRoll
            ? ThermalIncidentPreRoll.samples(
                from: history,
                endingAt: date,
                duration: automaticIncidentPreRoll
            )
            : []
        let startedAt = preRoll.first?.timestamp ?? date
        let id = UUID()
        let name = incidentName(trigger: trigger, startedAt: startedAt)
        incidentStartedAt = startedAt
        incidentSamples = preRoll
        incidentSampleCount = preRoll.count
        recordingTrigger = trigger
        activeIncidentID = id
        activeIncidentName = name
        isRecordingIncident = true
        do {
            try await historyStore.beginActiveIncident(
                id: id,
                name: name,
                startedAt: startedAt,
                trigger: trigger,
                samples: preRoll
            )
            activeIncidentJournalAvailable = true
        } catch {
            activeIncidentJournalAvailable = false
            presentedError = UserFacingError(message: "The incident journal could not be started: \(error.localizedDescription)")
        }
    }

    private func stopIncidentRecording(endedAt: Date = .now) async {
        isRecordingIncident = false
        guard let startedAt = incidentStartedAt, !incidentSamples.isEmpty else {
            resetActiveIncidentState()
            await historyStore.discardActiveIncident()
            return
        }

        let trigger = recordingTrigger ?? .manual
        let incident = ThermalIncident(
            id: activeIncidentID ?? UUID(),
            name: activeIncidentName ?? incidentName(trigger: trigger, startedAt: startedAt),
            startedAt: startedAt,
            endedAt: endedAt,
            samples: incidentSamples,
            trigger: trigger
        )
        archiveState.insertIncident(incident)
        pruneStoredIncidents(now: endedAt)
        resetActiveIncidentState()
        await persistIncidentsNow(clearActiveIncident: true)
    }

    private func handleAutomaticIncidentTransition(
        _ transition: AutomaticIncidentTransition?,
        now: Date
    ) async {
        switch transition {
        case .start(let trigger, _, _):
            await startIncidentRecording(trigger: trigger, at: now)
        case .stop:
            if recordingTrigger?.isAutomatic == true {
                await stopIncidentRecording(endedAt: now)
            }
        case nil:
            break
        }
    }

    private func scheduleIncidentPersistence() {
        incidentRevision += 1
        let revision = incidentRevision
        let value = incidents
        incidentPersistenceTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await historyStore.saveIncidents(value, revision: revision)
            } catch {
                presentedError = UserFacingError(message: "Incidents could not be saved: \(error.localizedDescription)")
            }
        }
    }

    private func persistIncidentsNow(clearActiveIncident: Bool) async {
        incidentRevision += 1
        let revision = incidentRevision
        do {
            try await historyStore.saveIncidents(
                incidents,
                revision: revision,
                clearActiveIncident: clearActiveIncident
            )
        } catch {
            presentedError = UserFacingError(message: "Incidents could not be saved: \(error.localizedDescription)")
        }
    }

    private func trimInMemoryHistoryIfNeeded(now: Date) {
        guard lastMemoryTrimAt.map({ now.timeIntervalSince($0) >= memoryTrimInterval }) ?? true else { return }
        lastMemoryTrimAt = now
        let retainedDays = min(settings.retentionDays, maximumInMemoryHistoryDays)
        let cutoff = Calendar.current.date(byAdding: .day, value: -retainedDays, to: now) ?? .distantPast
        archiveState.trimHistory(before: cutoff)
    }

    private func pruneStoredIncidents(now: Date) {
        let cutoff = Calendar.current.date(
            byAdding: .day,
            value: -settings.incidentRetentionDays,
            to: now
        ) ?? .distantPast
        archiveState.pruneIncidents(
            cutoff: cutoff,
            maximumCount: max(1, settings.maximumStoredIncidents)
        )
    }

    private func incidentName(trigger: ThermalIncidentTrigger, startedAt: Date) -> String {
        let prefix: String
        switch trigger {
        case .automaticThermalPressure: prefix = "Automatic pressure incident"
        case .automaticHighTemperature: prefix = "Automatic temperature incident"
        case .manual: prefix = "Thermal incident"
        }
        return "\(prefix) \(startedAt.formatted(date: .abbreviated, time: .shortened))"
    }

    private func resetActiveIncidentState() {
        incidentStartedAt = nil
        incidentSamples.removeAll(keepingCapacity: false)
        incidentSampleCount = 0
        recordingTrigger = nil
        activeIncidentID = nil
        activeIncidentName = nil
        activeIncidentJournalAvailable = false
    }

    func prepareForTermination() async {
        do {
            try await historyStore.flushActiveIncident()
        } catch {
            NSLog("macthermal: could not flush active incident: \(error.localizedDescription)")
        }
        await incidentPersistenceTask?.value
    }
}
