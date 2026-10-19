import Foundation
import EarthCore

/// The UI owns a child backend, not an AIS connection or a long-lived key.
@MainActor final class LocalVesselStore {
    typealias State = VesselStore.State
    private(set) var state: State = .unconfigured
    private(set) var visible = [VesselSample]()
    private(set) var diagnostics: VesselServiceSnapshot?
    private var inventory = VesselInventory()
    private var active = false
    private var generation = UUID()
    private var process: Process?
    private var lifetime: Pipe?
    private var output: Pipe?
    private var parser = VesselServiceFrames()
    private var retry: Task<Void,Never>?
    private var watchdog: Timer?
    private var lastMessage = Date()
    private var lastSequence = -1
    private var attempts = 0
    private let executable: URL
    private let arguments: [String]
    private var authorizeNextStart = false
    private let retryDelay: TimeInterval
    var onChange: (() -> Void)?

    init(executable: URL = Bundle.main.executableURL!, arguments: [String] = ["--vessel-service"], retryDelay: TimeInterval = 2) {
        self.executable = executable; self.arguments = arguments; self.retryDelay = retryDelay
    }
    func authorizeSavedKey() {
        authorizeNextStart = true
        reload()
    }
    func reload() {
        stop(); clear()
        state = active ? .connecting:.paused; onChange?()
        if active { start() }
    }
    func setActive(_ value: Bool) {
        guard active != value else { return }
        active = value
        if value { start() } else {
            let wasUnconfigured = state == .unconfigured
            stop(); clear(); state = wasUnconfigured ? .unconfigured:.paused; onChange?()
        }
    }
    func sample(mmsi: String) -> VesselSample? { inventory.sample(mmsi:mmsi,at:Date()) }
    private func clear() { visible = []; inventory.clear(); diagnostics = nil }
    private func stop() {
        generation = UUID()
        retry?.cancel(); retry = nil
        watchdog?.invalidate(); watchdog = nil
        output?.fileHandleForReading.readabilityHandler = nil
        try? lifetime?.fileHandleForWriting.close()
        if let process, process.isRunning { process.terminate() }
        process = nil; lifetime = nil; output = nil; parser = VesselServiceFrames()
        lastSequence = -1
    }
    private func start() {
        guard active, process == nil else { return }
        let token = generation
        let child = Process(), input = Pipe(), output = Pipe()
        child.executableURL = executable
        child.arguments = authorizeNextStart && arguments == ["--vessel-service"] ? ["--vessel-service-authorize"] : arguments
        authorizeNextStart = false
        child.standardInput = input; child.standardOutput = output
        child.standardError = FileHandle.nullDevice
        self.process = child; lifetime = input; self.output = output
        lastMessage = Date()
        state = .connecting; onChange?()
        output.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            if data.isEmpty { handle.readabilityHandler = nil }
            Task { @MainActor in self?.receive(data,token:token) }
        }
        child.terminationHandler = { [weak self] _ in
            Task { @MainActor in self?.failed(token:token) }
        }
        do {
            try child.run()
            watchdog = Timer.scheduledTimer(withTimeInterval:2,repeats:true) { [weak self] _ in
                Task { @MainActor in
                    guard let self, self.generation == token else { return }
                    // A hung helper must not leave the UI falsely connected.
                    if Date().timeIntervalSince(self.lastMessage) > 45 { self.failed(token:token); return }
                    let fresh = self.visible.filter { $0.usable(at:Date()) }
                    if fresh != self.visible { self.visible = fresh; self.onChange?() }
                }
            }
        } catch { failed(token:token) }
    }
    private func receive(_ data: Data, token: UUID) {
        guard active, generation == token else { return }
        guard !data.isEmpty else { failed(token:token); return }
        do {
            for frame in try parser.append(data) {
                let snapshot = try JSONDecoder().decode(VesselServiceSnapshot.self,from:frame)
                let samples = try snapshot.validated(at:Date())
                guard snapshot.sequence > lastSequence else { continue }
                lastSequence = snapshot.sequence
                lastMessage = Date()
                if snapshot.state == .connected { attempts = 0 }
                diagnostics = snapshot; state = snapshot.state
                if [.unconfigured,.paused,.rejected,.credentialUnavailable].contains(state) {
                    clear()
                } else {
                    for sample in samples { inventory.merge(sample,at:Date()) }
                    // Preserve the backend's exact subset, with freshness filtering only.
                    visible = samples
                }
                onChange?()
            }
        } catch { failed(token:token) }
    }
    private func failed(token: UUID) {
        guard active, generation == token else { return }
        stop(); clear(); state = .retrying; onChange?()
        attempts = min(attempts+1,5)
        let delay = min(30,retryDelay*pow(2,Double(attempts-1)))
        let next = generation
        retry = Task { [weak self] in
            do { try await Task.sleep(nanoseconds:UInt64(max(0.01,delay)*1_000_000_000)) } catch { return }
            guard let self, self.active, self.generation == next else { return }
            self.retry = nil; self.start()
        }
    }
}
