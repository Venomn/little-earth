import Foundation
import EarthCore

protocol AISConnection: Sendable {
    func send(_ data: Data) async throws
    func receive() async throws -> Data
    func ping() async throws
    func close() async
}

private final class NetworkAISConnection: AISConnection, @unchecked Sendable {
    private let task: URLSessionWebSocketTask
    init() {
        task = URLSession.shared.webSocketTask(with:URL(string:"wss://stream.aisstream.io/v0/stream")!)
        task.maximumMessageSize = 65_536
        task.resume()
    }
    func send(_ data: Data) async throws { try await task.send(.data(data)) }
    func receive() async throws -> Data {
        switch try await task.receive() {
        case .data(let data): return data
        case .string(let text): return Data(text.utf8)
        @unknown default: throw URLError(.cannotParseResponse)
        }
    }
    func ping() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void,Error>) in
            task.sendPing { error in
                if let error { continuation.resume(throwing:error) } else { continuation.resume() }
            }
        }
    }
    func close() async { task.cancel(with:.goingAway,reason:nil) }
}

@MainActor final class VesselStore {
    enum State: String, Codable, Equatable { case unconfigured, paused, connecting, connected, retrying, rejected, credentialUnavailable }
    private(set) var state: State = .unconfigured
    private(set) var visible = [VesselSample]()
    private(set) var receivedFrames = 0
    private(set) var acceptedReports = 0
    private(set) var compressionEnabled: Bool?
    private var inventory = VesselInventory()
    private var key: String?
    private var active = false
    private var generation = UUID()
    private var task: Task<Void,Never>?
    private var connection: (any AISConnection)?
    private var timer: Timer?
    private let connectionFactory: () -> any AISConnection
    private let confirmationTimeout: TimeInterval
    var onChange: (() -> Void)?
    var configured: Bool { key != nil }
    init(confirmationTimeout: TimeInterval = 15, connectionFactory: @escaping () -> any AISConnection = { NetworkAISConnection() }) {
        self.connectionFactory = connectionFactory
        self.confirmationTimeout = confirmationTimeout
    }
    func configure(key: String?) {
        stop()
        self.key = key?.trimmingCharacters(in:.whitespacesAndNewlines)
        if self.key?.isEmpty == true { self.key = nil }
        inventory.clear(); visible = []
        receivedFrames = 0; acceptedReports = 0; compressionEnabled = nil
        state = self.key == nil ? .unconfigured:.paused
        onChange?()
        start()
    }
    func beginCredentialRead() {
        state = .connecting
        onChange?()
    }
    func credentialReadFailed() {
        stop(); key = nil
        inventory.clear(); visible = []
        receivedFrames = 0; acceptedReports = 0; compressionEnabled = nil
        state = .credentialUnavailable
        onChange?()
    }
    func setActive(_ value: Bool) {
        guard active != value else { return }
        active = value
        if value { start() } else {
            stop(); inventory.clear(); visible = []
            state = key == nil ? .unconfigured:.paused; onChange?()
        }
    }
    func sample(mmsi: String) -> VesselSample? { inventory.sample(mmsi:mmsi,at:Date()) }
    private func stop() {
        generation = UUID(); task?.cancel(); task = nil
        if let connection { Task { await connection.close() } }; connection = nil
        timer?.invalidate(); timer = nil
    }
    private func publish() {
        visible = inventory.visible(at:Date())
        onChange?()
    }
    private func start() {
        guard active, let key, task == nil else { return }
        let token = generation
        timer = Timer.scheduledTimer(withTimeInterval:2,repeats:true) { [weak self] _ in
            Task { @MainActor in self?.publish() }
        }
        task = Task { [weak self] in
            var attempt = 0
            while let self, !Task.isCancelled, self.generation == token {
                self.state = .connecting; self.onChange?()
                self.compressionEnabled = nil
                let connection = self.connectionFactory()
                self.connection = connection
                let confirmationDeadline = Task { [weak self] in
                    do {
                        try await Task.sleep(nanoseconds:UInt64(max(0.001,self?.confirmationTimeout ?? 15)*1_000_000_000))
                        guard let self, !Task.isCancelled, self.generation == token, self.state == .connecting else { return }
                        await connection.close()
                    } catch {}
                }
                let keepAlive = Task {
                    do {
                        while !Task.isCancelled {
                            try await Task.sleep(nanoseconds:30_000_000_000)
                            try await connection.ping()
                        }
                    } catch { await connection.close() }
                }
                do {
                    let subscription: [String:Any] = ["APIKey":key,"BoundingBoxes":[[[-90.0,-180.0],[90.0,180.0]]],"FilterMessageTypes":["PositionReport","StandardClassBPositionReport","ExtendedClassBPositionReport"]]
                    try await connection.send(JSONSerialization.data(withJSONObject:subscription))
                    while !Task.isCancelled {
                        let data = try await connection.receive()
                        guard !Task.isCancelled, self.generation == token else { break }
                        self.receivedFrames += 1
                        if let frame = try? JSONSerialization.jsonObject(with:data) as? [String:Any], frame["MessageType"] as? String == "SubscriptionConfirmation" {
                            self.compressionEnabled = (frame["Message"] as? [String:Any])?["CompressionEnabled"] as? Bool
                            confirmationDeadline.cancel()
                            self.state = .connected; attempt = 0; self.onChange?()
                        }
                        do {
                            if let sample = try AISParser.parse(data,receivedAt:Date()) {
                                self.inventory.merge(sample,at:Date())
                                self.acceptedReports += 1
                            }
                        } catch AISParseError.serviceRejected { throw AISParseError.serviceRejected }
                        catch { /* A malformed position cannot invalidate other vessels. */ }
                    }
                } catch {
                    guard !Task.isCancelled, self.generation == token else {
                        confirmationDeadline.cancel(); keepAlive.cancel(); await connection.close(); return
                    }
                    if error as? AISParseError == .serviceRejected {
                        self.state = .rejected; self.inventory.clear(); self.visible = []
                        self.onChange?(); confirmationDeadline.cancel(); keepAlive.cancel(); await connection.close()
                        guard !Task.isCancelled, self.generation == token else { return }
                        self.timer?.invalidate(); self.timer = nil; self.task = nil; self.connection = nil
                        return
                    }
                    self.state = .retrying; self.onChange?()
                }
                confirmationDeadline.cancel(); keepAlive.cancel(); await connection.close()
                guard !Task.isCancelled, self.generation == token else { return }
                self.connection = nil
                attempt = min(attempt+1,6)
                let delay = min(60.0,pow(2.0,Double(attempt))) + Double.random(in:0...1)
                do { try await Task.sleep(nanoseconds:UInt64(delay*1_000_000_000)) } catch { return }
            }
        }
    }
}
