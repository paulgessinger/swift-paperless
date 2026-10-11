//
//  LogoTitle.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 25.03.23.
//

import AppShared
import SwiftUI

public struct LogoTitle: View {
  @ScaledMetric(relativeTo: .body) private var logoSize = 50.0

  public init() {}

  public var body: some View {
    HStack(spacing: 5) {
      Image("AppLogoTransparent")
        .resizable()
        .frame(width: logoSize, height: logoSize)
      Text(.app(.appName))
        .font(.title2)
    }
    .padding(.trailing, 15)
  }
}

#Preview {
  NavigationStack {
    Color.clear
      .toolbar {
        ToolbarItem(placement: .principal) {
          LogoTitle()
        }
      }
  }
}
