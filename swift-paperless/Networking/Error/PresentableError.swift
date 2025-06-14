//
//  PresentableError.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 14.12.2024.
//

import SwiftUI

protocol PresentableError {
    associatedtype PresentationView: View

    @MainActor
    var presentation: PresentationView { get }
}
