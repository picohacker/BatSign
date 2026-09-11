//
//  AppState.swift
//  BatSign
//

import Foundation
import SwiftUI

@MainActor
final class AppState: ObservableObject {
    enum Tab: Hashable {
        case sign, apps, certs, activity, settings
    }

    @Published var selectedTab: Tab = .sign
    @Published var selectedAppID: UUID?

    func signApp(_ id: UUID) {
        selectedAppID = id
        selectedTab = .sign
    }
}
