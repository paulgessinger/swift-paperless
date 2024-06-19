//
//  CreatedPicker.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 19.06.2024.
//
import SwiftUI

struct DocumentDetailViewV2CreatedPicker: View {
    @Bindable var viewModel: DocumentDetailModel
    @Binding var date: Date
    let animation: Namespace.ID

    @State private var showInterface = false
    @State private var changed = false

    @MainActor
    private func close() async {
        showInterface = false
        try? await Task.sleep(for: .seconds(0.3))
        await viewModel.stopEditing()
    }

    var body: some View {
        ScrollView(.vertical) {
            VStack {
                DatePicker(String(localized: .localizable(.documentEditCreatedDateLabel)),
                           selection: $date,
                           displayedComponents: .date)
                    .datePickerStyle(.graphical)
                    .opacity(showInterface ? 1 : 0)
            }
            .frame(width: min(320, UIScreen.main.bounds.width))
            .animation(.default.delay(showInterface ? 0.15 : 0), value: showInterface)

            .task {
                try? await Task.sleep(for: .seconds(0.20))
                showInterface = true
            }

            .onChange(of: date) {
                changed = true
            }
        }
        .safeAreaInset(edge: .top) {
            PickerHeader(color: .paletteBlue,
                         showInterface: $showInterface,
                         animation: animation,
                         id: "EditCreated",
                         closeInline: true,
                         icon: changed ? "checkmark" : "xmark")
            {
                HStack {
                    Label(localized: .localizable(.documentEditCreatedDateLabel), systemImage: "calendar")
                        .labelStyle(.iconOnly)
                        .font(.title3)
                        .matchedGeometryEffect(id: "EditCreatedIcon", in: animation, isSource: true)
                    Text(.localizable(.documentEditCreatedDateLabel))
                        .opacity(showInterface ? 1 : 0)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

            } onClose: {
                Task {
                    Haptics.shared.impact(style: .light)
                    await close()
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
