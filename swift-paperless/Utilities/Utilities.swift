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

class ThrottleObject<T: Equatable>: ObservableObject {
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

extension Color {
    enum HexError: Error {
        case invalid(String)
    }

    init(hex: String) throws {
        var string = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if string.hasPrefix("#") {
            _ = string.removeFirst()
        }

        if string.count != 6 {
            throw HexError.invalid(hex)
        }

        let scanner = Scanner(string: string)
        var color: UInt64 = 0
        scanner.scanHexInt64(&color)

        let mask = 0x0000FF
        let r = Double(Int(color >> 16) & mask) / 255.0
        let g = Double(Int(color >> 8) & mask) / 255.0
        let b = Double(Int(color) & mask) / 255.0

        self.init(.sRGB, red: r, green: g, blue: b)
    }

    var hexString: String {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0

        UIColor(self).getRed(&red, green: &green, blue: &blue, alpha: &alpha)

        let convert = { v in
            let vv = max(0.0, min(1.0, v))
            return UInt(vv > 0.99999 ? 255 : vv * 255.0)
        }

        return "#" + String(format: "%02x", convert(red)) +
            String(format: "%02x", convert(green)) +
            String(format: "%02x", convert(blue))
    }
}

struct HexColor: Equatable {
    var color: Color

    init(_ color: Color) {
        self.color = color
    }
}

extension HexColor: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let str = try container.decode(String.self)
        color = try Color(hex: str)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(color.hexString)
    }
}

extension Color {}

extension Color {
    static let systemBackground = Color(UIColor.systemBackground)
    static let systemGroupedBackground = Color(UIColor.systemGroupedBackground)
    static let secondarySystemGroupedBackground = Color(UIColor.secondarySystemGroupedBackground)
//    static func systemBackground() -> Color {
//        return Color(UIColor.systemBackground)
//    }
//
//    static func systemGroupedBackground() -> Color {
//        return Color(UIColor.systemGroupedBackground)
//    }

    var hex: HexColor {
        HexColor(self)
    }
}

extension Bundle {
    var icon: Image? {
        if let icons = infoDictionary?["CFBundleIcons"] as? [String: Any],
           let primaryIcon = icons["CFBundlePrimaryIcon"] as? [String: Any],
           let iconFiles = primaryIcon["CFBundleIconFiles"] as? [String],
           let lastIcon = iconFiles.last
        {
            if let uiImage = UIImage(named: lastIcon) {
                return Image(uiImage: uiImage)
            }
        }
        return nil
    }
}

// @TODO: Put this into a dispatch queue
func pdfPreview(url: URL) -> Image? {
    var fileSize: UInt64 = 0
    do {
        let attr = try FileManager.default.attributesOfItem(atPath: url.path)
        let dict = attr as NSDictionary
        fileSize = dict.fileSize()
    } catch {}

    if Bundle.main.bundlePath.hasSuffix(".appex") {
        if fileSize > 5 * 1024 * 1024 {
            Logger.shared.debug("Refusing to make PDF preview, file size is \(fileSize)")
            return nil
        }
    }

    guard let doc = CGPDFDocument(url as CFURL) else { return nil }
    guard let page = doc.page(at: 1) else { return nil }

    let rect = page.getBoxRect(.mediaBox)
    let renderer = UIGraphicsImageRenderer(size: rect.size)
    let img = renderer.image { ctx in
        UIColor.white.set()
        ctx.fill(rect)

        ctx.cgContext.translateBy(x: 0, y: rect.size.height)
        ctx.cgContext.scaleBy(x: 1, y: -1.0)

        ctx.cgContext.drawPDFPage(page)
    }

    return Image(uiImage: img)
}

struct ColorPalette_Previews: PreviewProvider {
    static let colors: [Color] = [
        .red,
        .systemBackground,
        .systemGroupedBackground,
        .secondarySystemGroupedBackground,
    ]

    static var previews: some View {
        VStack {
            ForEach(colors, id: \.self) {
                color in
                Rectangle().fill(color)
            }
        }
    }
}

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

struct Haptics {
    static let shared = Haptics()

    private var impactGenerators: [UIImpactFeedbackGenerator.FeedbackStyle: UIImpactFeedbackGenerator] = [:]

    private let notificationGenerator = UINotificationFeedbackGenerator()

    private init() {
        let styles = [UIImpactFeedbackGenerator.FeedbackStyle]([
            .light, .heavy, .medium, .rigid, .soft,
        ])

        for style in styles {
            impactGenerators[style] = UIImpactFeedbackGenerator(style: style)
        }
    }

    func prepare() {
        for (_, gen) in impactGenerators {
            gen.prepare()
        }
        notificationGenerator.prepare()
    }

    func notification(_ type: UINotificationFeedbackGenerator.FeedbackType) {
        notificationGenerator.notificationOccurred(type)
    }

    func impact(style: UIImpactFeedbackGenerator.FeedbackStyle) {
        guard let gen = impactGenerators[style] else {
            fatalError("Invalid feedback style")
        }
        gen.impactOccurred()
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

            Label("Clear text", systemImage: "xmark.circle.fill")
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

extension EquatableNoop: Codable where Value: Codable {
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        wrappedValue = try container.decode(Value.self)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(wrappedValue)
    }
}

func gather<Return>(_ functions: (() async -> Return)...) async -> [Return] {
    await gather(functions)
}

func gather(_ functions: (() async -> Void)...) async {
    await gather(functions)
}

func gather<Return>(_ functions: [() async -> Return]) async -> [Return] {
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

func gather(_ functions: [() async -> Void]) async {
    await withTaskGroup(of: Void.self) { g in
        for fn in functions {
            g.addTask { await fn() }
        }
    }
}
