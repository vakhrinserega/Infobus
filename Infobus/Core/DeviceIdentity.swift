//
//  DeviceIdentity.swift
//  Infobus
//
//  A per-install anonymous identifier — ports the old Objective-C app's
//  `UserDefaults.deviceId` (a random UUID generated once and persisted),
//  which `InfobusAPIClient.postStatistic` already expects but nothing in
//  this rewrite has actually generated until now. Also doubles as the
//  owner key for support appeals (see AppealsStore's header): there's no
//  login anywhere in this app, so a sufficiently random UUID is the only
//  "who is asking" the appeals backend can go on. It resets on reinstall
//  or a new device — an accepted trade-off for a lightweight feedback
//  feature, not something worth a full account system for.
//

import Foundation

enum DeviceIdentity {
    private static let key = "device_id"

    static var current: String {
        let defaults = UserDefaults.standard
        if let existing = defaults.string(forKey: key) {
            return existing
        }
        let generated = UUID().uuidString
        defaults.set(generated, forKey: key)
        return generated
    }
}
