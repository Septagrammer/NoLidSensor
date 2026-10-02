import SwiftUI
import AppKit
import AVFoundation
import IOKit.pwr_mgt
import DarkSleepCore

final class Model: ObservableObject {
    @Published var enabled = false
    @Published var status = L("Off")
    @Published var brightness = L("Not measured yet")
    @Published var interval: Double { didSet { defaults.set(interval, forKey: "interval"); reset() } }
    @Published var threshold: Double { didSet { defaults.set(threshold, forKey: "threshold"); reset() } }
    @Published var snoozedUntil: Date
    @Published var promptVisible = false
    @Published var countdown = 60
    @Published var promptActivity = false
    private let defaults = UserDefaults.standard
    private let camera = CameraProbe()
    private var timer: Timer?
    private var generation = UUID()
    private var checking = false
    private var nextCheck = Date.distantFuture
    private var activityWindow = ActivityWindow()
    private var promptDeadline = 0.0
    private var promptUptime = 0.0
    private var promptIdle = 0.0
    private var sleeping = false
    private var inactiveSession = false
    private var suspended: Bool { sleeping || inactiveSession }
    private var observers: [NSObjectProtocol] = []
    var showPrompt: (() -> Void)?
    var closePrompt: (() -> Void)?

    private let authorizationStatus: () -> AVAuthorizationStatus
    private let requestAccess: (@escaping (Bool) -> Void) -> Void

