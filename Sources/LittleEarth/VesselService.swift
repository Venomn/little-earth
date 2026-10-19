import Foundation
import EarthCore
import Darwin

/// Only typed, bounded public ship data crosses the private pipe. Never send
/// provider frames, errors, subscriptions, or credentials to the UI process.
struct VesselServiceSnapshot: Codable {
    let version: Int
    let sequence: Int
    let state: VesselStore.State
    let vessels: [VesselSample]
    let receivedFrames: Int
    let acceptedReports: Int
    let compressionEnabled: Bool?
    @MainActor init(store: VesselStore, sequence: Int) {
        version = 1; self.sequence = sequence; state = store.state; vessels = store.visible
        receivedFrames = store.receivedFrames; acceptedReports = store.acceptedReports
        compressionEnabled = store.compressionEnabled
    }
    func validated(at date: Date) throws -> [VesselSample] {
        guard version == 1, sequence >= 0, vessels.count <= 48, receivedFrames >= 0, acceptedReports >= 0,
              Set(vessels.map(\.mmsi)).count == vessels.count else { throw VesselServiceError.invalidMessage }
        return vessels.filter { $0.usable(at:date) }
    }
}

enum VesselServiceError: Error { case invalidMessage, terminated }

/// Newline framing is bounded even when a child emits partial or corrupt data.
struct VesselServiceFrames {
    private var pending = Data()
    mutating func append(_ data: Data) throws -> [Data] {
        guard data.count <= 1_048_576 else { throw VesselServiceError.invalidMessage }
        pending.append(data)
        var frames = [Data]()
        while let end = pending.firstIndex(of:10) {
            guard pending.distance(from:pending.startIndex,to:end) <= 65_536 else { throw VesselServiceError.invalidMessage }
            frames.append(Data(pending[..<end])); pending.removeSubrange(...end)
        }
        guard pending.count <= 65_536 else { throw VesselServiceError.invalidMessage }
        return frames
    }
}

/// Run before NSApplication is created. This process owns the upstream socket
/// and exits on stdin EOF, including when its parent crashes or quits.
@MainActor func runVesselService(allowInteraction: Bool = false) -> Never {
    signal(SIGPIPE,SIG_IGN)
    let store = VesselStore()
    var sequence = 0
    store.onChange = {
        do {
            sequence += 1
            var data = try JSONEncoder().encode(VesselServiceSnapshot(store:store,sequence:sequence))
            data.append(10)
            try FileHandle.standardOutput.write(contentsOf:data)
        } catch { exit(0) }
    }
    // A private lifetime pipe, not a command channel: no key in argv or stdin.
    Thread.detachNewThread {
        while let data = try? FileHandle.standardInput.read(upToCount:1), !data.isEmpty {}
        exit(0)
    }
    store.beginCredentialRead()
    Task {
        do {
            // A system credential prompt must not block the heartbeat or look like
            // a crashed backend while the user is responding to macOS.
            let key = try await Task.detached { try VesselKeychain.read(allowInteraction:allowInteraction) }.value
            store.configure(key:key)
            store.setActive(true)
        } catch {
            let status = (error as? VesselKeychain.ReadError)?.status ?? -1
            fputs("AIS Keychain read failed (OSStatus \(status)).\n",stderr)
            store.credentialReadFailed()
        }
    }
    let heartbeat = Timer.scheduledTimer(withTimeInterval:10,repeats:true) { _ in
        MainActor.assumeIsolated { store.onChange?() }
    }
    _ = heartbeat
    RunLoop.main.run()
    exit(0)
}
