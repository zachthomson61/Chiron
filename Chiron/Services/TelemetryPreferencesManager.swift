//
//  TelemetryPreferencesManager.swift
//  Chiron
//
//  User-controllable preferences for the developer-facing telemetry pipeline:
//  whether to share workout data at all, and whether to do so over cellular.
//
//  Mirrors `CameraCoachingPreferencesManager` — singleton ObservableObject with
//  UserDefaults-backed @Published flags, bound directly from SettingsView.
//
//  Both flags default to false. No telemetry leaves the device until the user
//  explicitly opts in via Settings.
//

import Foundation
import SwiftUI

final class TelemetryPreferencesManager: ObservableObject {
    static let shared = TelemetryPreferencesManager()

    private static let shareKey = "chiron.telemetry.share_data.v1"
    private static let cellularKey = "chiron.telemetry.allow_cellular.v1"

    /// Master switch. When false, no CSV is written, no screen recording is
    /// captured for upload, and no new files are enqueued.
    ///
    /// **Default is currently `true`** — solo-developer testing phase, no
    /// external testers, all data should land in R2 automatically. There is
    /// no UI for this flag right now.
    ///
    /// **Before TestFlight** flip the default back to `false` and re-add the
    /// "Help Improve Chiron" section to `SettingsView` (git history has it).
    /// Apple reviewers treat unconsented screen-capture-and-upload as a
    /// privacy violation, even with the existing camera permission.
    @Published var shareDataToImproveChiron: Bool {
        didSet { UserDefaults.standard.set(shareDataToImproveChiron, forKey: Self.shareKey) }
    }

    /// When true, the upload queue is allowed on cellular. When false (default),
    /// uploads are gated to Wi-Fi via `URLSessionConfiguration.allowsCellularAccess`
    /// plus an `NWPathMonitor` pre-enqueue check. Independent of the master flag —
    /// only consulted when `shareDataToImproveChiron` is true.
    @Published var allowCellularUploads: Bool {
        didSet { UserDefaults.standard.set(allowCellularUploads, forKey: Self.cellularKey) }
    }

    private init() {
        // Default share flag to `true` when never set — solo testing phase.
        // Once present in UserDefaults, honor whatever was last written.
        if UserDefaults.standard.object(forKey: Self.shareKey) == nil {
            self.shareDataToImproveChiron = true
            UserDefaults.standard.set(true, forKey: Self.shareKey)
        } else {
            self.shareDataToImproveChiron = UserDefaults.standard.bool(forKey: Self.shareKey)
        }
        self.allowCellularUploads = UserDefaults.standard.bool(forKey: Self.cellularKey)
    }
}
