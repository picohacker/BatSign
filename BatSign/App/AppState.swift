//
//  AppState.swift
//  BatSign
//

import Foundation
import SwiftUI

@MainActor
final class AppState: ObservableObject {
    enum Tab: Hashable {
        case discover, apps, certs, activity, settings
    }

    @Published var selectedTab: Tab = .discover
}
