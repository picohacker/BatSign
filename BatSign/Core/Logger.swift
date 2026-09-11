//
//  Logger.swift
//  BatSign
//

import Foundation
import os

/// Thin wrappers over os.Logger. Qualified explicitly to avoid clashing
/// with the system `Logger` type.
enum BLog {
    static let app = os.Logger(subsystem: "app.batsign", category: "app")
    static let signing = os.Logger(subsystem: "app.batsign", category: "signing")
    static let certs = os.Logger(subsystem: "app.batsign", category: "certs")
}
