//
//  TelemetryUploader.swift
//  Chiron
//
//  Background-resilient upload queue for the developer-facing telemetry pipeline.
//
//  Upload flow per file:
//    1. POST {firebase_user_id, anonymous_uuid, filename, file_type, app_build,
//       schema_version} to the Worker → presigned PUT URL.
//    2. PUT the file to that presigned URL via a background URLSession.
//    3. On 2xx, move the file from Pending/ to Uploaded/ (kept 7 days).
//    4. On any failure: exponential backoff (30s → 1h cap), up to 5 attempts,
//       then give up and log.
//
//  Network guardrails (BOTH apply):
//    - Wi-Fi-only by default. `TelemetryPreferencesManager.allowCellularUploads`
//      lifts this. Enforced both via `URLRequest.allowsCellularAccess` and a
//      pre-enqueue NWPathMonitor check.
//    - Per-file size cap (`cellularByteCap` = 50 MB) — even with cellular
//      allowed, a file larger than this defers to Wi-Fi. Defends against an
//      unexpectedly long set producing a fat mp4 that would burn the user's
//      mobile data.
//
//  Background URLSession identifier:
//    "com.chiron.telemetry.uploads" — must be unique per app and stable across
//    launches so the system can re-attach. AppDelegate must forward
//    `handleEventsForBackgroundURLSession:` to `setBackgroundEventsCompletion()`.
//

import Foundation
import Network

