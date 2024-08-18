//
//  ErrorDisplay.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 07.05.2024.
//

import SwiftUI

struct ErrorDisplay: ViewModifier {
    @ObservedObject var errorController: ErrorController

    // Additional offset applied to pill view
    let offset: CGFloat

    @State private var detail: (any DisplayableError)? = nil
    @State private var alertOffsetRaw: CGFloat

    private var alertOffset: CGFloat {
        alertOffsetRaw - offset
    }

    @State private var dismissTask: Task<Void, Never>? = nil
    @State private var ready = false

    func createAutoDismissTask(duration: Double) -> Task<Void, Never> {
        Task {
            try? await Task.sleep(for: .seconds(duration))
            guard !Task.isCancelled else {
                return
            }
            errorController.clear()
        }
    }

    init(errorController: ErrorController, offset: CGFloat = 0) {
        self.errorController = errorController
        self.offset = offset
        _alertOffsetRaw = State(initialValue: offset)
    }

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .top) {
                switch errorController.state {
                case let .active(error, duration):
                    HStack {
                        Label(error.message,
                              systemImage: "xmark")
                            .labelStyle(.iconOnly)
                            .foregroundColor(.red)
                            .scaleEffect(1.5)

                        VStack(alignment: .leading) {
                            Text(error.message)
                                .bold()
                            if error.details != nil {
                                Text(.localizable(.errorAlertTapForDetails))
                                    .font(Font.custom("", size: 14))
                            }
                        }
                        .font(Font.body.leading(.tight))
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, error.details == nil ? 10 : 7)

                    .contentShape(Capsule())

                    .background(Capsule()
                        .strokeBorder(.gray, lineWidth: 0.66)
                        .background(
                            Capsule().fill(
                                Material.bar
                            )
                        )
                    )

                    .offset(y: min(offset, alertOffsetRaw))

                    .opacity(min(1, max(0, 1 - (alertOffset + 10.0) / -30.0)))

                    .gesture(DragGesture(minimumDistance: 0, coordinateSpace: .global)
                        .onChanged { gesture in
                            Task {
                                alertOffsetRaw = gesture.translation.height + offset
                                dismissTask?.cancel()
                            }
                        }
                        .onEnded { _ in
                            if alertOffset < -30 {
                                withAnimation(.linear(duration: 0.3)) {
                                    alertOffsetRaw = -100 + offset
                                }
                                Task {
                                    try? await Task.sleep(for: .seconds(0.3))
                                    errorController.clear(animate: false)
                                }
                            } else if alertOffset == .zero {
                                if error.details != nil {
                                    detail = error
                                }
                                errorController.clear()
                            } else {
                                dismissTask?.cancel()
                                withAnimation(.spring(duration: 0.3)) {
                                    alertOffsetRaw = offset
                                }
                                Task {
                                    try? await Task.sleep(for: .seconds(0.31))
                                    dismissTask = createAutoDismissTask(duration: duration)
                                }
                            }
                        }
                    )

                    .disabled(!ready)

                    .task {
                        ready = false
                        dismissTask = createAutoDismissTask(duration: duration)
                        try? await Task.sleep(for: .seconds(0.75))
                        ready = true
                    }

                    .transition(.move(edge: .top).combined(with: .opacity))

                case .none:
                    EmptyView()
                }
            }

            .alert(unwrapping: $detail,
                   title: { $detail in
                       Text(detail.message)
                   },
                   actions: { $detail in
                       Button(String(localized: .localizable(.copyToClipboard))) {
                           UIPasteboard.general.string = detail.details
                       }

                       if let link = detail.documentationLink {
                           Link(String(localized: .localizable(.errorMoreInfo)), destination: link)
                       }

                       Button(String(localized: .localizable(.ok)), role: .cancel) {}
                   },
                   message: { $detail in
                       Text(detail.details!)
                   })

            .onReceive(errorController.$state) { value in
                if case .none = value {
                    Task {
                        try? await Task.sleep(for: .seconds(0.3))
                        alertOffsetRaw = offset
                    }
                }
            }
    }
}

extension View {
    @MainActor func errorOverlay(errorController: ErrorController, offset: CGFloat = 0) -> some View {
        modifier(ErrorDisplay(errorController: errorController, offset: offset))
    }
}
