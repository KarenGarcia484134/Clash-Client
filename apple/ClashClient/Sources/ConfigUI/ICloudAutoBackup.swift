import CryptoKit
import Foundation
#if os(macOS)
import Security
#endif
import ClashClientKit

 
 
 
 
 
 
 
 
 
 
 
 
 
@MainActor
final class ICloudAutoBackup: ObservableObject {
    static let keepUpToDateKey = "clash.backup.autoKeepUpToDate"
    static let lastHashKey = "clash.backup.autoLastHash"
    static let lastExportedAtKey = "clash.backup.autoLastExportedAt"
    static let debounceSeconds: TimeInterval = 60

     
     
    struct Collected: Sendable {
        let data: Data
        let leftOut: [String]
    }

    struct Dependencies {
         
         
         
        var collect: @Sendable () throws -> Collected
        var sink: any BackupRecordSink
        var installID: @Sendable () -> String
        var sourceDevice: @Sendable () -> String
        var now: @Sendable () -> Date = { Date() }
        var sleep: @Sendable (TimeInterval) async throws -> Void = { seconds in
            try await Task.sleep(nanoseconds: UInt64(max(0, seconds) * 1_000_000_000))
        }
        var debounce: TimeInterval = ICloudAutoBackup.debounceSeconds
        var log: @Sendable (String) -> Void = { _ in }
    }

     
    enum Outcome: Equatable {
        case exported(Date)
        case unchanged
        case waitingForNetwork
        case waitingForServer(seconds: Double)
        case noAccount
        case storageFull
        case failed(String)
    }

    @Published private(set) var isEnabled: Bool
    @Published private(set) var lastExportedAt: Date?
    @Published private(set) var outcome: Outcome?
    @Published private(set) var isExporting = false
     
     
    @Published private(set) var leftOutProfiles: [String] = []
    private(set) var isForeground = true
    private(set) var hasPendingChange = false

    private let defaults: UserDefaults
    private let deps: Dependencies
    private var debounceTask: Task<Void, Never>?
    private var observers: [NSObjectProtocol] = []

    init(defaults: UserDefaults, dependencies: Dependencies) {
        self.defaults = defaults
        self.deps = dependencies
        isEnabled = defaults.bool(forKey: Self.keepUpToDateKey)
        lastExportedAt = defaults.object(forKey: Self.lastExportedAtKey) as? Date
    }

    static let shared: ICloudAutoBackup = {
        let defaults = GlobalConfig.appGroupDefaults
         
         
         
         
         
         
         
        let sink: any BackupRecordSink
        if ICloudAutoBackup.processHasICloudEntitlement {
            let cloud = CloudKitBackupRecordSink(containerIdentifier: ClashAppIdentifiers.iCloudContainer)
            cloud.diagnostics = { ClashLogStore.shared.append($0, stream: .app) }
            sink = cloud
        } else {
            sink = UnentitledBackupRecordSink()
        }
        return ICloudAutoBackup(
            defaults: defaults,
            dependencies: Dependencies(
                collect: {
                    guard let container = ClashAppIdentifiers.appGroupContainer else {
                        throw BackupRecordSinkError.unavailable("The shared container is unavailable.")
                    }
                    let archive = try BackupArchive.collect(
                        workingDir: container.appendingPathComponent("working"),
                        leavingOutIncompleteProfiles: true
                    )
                    return Collected(data: try archive.encoded(), leftOut: archive.leftOutProfileLabels)
                },
                sink: sink,
                installID: { BackupArchive.autoInstallID(defaults: defaults) },
                sourceDevice: { BackupArchive.localDeviceName() },
                log: { ClashLogStore.shared.append($0, stream: .app) }
            )
        )
    }()

     
     
     
     
     
     
     
     
