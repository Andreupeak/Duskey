import AppKit
import Combine

@MainActor
final class AutoBacklightController: NSObject, ObservableObject {
    static let shared = AutoBacklightController()

    private struct HardwareOutput: Equatable {
        let brightness: Float
        let ambient: Bool
    }

    private struct Target {
        let output: HardwareOutput
        let status: String
        let periodName: String?
        let night: Bool

        init(_ decision: BacklightDecision) {
            // Seed visible brightness before handing control to the ambient sensor.
            output = HardwareOutput(brightness: Float(decision.ambient
                ? max(decision.brightness, 0.08) : decision.brightness), ambient: decision.ambient)
            status = decision.status
            periodName = decision.periodName
            night = decision.night
        }
    }

    private struct PolicySnapshot {
        let normal: Target
        let idle: Target
        let timeout: TimeInterval?
        let calculatedAt: Date
        let refreshAt: Date
    }

    private let keyboard = KeyboardBacklightManager.shared
    private let sun = SunScheduleManager.shared
    private let prefs = Preferences.shared
    private var evaluationTimer: Timer?
    private var isMonitoring = false
    private var policy: PolicySnapshot?
    private var previewUntilUptime: TimeInterval?
    private var previewBrightnessApplied: Float?
    private var previewAmbientDisabled = false
    private var cancellables = Set<AnyCancellable>()
    private var inactivity = InactivityState()
    private var launchUptime = ProcessInfo.processInfo.systemUptime
    private var lastAppliedOutput: HardwareOutput?
    private var retryOutput: HardwareOutput?
    private var retryAfterUptime: TimeInterval?
    private var retryDelay: TimeInterval = 0.5
    private var originalBrightness: Float?
    private var originalAmbient: Bool?
    private var didCaptureHardware = false

    @Published private(set) var currentStatus = "Starting…"
    @Published private(set) var isNightMode = false
    @Published private(set) var keyboardAvailable = false
    @Published private(set) var activePeriodName: String?

