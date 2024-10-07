//
//  LoginView.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 04.08.2024.
//

import Foundation
import SwiftUI

@MainActor
protocol LoginViewProtocol: View {
    init(connectionManager: ConnectionManager, initial: Bool)
}

struct LoginView: LoginViewProtocol {
    @ObservedObject var connectionManager: ConnectionManager
    var initial = true

    @ObservedObject private var appSettings = AppSettings.shared

    var body: some View {
        // @TODO: Enable new lgoin screen for AppStore
        if appSettings.loginScreenV2, Bundle.main.appConfiguration != .AppStore {
            LoginViewV2(connectionManager: connectionManager, initial: initial)
        } else {
            LoginViewV1(connectionManager: connectionManager, initial: initial)
        }
    }
}

struct LoginViewSwitchView: View {
    @ObservedObject private var appSettings = AppSettings.shared

    var body: some View {
        Toggle("Login screen v2", isOn: $appSettings.loginScreenV2)
    }
}