    static var processHasICloudEntitlement: Bool {
        #if os(macOS)
        guard let task = SecTaskCreateFromSelf(nil) else { return false }
        func strings(_ key: String) -> [String] {
            let value = SecTaskCopyValueForEntitlement(task, key as CFString, nil)
            if let list = value as? [String] { return list }
            if let one = value as? String { return [one] }
            return []
        }
        return strings("com.apple.developer.icloud-services").contains("CloudKit")
            && strings("com.apple.developer.icloud-container-identifiers")
                .contains(ClashAppIdentifiers.iCloudContainer)
        #else
        return Self.provisioningAllowsCloudKit(
            Bundle.main.url(forResource: "embedded", withExtension: "mobileprovision")
                .flatMap { try? Data(contentsOf: $0) }
        )
        #endif
    }

    /// iOS cannot read its own entitlements, but a sideloaded or developer
    /// build carries an `embedded.mobileprovision` whose `Entitlements` are a
    /// superset of what the binary was signed with. When the profile grants no
    /// CloudKit (e.g. a free Apple ID re-sign), `CKContainer(identifier:)`
    /// traps, so the backup must fall back to the unentitled sink. No profile
    /// (App Store, TrollStore) keeps the previous behaviour.
    static func provisioningAllowsCloudKit(_ profile: Data?) -> Bool {
        guard let profile else { return true }
        guard let start = profile.range(of: Data("<?xml".utf8)),
              let end = profile.range(of: Data("</plist>".utf8), in: start.lowerBound..<profile.endIndex),
              let plist = try? PropertyListSerialization.propertyList(
                  from: profile.subdata(in: start.lowerBound..<end.upperBound), format: nil
              ) as? [String: Any],
              let entitlements = plist["Entitlements"] as? [String: Any]
        else { return false }
        func strings(_ key: String) -> [String] {
            if let list = entitlements[key] as? [String] { return list }
            if let one = entitlements[key] as? String { return [one] }
            return []
        }
        let wanted = ClashAppIdentifiers.iCloudContainer
        let containerAllowed = strings("com.apple.developer.icloud-container-identifiers").contains { id in
            id == wanted || (id.hasSuffix("*") && wanted.hasPrefix(String(id.dropLast())))
        }
        return strings("com.apple.developer.icloud-services").contains { $0 == "CloudKit" || $0 == "*" }
            && containerAllowed
    }

     
     
     
     
     
    static let dirtySignals: [Notification.Name] = [
        ProfileStore.didChangeNotification, .clashProfileSelectionDidChange,
        GlobalConfig.didChangeNotification, ScriptLibrary.didChange,
    ]

     
     
     
     
    func start() {
        guard observers.isEmpty else { return }
        let center = NotificationCenter.default
        for name in Self.dirtySignals {
            observers.append(center.addObserver(forName: name, object: nil, queue: nil) { [weak self] _ in
                Task { @MainActor [weak self] in self?.noteChange() }
            })
        }
         
         
        let appGroup = ClashAppIdentifiers.appGroupContainer.map(ModuleStore.normalized)
        observers.append(center.addObserver(forName: ModuleStore.didChange, object: nil, queue: nil) { [weak self] note in
            guard let appGroup, (note.object as? URL).map(ModuleStore.normalized) == appGroup else { return }
            Task { @MainActor [weak self] in self?.noteChange() }
        })
    }

     
     
     
     
    @discardableResult
    func enable() async -> Outcome? {
        isEnabled = true
        defaults.set(true, forKey: Self.keepUpToDateKey)
        hasPendingChange = true
        debounceTask?.cancel()
        debounceTask = nil
        await exportNow()
        if outcome == .noAccount {
            isEnabled = false
            defaults.set(false, forKey: Self.keepUpToDateKey)
            hasPendingChange = false
        }
        return outcome
    }

     
     
     
    func disable() async {
        isEnabled = false
        defaults.set(false, forKey: Self.keepUpToDateKey)
        debounceTask?.cancel()
        debounceTask = nil
        hasPendingChange = false
        defaults.removeObject(forKey: Self.lastHashKey)
        defaults.removeObject(forKey: Self.lastExportedAtKey)
        lastExportedAt = nil
        outcome = nil
        let sink = deps.sink
        let installID = deps.installID()
        do {
            try await Task.detached(priority: .utility) { try await sink.deleteOwn(installID: installID) }.value
            deps.log("icloud auto backup: record removed (\(installID))")
        } catch {
            deps.log("icloud auto backup: record not removed: \(error)")
            outcome = .failed(Self.sentence(for: error))
        }
    }

