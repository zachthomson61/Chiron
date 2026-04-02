//
//  ScreenKeepAlive.swift
//  Chiron
//
//  Prevents the device screen from locking due to inactivity while the user is
//  in active workout or track views (similar to video playback).
//  Uses a ref count so multiple such views can be in the hierarchy safely.
//

import UIKit

enum ScreenKeepAlive {
    private static var refCount = 0

    /// Call when a view that should keep the screen on appears (e.g. TrackView, ActiveWorkoutView).
    static func begin() {
        refCount += 1
        if refCount == 1 {
            UIApplication.shared.isIdleTimerDisabled = true
        }
    }

    /// Call when that view disappears.
    static func end() {
        refCount = max(0, refCount - 1)
        if refCount == 0 {
            UIApplication.shared.isIdleTimerDisabled = false
        }
    }
}