    init(authorizationStatus: @escaping () -> AVAuthorizationStatus = { AVCaptureDevice.authorizationStatus(for: .video) },
         requestAccess: @escaping (@escaping (Bool) -> Void) -> Void = { AVCaptureDevice.requestAccess(for: .video, completionHandler: $0) }) {
        self.authorizationStatus = authorizationStatus
        self.requestAccess = requestAccess
        func number(_ key: String, _ fallback: Double, _ range: ClosedRange<Double>) -> Double {
            guard let n = UserDefaults.standard.object(forKey: key) as? Double, n.isFinite else { return fallback }
            return min(range.upperBound, max(range.lowerBound, n))
        }
        interval = number("interval", 3, 1...30)
        threshold = number("threshold", 3, 0.5...20)
        snoozedUntil = Date(timeIntervalSince1970: defaults.double(forKey: "snooze"))
        scheduleNextEvent()
        let center = NSWorkspace.shared.notificationCenter
        observers.append(center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            self?.sleeping = true; self?.reset()
        })
        observers.append(center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            self?.sleeping = false; self?.reset()
        })
        observers.append(center.addObserver(forName: NSWorkspace.sessionDidResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
            self?.inactiveSession = true; self?.reset()
        })
        observers.append(center.addObserver(forName: NSWorkspace.sessionDidBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            self?.inactiveSession = false; self?.reset()
        })
    }
    private var idle: Double { CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: .null) }
    private var eligible: Bool {
        !suspended && SleepPolicy.eligible(enabled: enabled, now: Date(), snoozedUntil: snoozedUntil, idle: idle, requiredIdle: activityWindow.requiredIdle(at: ProcessInfo.processInfo.systemUptime))
    }
    func setEnabled(_ value: Bool) {
        enabled = value; reset()
        guard value else { status = L("Off"); return }
        withCameraAccess { [weak self] granted in
            guard let self else { return }
            self.enabled = granted
            self.status = granted ? L("Waiting for inactivity") : L("Camera access denied. Allow it in macOS Settings.")
            self.scheduleNextEvent()
        }
    }
    private func withCameraAccess(_ completion: @escaping (Bool) -> Void) {
        switch authorizationStatus() {
        case .authorized: completion(true)
        case .notDetermined:
            checking = true
            scheduleNextEvent()
            status = L("Camera permission required")
            let token = generation
            requestAccess { [weak self] granted in
                DispatchQueue.main.async {
                    guard let self else { return }
                    guard self.generation == token else {
                        // Settings may have changed while the system permission dialog was open.
                        self.scheduleNextEvent()
                        return
                    }
                    self.checking = false
                    completion(granted)
                    self.scheduleNextEvent()
                }
            }
        default: completion(false)
        }
    }
    func reset() {
        generation = UUID(); checking = false; camera.cancel(); activityWindow = ActivityWindow()
        dismissPrompt(); nextCheck = Date().addingTimeInterval(interval * 60)
        scheduleNextEvent()
    }
    private func dismissPrompt() { promptVisible = false; closePrompt?() }
    func snooze() {
        snoozedUntil = Date().addingTimeInterval(3600)
        defaults.set(snoozedUntil.timeIntervalSince1970, forKey: "snooze")
        reset(); status = LF("Paused until %@", snoozedUntil.formatted(date: .omitted, time: .shortened))
    }
    func resume() { snoozedUntil = .distantPast; defaults.set(0, forKey: "snooze"); reset(); status = enabled ? L("Waiting for inactivity") : L("Off") }
    func skip() { reset(); status = L("Sleep skipped until the next check") }
    func testCamera() {
        guard !checking, !promptVisible, Date() >= snoozedUntil, !suspended else { return }
        withCameraAccess { [weak self] granted in
            guard let self else { return }
            guard granted else { self.status = L("Camera access denied. Allow it in macOS Settings."); return }
            self.probe(testOnly: true)
        }
    }
    private func scheduleNextEvent() {
        timer?.invalidate(); timer = nil
        guard let delay = EventSchedule.delay(enabled: enabled && authorizationStatus() == .authorized,
            suspended: suspended, checking: checking, prompt: promptVisible,
            snoozeRemaining: snoozedUntil.timeIntervalSinceNow, checkRemaining: nextCheck.timeIntervalSinceNow) else { return }
        let next = Timer(timeInterval: delay, repeats: false) { [weak self] _ in self?.tick() }
        next.tolerance = promptVisible ? 0.05 : min(5, delay * 0.05)
        RunLoop.main.add(next, forMode: .common)
        timer = next
    }
    private func tick() {
        defer { scheduleNextEvent() }
        if snoozedUntil > Date(timeIntervalSince1970: 0), Date() >= snoozedUntil {
            snoozedUntil = .distantPast
            defaults.set(0, forKey: "snooze")
            activityWindow = ActivityWindow()
            nextCheck = Date().addingTimeInterval(interval * 60)
            status = enabled ? L("Waiting for inactivity") : L("Off")
        }
        guard enabled, !suspended else { return }
        if Date() < snoozedUntil { return }
        if promptVisible {
            if !SleepPolicy.unchangedActivity(idleBefore: promptIdle, idleAfter: idle, elapsed: ProcessInfo.processInfo.systemUptime - promptUptime) {
                if !promptActivity { promptActivity = true }
            }
            let remaining = max(0, Int(ceil(promptDeadline - ProcessInfo.processInfo.systemUptime)))
            if countdown != remaining { countdown = remaining }
            if countdown == 0 {
                if !promptActivity { attemptSleep(explicit: false) } else { skip() }
            }
            return
        }
        guard !checking, Date() >= nextCheck else { return }
        nextCheck = Date().addingTimeInterval(interval * 60)
        let now = ProcessInfo.processInfo.systemUptime
        guard activityWindow.beginCheck(at: now) else {
            status = L("First check recorded. Waiting for the next check."); return
        }
        guard eligible else { status = L("Activity between checks. Waiting for a quiet interval."); return }
        probe(testOnly: false)
    }
    private func probe(testOnly: Bool) {
        checking = true; scheduleNextEvent(); status = L("Measuring light…")
        let token = generation, before = idle, started = ProcessInfo.processInfo.systemUptime
        camera.capture { [weak self] result in
            guard let self, token == self.generation else { return }
            defer { self.scheduleNextEvent() }
            self.checking = false
            self.nextCheck = Date().addingTimeInterval(self.interval * 60)
            switch result {
            case .failure(let error): self.status = error.localizedDescription
            case .success(let samples):
                let level = samples.reduce(0, +) / Double(samples.count) * 100
                self.brightness = String(format: "%.1f %%", level)
                let dark = SleepPolicy.dark(samples, threshold: self.threshold / 100)
                guard !testOnly else { self.status = dark ? L("Test: dark. Sleep was not requested.") : L("Test: bright. Sleep was not requested."); return }
                guard self.eligible, SleepPolicy.unchangedActivity(idleBefore: before, idleAfter: self.idle, elapsed: ProcessInfo.processInfo.systemUptime - started) else {
                    self.status = L("Check cancelled: activity detected"); return
                }
                guard dark else { self.status = L("Light detected, continuing to wait"); return }
                    self.promptVisible = true; self.countdown = 60; self.promptActivity = false
                    self.promptDeadline = ProcessInfo.processInfo.systemUptime + 60
                    self.promptIdle = self.idle; self.promptUptime = ProcessInfo.processInfo.systemUptime
                    self.status = L("Waiting for your response"); self.showPrompt?()
            }
        }
    }
    func confirmSleep() { guard promptVisible else { return }; attemptSleep(explicit: true) }
    private func attemptSleep(explicit: Bool) {
        guard enabled, !suspended, Date() >= snoozedUntil, explicit || eligible else { skip(); return }
        reset()
        let connection = IOPMFindPowerManagement(mach_port_t(MACH_PORT_NULL))
        guard connection != 0 else { status = L("Could not connect to power management"); return }
        let result = IOPMSleepSystem(connection)
        IOServiceClose(connection)
        status = result == kIOReturnSuccess ? L("Sleep request sent to macOS") : LF("macOS rejected sleep (%d)", result)
    }
}