    private static func sentence(for error: Error) -> String {
        if let sink = error as? BackupRecordSinkError {
            switch sink {
            case .noAccount: return "Not signed in to iCloud."
            case .offline(let text), .unavailable(let text): return text
            case .quotaExceeded: return "iCloud storage is full."
            case .rateLimited(let seconds): return "iCloud asked to wait \(Int(seconds.rounded())) s."
            }
        }
        return error.localizedDescription
    }

     
     
    func setForeground(_ foreground: Bool) {
        isForeground = foreground
        if foreground {
            if isEnabled, hasPendingChange { schedule(after: deps.debounce) }
        } else {
            debounceTask?.cancel()
            debounceTask = nil
        }
    }

     
     
    func noteChange() {
        guard isEnabled else { return }
        hasPendingChange = true
        if isForeground { schedule(after: deps.debounce) }
    }

    private func schedule(after seconds: TimeInterval) {
        debounceTask?.cancel()
        let sleep = deps.sleep
        debounceTask = Task { @MainActor [weak self] in
            do { try await sleep(seconds) } catch { return }
            guard !Task.isCancelled, let self else { return }
            await self.exportNow()
        }
    }

     
     
    func exportNow() async {
        guard isEnabled, !isExporting else { return }
        isExporting = true
        defer { isExporting = false }
        hasPendingChange = false
        let collect = deps.collect
        let data: Data
        do {
            let collected = try await Task.detached(priority: .utility) { try collect() }.value
            data = collected.data
            leftOutProfiles = collected.leftOut
            if !collected.leftOut.isEmpty {
                deps.log("icloud auto backup: left out, never downloaded: \(collected.leftOut.joined(separator: ", "))")
            }
        } catch {
            outcome = .failed(error.localizedDescription)
            deps.log("icloud auto backup: archive not collected: \(error)")
            return
        }
        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        if digest == defaults.string(forKey: Self.lastHashKey) {
            outcome = .unchanged
            return
        }
        let payload = BackupRecordPayload(
            installID: deps.installID(), archive: data, sourceDevice: deps.sourceDevice(),
            exportedAt: deps.now(), schemaVersion: BackupArchive.currentSchemaVersion
        )
        do {
            try await deps.sink.upsert(payload)
            defaults.set(digest, forKey: Self.lastHashKey)
            defaults.set(payload.exportedAt, forKey: Self.lastExportedAtKey)
            lastExportedAt = payload.exportedAt
            outcome = .exported(payload.exportedAt)
            deps.log("icloud auto backup: record written for \(payload.sourceDevice) (\(payload.installID)), \(data.count) bytes, schema \(payload.schemaVersion)")
        } catch let error as BackupRecordSinkError {
            deps.log("icloud auto backup: not written: \(error)")
            switch error {
            case .offline:
                hasPendingChange = true
                outcome = .waitingForNetwork
            case .rateLimited(let seconds):
                hasPendingChange = true
                outcome = .waitingForServer(seconds: seconds)
                schedule(after: seconds)
            case .noAccount:
                outcome = .noAccount
            case .quotaExceeded:
                outcome = .storageFull
            case .unavailable(let sentence):
                outcome = .failed(sentence)
            }
        } catch {
            deps.log("icloud auto backup: not written: \(error)")
            outcome = .failed(error.localizedDescription)
        }
    }
}

 
 
private struct UnentitledBackupRecordSink: BackupRecordSink {
    func upsert(_ payload: BackupRecordPayload) async throws {
        throw BackupRecordSinkError.unavailable("iCloud is not available in this build.")
    }
    func deleteOwn(installID: String) async throws {}
}
