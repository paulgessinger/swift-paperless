//
//  RefreshableContentUnavailableView.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 12.01.25.
//

import DataModel
import SwiftUI

struct ScrollableContentUnavailableView<Label, Description>: View where Label: View, Description: View {
    let label: () -> Label
    let description: () -> Description

    var body: some View {
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
    init(label: @escaping () -> Label) {
        self.label = label
        description = { EmptyView() }
    }
}

extension ScrollableContentUnavailableView where Label == SwiftUI.Label<Text, Image>, Description == EmptyView {
    init(_ string: String, systemImage: String) {
        label = {
            SwiftUI.Label(string, systemImage: systemImage)
        }
        description = { EmptyView() }
    }
}

struct NoPermissionsView<Resource>: View where Resource: LocalizedResource {
    init(for _: Resource.Type) {}

    var body: some View {
        ScrollableContentUnavailableView {
            SwiftUI.Label(String(localized: .permissions(.noViewPermissionsDisplayTitle)), systemImage: "lock.fill")
        } description: {
            Text(Resource.localizedNoViewPermissions)
        }
    }
}

#Preview("Full") {
    ScrollableContentUnavailableView {
        Label(String(localized: .localizable(.requestErrorForbidden)), systemImage: "lock.fill")
    } description: {
        Text("Some subtitle text")
    }
    .refreshable {
        print("Refresh")
    }
}

#Preview("Label only") {
    ScrollableContentUnavailableView {
        Label(String(localized: .localizable(.requestErrorForbidden)), systemImage: "lock.fill")
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