    override private init() {
        super.init()
        prefs.objectWillChange
            .debounce(for: .milliseconds(200), scheduler: RunLoop.main)
            .sink { [weak self] _ in self?.evaluateAndApply() }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .NSSystemTimeZoneDidChange)
            .merge(with: NotificationCenter.default.publisher(for: .NSSystemClockDidChange))
            .merge(with: NotificationCenter.default.publisher(for: NSLocale.currentLocaleDidChangeNotification))
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.sun.refreshSolarTimesIfNeeded(force: true)
                self?.evaluateAndApply()
            }
            .store(in: &cancellables)

        NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.willSleepNotification)
            .sink { [weak self] _ in self?.suspendMonitoring() }
            .store(in: &cancellables)
        NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didWakeNotification)
            .sink { [weak self] _ in self?.startMonitoring() }
            .store(in: &cancellables)
    }

    func startMonitoring() {
        let available = AppRuntime.isUITesting || keyboard.load()
        if keyboardAvailable != available { keyboardAvailable = available }
        guard available else {
            suspendMonitoring()
            setStatus("No keyboard backlight")
            return
        }
        if !didCaptureHardware, !AppRuntime.isUITesting {
            originalBrightness = keyboard.currentBrightness
            originalAmbient = keyboard.isAutoBrightnessEnabled
            didCaptureHardware = true
            launchUptime = ProcessInfo.processInfo.systemUptime
        }
        isMonitoring = true
        lastAppliedOutput = nil
        clearRetry()
        if evaluationTimer == nil {
            // Move one timer's fire date in place. Common run-loop modes retain
            // monitoring during native menu tracking, without a Task per tick.
            // The repeating interval is a fallback; every callback rearms it.
            let timer = Timer(timeInterval: 86_400, target: self,
                              selector: #selector(scheduledEvaluationFired(_:)), userInfo: nil, repeats: true)
            timer.fireDate = .distantFuture
            evaluationTimer = timer
            RunLoop.main.add(timer, forMode: .common)
        }
        sun.refreshSolarTimesIfNeeded(force: true)
        evaluateAndApply()
    }

    private func suspendMonitoring() {
        isMonitoring = false
        evaluationTimer?.invalidate()
        evaluationTimer = nil
        endPreview()
        policy = nil
        lastAppliedOutput = nil
        clearRetry()
        sun.cancelPendingRequests()
    }

    func stopMonitoring() {
        suspendMonitoring()
        // Restore the state captured before Duskey took control, on a normal quit.
        if let originalBrightness {
            keyboard.setAutoBrightnessEnabled(false)
            keyboard.setBrightness(originalBrightness)
        }
        if let originalAmbient { keyboard.setAutoBrightnessEnabled(originalAmbient) }
    }

    /// Explicit settings/location changes invalidate the cached policy. Timer
    /// callbacks reuse it until a minute, solar event, or day actually changes.
    func evaluateAndApply() {
        evaluate(forcePolicyRefresh: true)
    }

    @objc private func scheduledEvaluationFired(_ timer: Timer) {
        guard timer === evaluationTimer, isMonitoring else {
            timer.invalidate()
            return
        }
        timer.fireDate = .distantFuture
        autoreleasepool { evaluate(forcePolicyRefresh: false) }
    }

    private func evaluate(forcePolicyRefresh: Bool) {
        // Preference/location callbacks must never restart hardware work in sleep.
        guard isMonitoring, keyboardAvailable else { return }
        let now = Date()
        let uptime = ProcessInfo.processInfo.systemUptime
        let policyExpired = policy.map { now >= $0.refreshAt || now < $0.calculatedAt } ?? true
        if forcePolicyRefresh || policyExpired {
            refreshPolicy(at: now)
        }
        guard let policy else { return }
        var idleSeconds: TimeInterval?
        if policy.timeout != nil || inactivity.isOff {
            // kCGAnyInputEventType is ~0; no event contents or event taps are used.
            let idle = AppRuntime.isUITesting ? 0
                : CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: .init(rawValue: ~0)!)
            idleSeconds = idle
            inactivity.update(idleSeconds: idle, timeout: policy.timeout,
                              withinGracePeriod: uptime - launchUptime < 10)
        }
        if let until = previewUntilUptime, uptime >= until || inactivity.isOff {
            endPreview()
        }
        if previewUntilUptime == nil {
            apply(inactivity.isOff ? policy.idle : policy.normal, uptime: uptime)
        }
        scheduleNextEvaluation(policy: policy, now: now, uptime: uptime, idleSeconds: idleSeconds)
    }

    private func refreshPolicy(at now: Date) {
        sun.refreshSolarTimesIfNeeded(at: now)
        let settings = prefs.automationSettings
        var minute = 0
        var refreshAt = sun.nextSolarRefresh
        if settings.periodic {
            if let transition = sun.nextTransition(after: now) {
                refreshAt = min(refreshAt, transition)
            }
            if settings.tab == 1 {
                let calendar = Calendar.current
                let components = calendar.dateComponents([.hour, .minute], from: now)
                minute = (components.hour ?? 0) * 60 + (components.minute ?? 0)
                // Minute boundaries preserve local-time and repeated-hour/DST
                // semantics without rebuilding/validating every half second.
                let nextMinute = calendar.dateInterval(of: .minute, for: now)?.end
                    ?? now.addingTimeInterval(60)
                refreshAt = min(refreshAt, nextMinute)
            }
        }
        let decision = AutomationPolicy.decision(settings: settings, minute: minute,
                                                  isNight: sun.isNighttime(at: now))
        var idleDecision = decision
        idleDecision.brightness = 0
        idleDecision.ambient = false
        idleDecision.statusOverride = "Idle Timeout • " + decision.status
        policy = PolicySnapshot(normal: Target(decision), idle: Target(idleDecision),
                                timeout: AutomationPolicy.idleTimeout(settings: settings, minute: minute),
                                calculatedAt: now, refreshAt: refreshAt)
    }

    private func scheduleNextEvaluation(policy: PolicySnapshot, now: Date,
                                        uptime: TimeInterval, idleSeconds: TimeInterval?) {
        var delay = max(0.05, policy.refreshAt.timeIntervalSince(now))
        if inactivity.isOff {
            // Only an idle keyboard needs frequent checks for actual input.
            delay = min(delay, 0.5)
        } else if let timeout = policy.timeout {
            if let idleSeconds, idleSeconds.isFinite, idleSeconds >= 0 {
                let graceRemaining = max(0, 10 - (uptime - launchUptime))
                // Input can only postpone the idle deadline. Re-read the counter
                // at the earliest possible timeout, then move the deadline back.
                delay = min(delay, max(0.05, max(graceRemaining, timeout - idleSeconds)))
            } else {
                delay = min(delay, 0.5)
            }
        }
        if let until = previewUntilUptime { delay = min(delay, max(0.05, until - uptime)) }
        if let retryAfterUptime { delay = min(delay, max(0.05, retryAfterUptime - uptime)) }
        // Hardware IPC may have taken time since the sample. Do not add that
        // processing time to preview or inactivity deadlines.
        let elapsed = max(0, ProcessInfo.processInfo.systemUptime - uptime)
        let remaining = max(0.01, delay - elapsed)
        evaluationTimer?.tolerance = min(0.1, remaining * 0.1)
        evaluationTimer?.fireDate = Date().addingTimeInterval(remaining)
    }

    func previewBrightness(_ value: Double) {
        guard isMonitoring, keyboardAvailable else { return }
        let brightness = Float(AutomationPolicy.clampBrightness(value))
        previewUntilUptime = ProcessInfo.processInfo.systemUptime + 3
        lastAppliedOutput = nil
        clearRetry()
        if !previewAmbientDisabled {
            previewAmbientDisabled = AppRuntime.isUITesting || keyboard.setAutoBrightnessEnabled(false)
        }
        let applied = previewBrightnessApplied == brightness
            || AppRuntime.isUITesting || keyboard.setBrightness(brightness)
        previewBrightnessApplied = applied ? brightness : nil
        setStatus(previewAmbientDisabled && applied
            ? BacklightDecision(brightness: Double(brightness), label: "Preview").status
            : "Keyboard control failed")
        evaluate(forcePolicyRefresh: false)
    }

    private func endPreview() {
        previewUntilUptime = nil
        previewBrightnessApplied = nil
        previewAmbientDisabled = false
    }

    private func apply(_ target: Target, uptime: TimeInterval) {
        if target.output != lastAppliedOutput, !AppRuntime.isUITesting {
            if retryOutput == target.output, let retryAfterUptime, uptime < retryAfterUptime { return }
            // A partially successful write invalidates the previously known
            // hardware state, even if the next decision returns to that output.
            lastAppliedOutput = nil
            let disabledAmbient = keyboard.setAutoBrightnessEnabled(false)
            let appliedBrightness = keyboard.setBrightness(target.output.brightness)
            let appliedAmbient = target.output.ambient ? keyboard.setAutoBrightnessEnabled(true) : true
            guard disabledAmbient && appliedBrightness && appliedAmbient else {
                // Retain retries after transient failures without hammering a
                // failing private hardware service twice a second indefinitely.
                retryDelay = retryOutput == target.output ? min(retryDelay * 2, 30) : 0.5
                retryOutput = target.output
                retryAfterUptime = uptime + retryDelay
                setStatus("Keyboard control failed")
                return
            }
        }
        lastAppliedOutput = target.output
        clearRetry()
        if activePeriodName != target.periodName { activePeriodName = target.periodName }
        if isNightMode != target.night { isNightMode = target.night }
        setStatus(target.status)
    }

    private func clearRetry() {
        retryOutput = nil
        retryAfterUptime = nil
        retryDelay = 0.5
    }

    private func setStatus(_ status: String) {
        if currentStatus != status { currentStatus = status }
    }
}
