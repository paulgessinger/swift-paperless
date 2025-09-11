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
        LoginViewV2(connectionManager: connectionManager, initial: initial)
    }
}
