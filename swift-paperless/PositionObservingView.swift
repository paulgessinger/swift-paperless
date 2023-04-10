//
//  PositionObservingView.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 26.03.23.
//

// Adapted from https://gist.github.com/JohnSundell/341f5855f4ede71a7741e99881c74daf

import SwiftUI

/// View that observes its position within a given coordinate space,
/// and assigns that position to the specified Binding.
struct PositionObservingView<Content: View>: View {
    var coordinateSpace: CoordinateSpace
    @Binding var position: CGPoint
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .background(GeometryReader { geometry in
                Color.clear.preference(
                    key: PreferenceKey.self,
                    value: geometry.frame(in: coordinateSpace).origin
                )
            })
            .onPreferenceChange(PreferenceKey.self) { position in
                self.position = position
            }
    }
}

struct SizeObservingView<Content: View>: View {
    var coordinateSpace: CoordinateSpace
    @Binding var size: CGSize
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .background(GeometryReader { geometry in
                Color.clear.preference(
                    key: PreferenceKey.self,
                    value: geometry.frame(in: coordinateSpace).size
                )
            })
            .onPreferenceChange(PreferenceKey.self) { size in
                self.size = size
            }
    }
}

private extension PositionObservingView {
    enum PreferenceKey: SwiftUI.PreferenceKey {
        static var defaultValue: CGPoint { .zero }

        static func reduce(value: inout CGPoint, nextValue: () -> CGPoint) {
            // No-op
        }
    }
}

private extension SizeObservingView {
    enum PreferenceKey: SwiftUI.PreferenceKey {
        static var defaultValue: CGSize { .zero }

        static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
            // No-op
        }
    }
}

/// Specialized scroll view that observes its content offset (scroll position)
/// and assigns it to the specified Binding.
struct OffsetObservingScrollView<Content: View>: View {
    var axes: Axis.Set = [.vertical]
    var showsIndicators = true
    @Binding var offset: CGPoint
    @ViewBuilder var content: () -> Content

    private let coordinateSpaceName = UUID()

    var body: some View {
        ScrollView(axes, showsIndicators: showsIndicators) {
            PositionObservingView(
                coordinateSpace: .named(coordinateSpaceName),
                position: Binding(
                    get: { offset },
                    set: { newOffset in
                        offset = CGPoint(
                            x: -newOffset.x,
                            y: -newOffset.y
                        )
                    }
                ),
                content: content
            )
        }
        .coordinateSpace(name: coordinateSpaceName)
    }
}

/// View that renders scrollable content beneath a header that
/// automatically collapses when the user scrolls down.
// struct ContentView<Content: View>: View {
//    var title: String
//    var headerGradient: Gradient
//    @ViewBuilder var content: () -> Content
//
//    private let headerHeight = (collapsed: 50.0, expanded: 150.0)
//    @State private var scrollOffset = CGPoint()
//
//    var body: some View {
//        GeometryReader { geometry in
//            OffsetObservingScrollView(offset: $scrollOffset) {
//                VStack(spacing: 0) {
//                    makeHeaderText(collapsed: false)
//                    content()
//                }
//            }
//            .overlay(alignment: .top) {
//                makeHeaderText(collapsed: true)
//                    .background(alignment: .top) {
//                        headerLinearGradient.ignoresSafeArea()
//                    }
//                    .opacity(collapsedHeaderOpacity)
//            }
//            .background(alignment: .top) {
//                // We attach the expanded header's background to the scroll
//                // view itself, so that we can make it expand into both the
//                // safe area, as well as any negative scroll offset area:
//                headerLinearGradient
//                    .frame(height: max(0, headerHeight.expanded - scrollOffset.y) + geometry.safeAreaInsets.top)
//                    .ignoresSafeArea()
//            }
//        }
//    }
// }
//
// private extension ContentView {
//    var collapsedHeaderOpacity: CGFloat {
//        let minOpacityOffset = headerHeight.expanded / 2
//        let maxOpacityOffset = headerHeight.expanded - headerHeight.collapsed
//
//        guard scrollOffset.y > minOpacityOffset else { return 0 }
//        guard scrollOffset.y < maxOpacityOffset else { return 1 }
//
//        let opacityOffsetRange = maxOpacityOffset - minOpacityOffset
//        return (scrollOffset.y - minOpacityOffset) / opacityOffsetRange
//    }
//
//    var headerLinearGradient: LinearGradient {
//        LinearGradient(
//            gradient: headerGradient,
//            startPoint: .top,
//            endPoint: .bottom
//        )
//    }
//
//    func makeHeaderText(collapsed: Bool) -> some View {
//        Text(title)
//            .font(collapsed ? .body : .title)
//            .lineLimit(1)
//            .padding()
//            .frame(height: collapsed ? headerHeight.collapsed : headerHeight.expanded)
//            .frame(maxWidth: .infinity)
//            .foregroundColor(.white)
//            .accessibilityHeading(.h1)
//            .accessibilityHidden(collapsed)
//    }
// }
