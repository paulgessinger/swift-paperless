//
//  LogoView.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 25.03.23.
//

import SwiftUI

public struct LogoView: View {
  private let logoSize: CGFloat = 64
  private let logoRadius: CGFloat = 5

  public var body: some View {
    VStack(spacing: -15) {
      Image("AppLogoTransparent")
      Text(.localizable(.appName))
        .font(.title)
    }
  }
}

public struct LogoTitle: View {
  @ScaledMetric(relativeTo: .body) private var logoSize = 50.0

  public init() {}

  public var body: some View {
    HStack(spacing: 5) {
      Image("AppLogoTransparent")
        .resizable()
        .frame(width: logoSize, height: logoSize)
      Text(.localizable(.appName))
        .font(.title2)
    }
    .padding(.trailing, 15)
  }
}

#Preview {
  NavigationStack {
    LogoView()
      .toolbar {
        ToolbarItem(placement: .principal) {
          LogoTitle()
        }
      }
  }
}
