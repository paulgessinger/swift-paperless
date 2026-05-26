//
//  RefreshableContentUnavailableView.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 12.01.25.
//

import DataModel
import SwiftUI

public struct ScrollableContentUnavailableView<Label, Description>: View
where Label: View, Description: View {
  public let label: () -> Label
  public let description: () -> Description

  public var body: some View {
    ScrollView(.vertical) {
      ContentUnavailableView {
        label()
      } description: {
        description()
      }
      .padding(.top, 40)
    }
  }
}

extension ScrollableContentUnavailableView where Description == EmptyView {
  public init(label: @escaping () -> Label) {
    self.label = label
    description = { EmptyView() }
  }
}

extension ScrollableContentUnavailableView
where Label == SwiftUI.Label<Text, Image>, Description == EmptyView {
  public init(_ string: String, systemImage: String) {
    label = {
      SwiftUI.Label(string, systemImage: systemImage)
    }
    description = { EmptyView() }
  }
}

public struct NoPermissionsView<Resource>: View where Resource: LocalizedResource {
  public init(for _: Resource.Type) {}

  public var body: some View {
    ScrollableContentUnavailableView {
      SwiftUI.Label(
        String(localized: .permissions(.noViewPermissionsDisplayTitle)), systemImage: "lock.fill")
    } description: {
      Text(Resource.localizedNoViewPermissions)
    }
  }
}

#Preview("Full") {
  ScrollableContentUnavailableView {
    Label(String(localized: .app(.requestErrorForbidden)), systemImage: "lock.fill")
  } description: {
    Text("Some subtitle text")
  }
  .refreshable {
    print("Refresh")
  }
}

#Preview("Label only") {
  ScrollableContentUnavailableView {
    Label(String(localized: .app(.requestErrorForbidden)), systemImage: "lock.fill")
  }
  .refreshable {
    print("Refresh")
  }
}

#Preview("No permissions") {
  NoPermissionsView(for: Document.self)
    .refreshable {
      print("Refresh")
    }
}
