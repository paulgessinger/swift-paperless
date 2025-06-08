import Common
@testable import DataModel
import Foundation
import Testing

struct TestFailure: Error {
    let message: String
    init(_ message: String) { self.message = message }
}

@Suite
struct CustomFieldInstanceTest {
    static let customFields: [UInt: CustomField] = [
        CustomField(id: 1, name: "Custom float", dataType: .float),
        CustomField(id: 2, name: "Custom bool", dataType: .boolean),
        CustomField(id: 4, name: "Custom integer", dataType: .integer),
        CustomField(id: 7, name: "Custom string", dataType: .string),
        CustomField(id: 3, name: "Custom date", dataType: .date),
        CustomField(id: 6, name: "Custom monetary", dataType: .monetary),
        CustomField(id: 5, name: "Custom monetary 2", dataType: .monetary),
        CustomField(id: 8, name: "Custom url", dataType: .url),
        CustomField(id: 9, name: "Custom doc link", dataType: .documentLink),
        CustomField(id: 10, name: "Custom select", dataType: .select, extraData: .init(selectOptions: [
            .init(id: "aa", label: "Option A"),
            .init(id: "bb", label: "Option B"),
            .init(id: "cc", label: "Option C"),
        ])),
    ].reduce(into: [UInt: CustomField]()) { $0[$1.id] = $1 }

    @Test("Test float field conversion")
    func testFloatFieldConversion() throws {
        let rawEntries = [CustomFieldRawEntry(field: 1, value: .float(123.45))]
        let instances = [CustomFieldInstance].fromRawEntries(rawEntries, customFields: Self.customFields)

        #expect(instances.count == 1)
        let instance = try #require(instances.first)
        #expect(instance.field.id == 1)
        #expect(instance.field.dataType == .float)

        #expect(instance.value == .float(123.45))
    }

    @Test("Test boolean field conversion")
    func testBooleanFieldConversion() throws {
        let rawEntries = [CustomFieldRawEntry(field: 2, value: .boolean(true))]
        let instances = [CustomFieldInstance].fromRawEntries(rawEntries, customFields: Self.customFields)

        #expect(instances.count == 1)
        let instance = try #require(instances.first)
        #expect(instance.field.id == 2)
        #expect(instance.field.dataType == .boolean)
        #expect(instance.value == .boolean(true))
    }

    @Test("Test date field conversion")
    func testDateFieldConversion() throws {
        let rawEntries = [CustomFieldRawEntry(field: 3, value: .string("2025-06-25"))]
        let instances = [CustomFieldInstance].fromRawEntries(rawEntries, customFields: Self.customFields)

        #expect(instances.count == 1)
        let instance = try #require(instances.first)
        #expect(instance.field.id == 3)
        #expect(instance.field.dataType == .date)

        let expectedDate = Calendar(identifier: .gregorian).date(from: DateComponents(
            year: 2025,
            month: 6,
            day: 25,
            hour: 0,
            minute: 0,
            second: 0
        ))!

        #expect(instance.value == .date(expectedDate))
    }

    @Test("Test integer field conversion")
    func testIntegerFieldConversion() throws {
        let rawEntries = [CustomFieldRawEntry(field: 4, value: .integer(42))]
        let instances = [CustomFieldInstance].fromRawEntries(rawEntries, customFields: Self.customFields)

        #expect(instances.count == 1)
        let instance = try #require(instances.first)
        #expect(instance.field.id == 4)
        #expect(instance.field.dataType == .integer)
        #expect(instance.value == .integer(42))
    }

    @Test("Test monetary field conversion")
    func testMonetaryFieldConversion() throws {
        let rawEntries = [
            CustomFieldRawEntry(field: 5, value: .string("USD1000.00")),
            CustomFieldRawEntry(field: 6, value: .string("EUR1000.00")),
        ]
        let instances = [CustomFieldInstance].fromRawEntries(rawEntries, customFields: Self.customFields)

        #expect(instances.count == 2)

        let usdInstance = try #require(instances.first { $0.field.id == 5 })
        #expect(usdInstance.field.dataType == .monetary)
        #expect(usdInstance.value == .monetary(currency: "USD", amount: Decimal(string: "1000.00")!))

        let eurInstance = try #require(instances.first { $0.field.id == 6 })
        #expect(eurInstance.field.dataType == .monetary)
        #expect(eurInstance.value == .monetary(currency: "EUR", amount: Decimal(string: "1000.00")!))
    }

    @Test("Test string field conversion")
    func testStringFieldConversion() throws {
        let rawEntries = [CustomFieldRawEntry(field: 7, value: .string("Super duper text"))]
        let instances = [CustomFieldInstance].fromRawEntries(rawEntries, customFields: Self.customFields)

        #expect(instances.count == 1)
        let instance = try #require(instances.first)
        #expect(instance.field.id == 7)
        #expect(instance.field.dataType == .string)
        #expect(instance.value == .string("Super duper text"))
    }

    @Test("Test URL field conversion")
    func testURLFieldConversion() throws {
        let rawEntries = [CustomFieldRawEntry(field: 8, value: .string("https://paperless-ngx.com"))]
        let instances = [CustomFieldInstance].fromRawEntries(rawEntries, customFields: Self.customFields)

        #expect(instances.count == 1)
        let instance = try #require(instances.first)
        #expect(instance.field.id == 8)
        #expect(instance.field.dataType == .url)
        #expect(instance.value == .url(#URL("https://paperless-ngx.com")))
    }

    @Test("Test document link field conversion")
    func testDocumentLinkFieldConversion() throws {
        let rawEntries = [CustomFieldRawEntry(field: 9, value: .idList([1, 6]))]
        let instances = [CustomFieldInstance].fromRawEntries(rawEntries, customFields: Self.customFields)

        #expect(instances.count == 1)
        let instance = try #require(instances.first)
        #expect(instance.field.id == 9)
        #expect(instance.field.dataType == .documentLink)
        #expect(instance.value == .documentLink([1, 6]))
    }

    @Test("Test select field conversion")
    func testSelectFieldConversion() throws {
        let rawEntries = [CustomFieldRawEntry(field: 10, value: .string("bb"))]
        let instances = [CustomFieldInstance].fromRawEntries(rawEntries, customFields: Self.customFields)

        #expect(instances.count == 1)
        let instance = try #require(instances.first)
        #expect(instance.field.id == 10)
        #expect(instance.field.dataType == .select)
        #expect(instance.value == .select(CustomField.SelectOption(id: "bb", label: "Option B")))
    }
}
