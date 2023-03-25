//
//  Utilities.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 22.02.23.
//

import Combine
import Foundation
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

extension Text {
    static func titleCorrespondent(value: Correspondent?) -> Text {
        if let correspondent = value {
            return Text("\(correspondent.name): ")
//                .bold()
                .foregroundColor(.accentColor)
        }
        else {
            return Text("")
        }
    }

    static func titleDocumentType(value: DocumentType?) -> Text {
        if let documentType = value {
            return Text("\(documentType.name)")
//                .bold()
                .foregroundColor(.orange)
        }
        else {
            return Text("")
        }
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

    var hex: String {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0

        UIColor(self).getRed(&red, green: &green, blue: &blue, alpha: &alpha)

        let convert = { v in UInt(v > 0.99999 ? 255 : v * 255.0) }

        return ("#" + String(format: "%02x", convert(red)) +
            String(format: "%02x", convert(green)) +
            String(format: "%02x", convert(blue)))
    }
}

@propertyWrapper
struct HexColor {
    var wrappedValue: Color
}

extension HexColor: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let str = try container.decode(String.self)
        wrappedValue = try Color(hex: str)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(wrappedValue.hex)
    }
}

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
        .secondarySystemGroupedBackground
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
    @ViewBuilder func `if`<Content: View>(_ condition: Bool, transform: (Self) -> Content) -> some View {
        if condition {
            transform(self)
        }
        else {
            self
        }
    }
}
