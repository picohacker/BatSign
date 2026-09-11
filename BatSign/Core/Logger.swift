//
//  Logger.swift
//  BatSign
//

import Foundation
import os

enum Logger {
    static let app = Logger(subsystem: "app.batsign", category: "app")
    static let signing = Logger(subsystem: "app.batsign", category: "signing")
    static let certs = Logger(subsystem: "app.batsign", category: "certs")
}
