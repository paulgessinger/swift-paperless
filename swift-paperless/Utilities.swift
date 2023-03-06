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

    init(delay: TimeInterval = 0.5) {
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
