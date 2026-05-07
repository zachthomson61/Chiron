//
//  TelemetryFilesystem.swift
//  Chiron
//
//  Shared on-disk layout helpers for the telemetry pipeline. Both the CSV
//  writer and the video recorder land their files under the same Pending/
//  tree; the uploader migrates to Uploaded/ on success.
//
//  The relative path inside Pending/ is also the R2 object key — the local
//  layout mirrors the cloud layout, so upload is a strict copy operation.
//

import Foundation

enum TelemetryFilesystem {

    /// Root for all telemetry artifacts under Application Support. Created on
    /// first access; safe to call repeatedly.
    static func appSupportRoot() throws -> URL {
        let fm = FileManager.default
        let base = try fm.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let root = base.appendingPathComponent("Telemetry", isDirectory: true)
        try fm.createDirectory(at: root, withIntermediateDirectories: true, attributes: nil)
        return root
    }

    /// Files actively being written or awaiting upload.
    static func pendingRoot() throws -> URL {
        let dir = try appSupportRoot().appendingPathComponent("Pending", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true, attributes: nil)
        return dir
    }

    /// Files successfully uploaded — kept for 7 days as a recovery safety net,
    /// then pruned by `TelemetryUploader.cleanupOldUploaded`.
    static func uploadedRoot() throws -> URL {
        let dir = try appSupportRoot().appendingPathComponent("Uploaded", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true, attributes: nil)
        return dir
    }

    /// Builds the relative path used for both the local on-disk location
    /// (under Pending/ or Uploaded/) and the R2 object key. Format is the
    /// non-negotiable spec convention — partition columns the analytical
    /// layer will read later all live in this filename:
    ///
    ///   {firebase_user_id}/{exercise_type}/{ISO8601}_{app_build}_{viewpoint}_{session}.{ext}
    ///
    /// The ISO timestamp uses `-` instead of `:` because macOS/iOS reject
    /// `:` in filenames; the upload step swaps it back when constructing
    /// the R2 key if you'd prefer `:` in the cloud.
    static func relativePath(
        firebaseUserId: String,
        exerciseTypeName: String,
        startedAt: Date,
        appBuild: String,
        viewpointProfile: String,
        sessionUUID: UUID,
        ext: String
    ) -> String {
        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime]
        let timestamp = isoFormatter.string(from: startedAt).replacingOccurrences(of: ":", with: "-")
        let safeUser = sanitize(firebaseUserId)
        let safeExercise = sanitize(exerciseTypeName)
        let safeViewpoint = sanitize(viewpointProfile)
        let basename = "\(timestamp)_\(appBuild)_\(safeViewpoint)_\(sessionUUID.uuidString).\(ext)"
        return "\(safeUser)/\(safeExercise)/\(basename)"
    }

    /// Strips characters that aren't safe in either a filesystem path segment
    /// or an S3-compatible object key.
    private static func sanitize(_ s: String) -> String {
        s.unicodeScalars.reduce(into: "") { acc, scalar in
            let c = Character(scalar)
            if c.isLetter || c.isNumber || c == "-" || c == "_" || c == "." {
                acc.append(c)
            } else {
                acc.append("_")
            }
        }
    }

    /// Walks `Pending/` and returns every regular file. Used on app launch to
    /// discover orphans from a prior crash and re-enqueue them.
    static func enumeratePending() throws -> [URL] {
        let root = try pendingRoot()
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }
        var urls: [URL] = []
        for case let url as URL in enumerator {
            let isFile = (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) ?? false
            if isFile { urls.append(url) }
        }
        return urls
    }
}