actor TelemetryUploader {
    static let shared = TelemetryUploader()

    // MARK: - Configuration

    /// TODO_REPLACE_WITH_WORKER_URL: paste the Cloudflare Worker URL once you
    /// deploy it (see `TELEMETRY_SETUP.md`). All POSTs from this file land
    /// here; one grep, one edit.
    private static let workerURL: String = "https://chiron-telemetry.zthomson.workers.dev"

    private static let backgroundIdentifier = "com.chiron.telemetry.uploads"

    private let maxRetries = 5
    private let initialBackoffSeconds: TimeInterval = 30
    private let maxBackoffSeconds: TimeInterval = 3600

    /// Bytes above which uploads defer to Wi-Fi even when cellular is allowed.
    /// Set to match the Worker's 200 MB ceiling — solo-dev phase, no testers
    /// whose data plans we need to defend yet. Tighten back down (50 MB) and
    /// re-evaluate before TestFlight.
    private static let cellularByteCap: Int64 = 200 * 1024 * 1024

    /// Files in `Uploaded/` older than this age are pruned by `cleanupOldUploaded`.
    private static let uploadedRetentionSeconds: TimeInterval = 7 * 24 * 3600

    // MARK: - Stored state

    nonisolated private let session: URLSession
    nonisolated private let delegate: TelemetryUploadDelegate
    nonisolated private let pathMonitor: NWPathMonitor
    nonisolated private let pathMonitorQueue: DispatchQueue

    /// Tracks in-flight background PUT tasks so the delegate callback can map
    /// `taskIdentifier` back to a relative path.
    private var inFlightTasks: [Int: InFlightUpload] = [:]

    /// Per-file retry counter, keyed by relative path under Pending/. Reset on
    /// success or final give-up.
    private var retryAttempts: [String: Int] = [:]

    /// Files currently being processed (presigned-URL fetch or PUT in flight).
    /// Prevents double-enqueue when the launch scan and a fresh `endSession()`
    /// fight over the same path.
    private var activePaths: Set<String> = []

    /// Held until `urlSessionDidFinishEvents` so the system knows when all
    /// background events have been delivered. AppDelegate sets it via
    /// `setBackgroundEventsCompletion(_:)`.
    private var backgroundEventsCompletion: (() -> Void)?

    // MARK: - Init

    init() {
        let config = URLSessionConfiguration.background(withIdentifier: TelemetryUploader.backgroundIdentifier)
        config.sessionSendsLaunchEvents = true
        config.isDiscretionary = false
        // Per-task `URLRequest.allowsCellularAccess` overrides this when needed.
        config.allowsCellularAccess = true
        // (Previously set `shouldUseExtendedBackgroundIdleMode = true` — the
        // property was deprecated and is a no-op as of iOS 18.4. Background
        // URLSession already gets the appropriate keep-alive treatment.)

        let delegate = TelemetryUploadDelegate()
        self.delegate = delegate
        self.session = URLSession(configuration: config, delegate: delegate, delegateQueue: nil)

        let monitor = NWPathMonitor()
        let queue = DispatchQueue(label: "com.chiron.telemetry.uploader.path-monitor")
        monitor.start(queue: queue)
        self.pathMonitor = monitor
        self.pathMonitorQueue = queue
    }

    // MARK: - Public entry points (nonisolated — fire-and-forget from any thread)

    /// Enqueue a single Pending/ file (relative path) for upload.
    nonisolated func enqueue(relativePath: String) {
        Task { await self.enqueueInternal(relativePath: relativePath) }
    }

    /// Walk Pending/ and enqueue every orphaned file. Call on app launch and
    /// on app foregrounding.
    nonisolated func resumePendingUploads() {
        Task { await self.resumePendingInternal() }
    }

    /// Prune Uploaded/ files older than 7 days. Call on app launch.
    nonisolated func cleanupOldUploaded() {
        Task { await self.cleanupOldUploadedInternal() }
    }

    /// AppDelegate hands the completion handler over here so we can invoke it
    /// once the system reports all background events delivered.
    nonisolated func setBackgroundEventsCompletion(_ completion: @escaping () -> Void) {
        Task { await self.storeBackgroundEventsCompletion(completion) }
    }

    // MARK: - Delegate callback hooks (called by TelemetryUploadDelegate)

    func handleTaskCompletion(taskIdentifier: Int, statusCode: Int, error: Error?) async {
        guard let info = inFlightTasks.removeValue(forKey: taskIdentifier) else { return }
        let relativePath = info.relativePath
        activePaths.remove(relativePath)

        let success = (error == nil) && (200..<300).contains(statusCode)
        if success {
            retryAttempts.removeValue(forKey: relativePath)
            moveToUploaded(relativePath: relativePath)
            print("[TelemetryUploader] Uploaded \(relativePath) (\(info.fileSize) bytes).")
        } else {
            scheduleRetry(
                relativePath: relativePath,
                reason: "PUT failed: status=\(statusCode), err=\(error?.localizedDescription ?? "nil")"
            )
        }
    }

    func handleBackgroundEventsFinished() async {
        let handler = backgroundEventsCompletion
        backgroundEventsCompletion = nil
        // System completion handlers must run on the main queue.
        if let handler = handler {
            await MainActor.run { handler() }
        }
    }

    // MARK: - Internal isolated work

    private func storeBackgroundEventsCompletion(_ completion: @escaping () -> Void) {
        backgroundEventsCompletion = completion
    }

    private func enqueueInternal(relativePath: String) async {
        if activePaths.contains(relativePath) {
            print("[TelemetryUploader] Skipping enqueue (already active): \(relativePath)")
            return
        }
        activePaths.insert(relativePath)
        print("[TelemetryUploader] Enqueued \(relativePath)")
        await processUpload(relativePath: relativePath)
    }

    private func resumePendingInternal() async {
        guard let urls = try? TelemetryFilesystem.enumeratePending(),
              let root = try? TelemetryFilesystem.pendingRoot() else {
            print("[TelemetryUploader] resumePending: failed to read Pending root")
            return
        }
        print("[TelemetryUploader] resumePending: found \(urls.count) orphan(s) in Pending/")
        // iOS's enumerator returns symlink-resolved paths (/private/var/...) while
        // `pendingRoot()` returns the logical form (/var/...). Resolve both so the
        // prefix-strip works regardless of which form each side hands back.
        let prefix = root.resolvingSymlinksInPath().path + "/"
        for url in urls {
            var rel = url.resolvingSymlinksInPath().path
            if rel.hasPrefix(prefix) {
                rel = String(rel.dropFirst(prefix.count))
            }
            let capturedRel = rel
            Task { await self.enqueueInternal(relativePath: capturedRel) }
        }
    }

    private func cleanupOldUploadedInternal() async {
        guard let root = try? TelemetryFilesystem.uploadedRoot(),
              let enumerator = FileManager.default.enumerator(
                at: root,
                includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
                options: [.skipsHiddenFiles]
              ) else { return }
        let cutoff = Date().addingTimeInterval(-Self.uploadedRetentionSeconds)
        // Materialize via `allObjects` rather than iterating the enumerator
        // directly — `DirectoryEnumerator.makeIterator()` is unavailable from
        // async contexts under Swift 6 strict concurrency.
        for case let url as URL in enumerator.allObjects {
            let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .isRegularFileKey])
            guard values?.isRegularFile == true else { continue }
            if let modDate = values?.contentModificationDate, modDate < cutoff {
                try? FileManager.default.removeItem(at: url)
            }
        }
    }

    private func processUpload(relativePath: String) async {
        // 1. Source file exists?
        guard let pendingRoot = try? TelemetryFilesystem.pendingRoot() else {
            print("[TelemetryUploader] processUpload abort: pendingRoot unreachable for \(relativePath)")
            activePaths.remove(relativePath)
            return
        }
        let pendingURL = pendingRoot.appendingPathComponent(relativePath)
        guard FileManager.default.fileExists(atPath: pendingURL.path) else {
            print("[TelemetryUploader] processUpload abort: file missing at \(pendingURL.path)")
            activePaths.remove(relativePath)
            return
        }

        // 2. Network gating — both the cellular toggle and the size guardrail.
        let path = pathMonitor.currentPath
        guard path.status == .satisfied else {
            scheduleRetry(relativePath: relativePath, reason: "no-network")
            return
        }
        let isWiFi = path.usesInterfaceType(.wifi) || path.usesInterfaceType(.wiredEthernet)
        let allowCellular = await MainActor.run { TelemetryPreferencesManager.shared.allowCellularUploads }
        if !isWiFi && !allowCellular {
            scheduleRetry(relativePath: relativePath, reason: "wifi-only-and-on-cellular")
            return
        }

        // 3. Size guardrail (defends against an unexpectedly large mp4).
        let fileSize = (try? FileManager.default.attributesOfItem(atPath: pendingURL.path)[.size] as? Int64) ?? 0
        if !isWiFi && fileSize > Self.cellularByteCap {
            scheduleRetry(
                relativePath: relativePath,
                reason: "size-exceeds-cellular-cap (\(fileSize) > \(Self.cellularByteCap))"
            )
            return
        }

        // 4. Worker URL configured?
        guard Self.workerURL != "TODO_REPLACE_WITH_WORKER_URL",
              let workerURLValue = URL(string: Self.workerURL) else {
            scheduleRetry(relativePath: relativePath, reason: "worker-url-not-configured")
            return
        }

        print("[TelemetryUploader] Fetching presigned URL for \(relativePath) (\(fileSize) bytes, isWiFi=\(isWiFi))")

        // 5. Fetch presigned URL.
        let presignedURL: URL
        do {
            presignedURL = try await fetchPresignedURL(
                workerURL: workerURLValue,
                relativePath: relativePath,
                fileSize: fileSize,
                allowCellular: allowCellular
            )
        } catch {
            scheduleRetry(relativePath: relativePath, reason: "presigned-fetch-failed: \(error.localizedDescription)")
            return
        }

        // 6. Background PUT.
        var putRequest = URLRequest(url: presignedURL)
        putRequest.httpMethod = "PUT"
        putRequest.allowsCellularAccess = allowCellular
        putRequest.setValue(contentType(for: relativePath), forHTTPHeaderField: "Content-Type")
        let task = session.uploadTask(with: putRequest, fromFile: pendingURL)
        inFlightTasks[task.taskIdentifier] = InFlightUpload(relativePath: relativePath, fileSize: fileSize)
        print("[TelemetryUploader] PUT started taskID=\(task.taskIdentifier) for \(relativePath)")
        task.resume()
    }

    private func fetchPresignedURL(
        workerURL: URL,
        relativePath: String,
        fileSize: Int64,
        allowCellular: Bool
    ) async throws -> URL {
        let (firebaseUserId, anonymousUUID) = TelemetryUploader.currentIdentities()
        let appBuild = TelemetryUploader.currentAppBuild()
        let fileType = (relativePath as NSString).pathExtension.lowercased()

        let body: [String: Any] = [
            "firebase_user_id": firebaseUserId,
            "anonymous_uuid": anonymousUUID,
            "filename": relativePath,
            "file_type": fileType,
            "file_size_bytes": fileSize,
            "app_build": appBuild,
            "schema_version": SessionCSVWriter.schemaVersion
        ]

        var request = URLRequest(url: workerURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.allowsCellularAccess = allowCellular
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw NSError(
                domain: "TelemetryUploader",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "presigned worker non-2xx"]
            )
        }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let urlStr = json["presigned_url"] as? String,
              let url = URL(string: urlStr) else {
            throw NSError(
                domain: "TelemetryUploader",
                code: -2,
                userInfo: [NSLocalizedDescriptionKey: "presigned worker malformed response"]
            )
        }
        return url
    }

    private func scheduleRetry(relativePath: String, reason: String) {
        activePaths.remove(relativePath)
        let attempt = (retryAttempts[relativePath] ?? 0) + 1
        if attempt > maxRetries {
            print("[TelemetryUploader] Giving up on \(relativePath) after \(attempt - 1) attempts. Last reason: \(reason)")
            retryAttempts.removeValue(forKey: relativePath)
            return
        }
        retryAttempts[relativePath] = attempt

        let delay = min(initialBackoffSeconds * pow(2, Double(attempt - 1)), maxBackoffSeconds)
        print("[TelemetryUploader] Retrying \(relativePath) in \(Int(delay))s (attempt \(attempt)/\(maxRetries)). Reason: \(reason)")

        Task {
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            await self.enqueueInternal(relativePath: relativePath)
        }
    }

    private func moveToUploaded(relativePath: String) {
        guard let pendingRoot = try? TelemetryFilesystem.pendingRoot(),
              let uploadedRoot = try? TelemetryFilesystem.uploadedRoot() else { return }
        let src = pendingRoot.appendingPathComponent(relativePath)
        let dest = uploadedRoot.appendingPathComponent(relativePath)
        do {
            try FileManager.default.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? FileManager.default.removeItem(at: dest)
            try FileManager.default.moveItem(at: src, to: dest)
        } catch {
            print("[TelemetryUploader] Failed to move \(relativePath) to Uploaded/: \(error)")
        }
    }

    // MARK: - Helpers

    private func contentType(for relativePath: String) -> String {
        switch (relativePath as NSString).pathExtension.lowercased() {
        case "csv": return "text/csv"
        case "mp4": return "video/mp4"
        case "json", "jsonl": return "application/json"
        default:    return "application/octet-stream"
        }
    }

    /// Today both IDs come from `UserManager.shared.getUserId()` (the device's
    /// `identifierForVendor`) — there's no real Firebase Auth installed yet.
    /// When you wire FirebaseAuth in, change ONLY the `firebaseUserId` line
    /// to `Auth.auth().currentUser?.uid ?? ...`. The schema, downstream
    /// partitioning, and Worker payload all stay the same.
    /// TODO(firebase-auth): swap firebaseUserId source. Search marker:
    /// `TODO_FIREBASE_USER_ID_SWAP`.
    nonisolated private static func currentIdentities() -> (firebaseUserId: String, anonymousUUID: String) {
        let id = UserManager.shared.getUserId()
        // TODO_FIREBASE_USER_ID_SWAP — see comment above.
        let firebaseUserId = id
        let anonymousUUID = id
        return (firebaseUserId, anonymousUUID)
    }

    nonisolated private static func currentAppBuild() -> String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "unknown"
    }
}

// MARK: - In-Flight tracking

private struct InFlightUpload {
    let relativePath: String
    let fileSize: Int64
}

// MARK: - URLSession Delegate

/// Bridges background URLSession callbacks into the actor. Lives at file
/// scope (not nested) so the URLSession's strong reference doesn't tangle
/// with actor isolation.
final class TelemetryUploadDelegate: NSObject, URLSessionTaskDelegate, URLSessionDataDelegate {

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        let identifier = task.taskIdentifier
        let statusCode = (task.response as? HTTPURLResponse)?.statusCode ?? 0
        Task { await TelemetryUploader.shared.handleTaskCompletion(taskIdentifier: identifier, statusCode: statusCode, error: error) }
    }

    func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        Task { await TelemetryUploader.shared.handleBackgroundEventsFinished() }
    }
}
