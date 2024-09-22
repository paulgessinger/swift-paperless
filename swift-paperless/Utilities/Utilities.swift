//
//  Utilities.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 22.02.23.
//

import Combine
import Foundation
import os
import SwiftUI

class DebounceObject: ObservableObject {
    @Published var text: String = ""
    @Published var debouncedText: String = ""
    private var tasks = Set<AnyCancellable>()

    init(value: String = "", delay: TimeInterval = 0.5) {
        text = value
        $text
            .removeDuplicates()
            .debounce(for: .seconds(delay), scheduler: DispatchQueue.main)
            .sink(receiveValue: { [weak self] value in
                self?.debouncedText = value
            })
            .store(in: &tasks)
    }
}

@MainActor
final class ThrottleObject<T: Equatable & Sendable>: ObservableObject, Sendable {
    @Published var value: T
    @Published var throttledValue: T

    var publisher = PassthroughSubject<T, Never>()
    private var tasks = Set<AnyCancellable>()

    init(value: T, delay: TimeInterval = 0.5) {
        self.value = value
        throttledValue = value
        $value
            .throttle(for: .seconds(delay), scheduler: DispatchQueue.main, latest: true)
            .sink(receiveValue: { [weak self] value in
                DispatchQueue.main.async { self?.throttledValue = value }
                self?.publisher.send(value)
            })
            .store(in: &tasks)
    }
}

#if canImport(UIKit)
    extension UIColor {
        private func makeColor(delta: CGFloat) -> UIColor {
            var red: CGFloat = 0
            var green: CGFloat = 0
            var blue: CGFloat = 0
            var alpha: CGFloat = 0

            getRed(&red, green: &green, blue: &blue, alpha: &alpha)

            let clamp = { (v: CGFloat) in min(1, max(0, v)) }
            return UIColor(
                red: clamp(red + delta),
                green: clamp(green + delta),
                blue: clamp(blue + delta),
                alpha: clamp(alpha + delta)
            )
        }

        func ligher(delta: CGFloat = 0.1) -> UIColor {
            makeColor(delta: delta)
        }

        func darker(delta: CGFloat = 0.1) -> UIColor {
            makeColor(delta: -1 * delta)
        }
    }

#endif

//// @TODO: Put this into a dispatch queue
// func pdfPreview(url: URL) -> Image? {
//    var fileSize: UInt64 = 0
//    do {
//        let attr = try FileManager.default.attributesOfItem(atPath: url.path)
//        let dict = attr as NSDictionary
//        fileSize = dict.fileSize()
//    } catch {}
//
//    if Bundle.main.bundlePath.hasSuffix(".appex") {
//        if fileSize > 5 * 1024 * 1024 {
//            Logger.shared.debug("Refusing to make PDF preview, file size is \(fileSize)")
//            return nil
//        }
//    }
//
//    guard let doc = CGPDFDocument(url as CFURL) else { return nil }
//    guard let page = doc.page(at: 1) else { return nil }
//
//    let rect = page.getBoxRect(.mediaBox)
//    let renderer = UIGraphicsImageRenderer(size: rect.size)
//    let img = renderer.image { ctx in
//        UIColor.white.set()
//        ctx.fill(rect)
//
//        ctx.cgContext.translateBy(x: 0, y: rect.size.height)
//        ctx.cgContext.scaleBy(x: 1, y: -1.0)
//
//        ctx.cgContext.drawPDFPage(page)
//    }
//
//    return Image(uiImage: img)
// }

extension View {
    /// Applies the given transform if the given condition evaluates to `true`.
    /// - Parameters:
    ///   - condition: The condition to evaluate.
    ///   - transform: The transform to apply to the source `View`.
    /// - Returns: Either the original `View` or the modified `View` if the condition is `true`.
    @ViewBuilder func `if`(_ condition: Bool, transform: (Self) -> some View) -> some View {
        if condition {
            transform(self)
        } else {
            self
        }
    }
}

struct ClearableModifier: ViewModifier {
    @Binding var text: String
    @FocusState var focused: Bool

    func body(content: Content) -> some View {
        HStack {
            content
                .focused($focused) // @TODO: This is probably not ideal if I want to manage focus externally.

            Spacer()

            Label(String(localized: .localizable(.clearText)), systemImage: "xmark.circle.fill")
                .labelStyle(.iconOnly)
                .foregroundColor(.gray)
                .onTapGesture {
                    text = ""
                    focused = true
                }
                .opacity(text.isEmpty ? 0 : 1)
        }
    }
}

extension TextField {
    func clearable(_ text: Binding<String>) -> some View {
        let m = ClearableModifier(text: text)
        return modifier(m)
    }
}

@propertyWrapper
struct EquatableNoop<Value>: Equatable {
    var wrappedValue: Value

    static func == (_: EquatableNoop<Value>, _: EquatableNoop<Value>) -> Bool {
        true
    }
}

extension EquatableNoop: Sendable where Value: Sendable {}

extension EquatableNoop: Codable where Value: Codable {
    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        wrappedValue = try container.decode(Value.self)
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(wrappedValue)
    }
}

func gather<Return: Sendable>(_ functions: (@Sendable () async -> Return)...) async -> [Return] {
    await gather(functions)
}

func gather(_ functions: (@Sendable () async -> Void)...) async {
    await gather(functions)
}

func gather<Return: Sendable>(_ functions: [@Sendable () async -> Return]) async -> [Return] {
    await withTaskGroup(of: Return.self, returning: [Return].self) { g in
        var result: [Return] = []
        for fn in functions {
            g.addTask { await fn() }
        }
        for await r in g {
            result.append(r)
        }
        return result
    }
}

func gather(_ functions: [@Sendable () async -> Void]) async {
    await withTaskGroup(of: Void.self) { g in
        for fn in functions {
            g.addTask { await fn() }
        }
    }
}