struct MenuAction: View {
    let title: String
    let icon: String
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon).frame(width: 18).foregroundStyle(.secondary)
                Text(title).multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .padding(.vertical, 5)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
    }
}

struct SnoozeButton: View {
    @ObservedObject var model: Model
    var body: some View {
        MenuAction(title: model.snoozedUntil > Date() ? L("Resume") : L("Do not disturb for an hour"),
                   icon: model.snoozedUntil > Date() ? "play" : "moon.zzz") {
            if Date() < model.snoozedUntil { model.resume() } else { model.snooze() }
        }
    }
}

struct ThresholdControl: View {
    @ObservedObject var model: Model
    @State private var draft: Double
    init(model: Model) {
        self.model = model
        _draft = State(initialValue: model.threshold)
    }
    var body: some View {
        VStack(alignment: .leading) {
            Text(LF("Darkness threshold: %.1f %%", draft))
            Slider(value: $draft, in: 0.5...20, step: 0.5, onEditingChanged: { editing in
                if !editing && draft != model.threshold { model.threshold = draft }
            }).accessibilityLabel(L("Darkness threshold"))
        }
        .onChange(of: model.threshold) { draft = $0 }
        .onDisappear { if draft != model.threshold { model.threshold = draft } }
    }
}

struct MenuView: View {
    @ObservedObject var model: Model
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("NoLidSensor").font(.headline)
            Toggle(L("Enable monitoring"), isOn: Binding(get: { model.enabled }, set: model.setEnabled))
            Divider()
            Stepper(LF("Check every %d min", Int(model.interval)), value: $model.interval, in: 1...30)
            ThresholdControl(model: model)
            Text(L("Sleep requires darkness and no keyboard or mouse activity between two checks.")).font(.caption).foregroundStyle(.secondary)
            Text(L("Sleep after 60 seconds without a response")).font(.caption).foregroundStyle(.secondary)
            Divider()
            VStack(spacing: 6) {
                SnoozeButton(model: model)
                MenuAction(title: L("Test camera"), icon: "camera", action: model.testCamera)
                    .help(L("Measure light without sleeping"))
            }
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(L("Brightness")).foregroundStyle(.secondary)
                    Spacer()
                    Text(model.brightness).monospacedDigit()
                }
                Divider()
                Text(L("Status")).foregroundStyle(.secondary)
                Text(model.status).fixedSize(horizontal: false, vertical: true)
            }
            .font(.caption)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
            Divider()
            HStack {
                Spacer()
                Button(L("Quit")) { NSApp.terminate(nil) }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 4)
            }
        }.padding(16).frame(width: 320)
    }
}
struct PromptView: View {
    @ObservedObject var model: Model
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(L("Put your Mac to sleep?")).font(.title2.bold())
            Text(L("The camera sees darkness and there has been no keyboard or mouse input."))
            Text(!model.promptActivity ? LF("Sleeping in %d s", model.countdown) : LF("Prompt closes in %d s without sleeping", model.countdown)).monospacedDigit()
            HStack {
                Button(L("Do not disturb for an hour"), action: model.snooze)
                Button(L("Not now"), action: model.skip).keyboardShortcut(.cancelAction)
                Button(L("Sleep"), action: model.confirmSleep)
            }
        }.padding(24).frame(width: 480)
    }
}
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    let model = Model()
    var prompt: NSPanel!
    func applicationDidFinishLaunching(_ notification: Notification) {
        prompt = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 480, height: 210), styleMask: [.titled], backing: .buffered, defer: false)
        prompt.title = "NoLidSensor"; prompt.level = .floating; prompt.isReleasedWhenClosed = false
        prompt.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        prompt.contentView = NSHostingView(rootView: PromptView(model: model))
        model.showPrompt = { [weak self] in self?.prompt.center(); self?.prompt.makeKeyAndOrderFront(nil) }
        model.closePrompt = { [weak self] in self?.prompt.orderOut(nil) }
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationWillTerminate(_ notification: Notification) { model.setEnabled(false) }
}
@main struct DarkSleepApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    var body: some Scene {
        MenuBarExtra("NoLidSensor", systemImage: "moon.zzz") {
            MenuView(model: delegate.model)
        }.menuBarExtraStyle(.window)
    }
}
