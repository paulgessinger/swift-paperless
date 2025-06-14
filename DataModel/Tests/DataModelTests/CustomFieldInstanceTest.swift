import Common
import Foundation
import Testing

@testable import DataModel

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
        CustomField(
            id: 6, name: "Custom monetary", dataType: .monetary,
            extraData: .init(defaultCurrency: "NOK")
        ),
        CustomField(id: 5, name: "Custom monetary 2", dataType: .monetary),
        CustomField(id: 8, name: "Custom url", dataType: .url),
        CustomField(id: 9, name: "Custom doc link", dataType: .documentLink),
        CustomField(
            id: 10, name: "Custom select", dataType: .select,
            extraData: .init(selectOptions: [
                .init(id: "aa", label: "Option A"),
                .init(id: "bb", label: "Option B"),
                .init(id: "cc", label: "Option C"),
            ])
        ),
    ].reduce(into: [UInt: CustomField]()) { $0[$1.id] = $1 }

    static let locale = Locale(identifier: "en_US")

    @Test("Test float field conversion")
    func testFloatFieldConversion() throws {
        let rawEntries = [CustomFieldRawEntry(field: 1, value: .float(123.45))]
        let instances = [CustomFieldInstance].fromRawEntries(
            rawEntries, customFields: Self.customFields, locale: Self.locale
        )

        #expect(instances.count == 1)
        let instance = try #require(instances.first)
        #expect(instance.field.id == 1)
        #expect(instance.field.dataType == .float)

        #expect(instance.value == .float(123.45))
    }

    @Test("Test boolean field conversion")
    func testBooleanFieldConversion() throws {
        let rawEntries = [CustomFieldRawEntry(field: 2, value: .boolean(true))]
        let instances = [CustomFieldInstance].fromRawEntries(
            rawEntries, customFields: Self.customFields, locale: Self.locale
        )

        #expect(instances.count == 1)
        let instance = try #require(instances.first)
        #expect(instance.field.id == 2)
        #expect(instance.field.dataType == .boolean)
        #expect(instance.value == .boolean(true))
    }

    @Test("Test date field conversion")
    func testDateFieldConversion() throws {
        let rawEntries = [CustomFieldRawEntry(field: 3, value: .string("2025-06-25"))]
        let instances = [CustomFieldInstance].fromRawEntries(
            rawEntries, customFields: Self.customFields, locale: Self.locale
        )

        #expect(instances.count == 1)
        let instance = try #require(instances.first)
        #expect(instance.field.id == 3)
        #expect(instance.field.dataType == .date)

        let expectedDate = Calendar(identifier: .gregorian).date(
            from: DateComponents(
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
        let instances = [CustomFieldInstance].fromRawEntries(
            rawEntries, customFields: Self.customFields, locale: Self.locale
        )

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
        let instances = [CustomFieldInstance].fromRawEntries(
            rawEntries, customFields: Self.customFields, locale: Self.locale
        )

        #expect(instances.count == 2)

        let usdInstance = try #require(instances.first { $0.field.id == 5 })
        #expect(usdInstance.field.dataType == .monetary)
        #expect(
            usdInstance.value == .monetary(currency: "USD", amount: Decimal(string: "1000.00")!))

        let eurInstance = try #require(instances.first { $0.field.id == 6 })
        #expect(eurInstance.field.dataType == .monetary)
        #expect(
            eurInstance.value == .monetary(currency: "EUR", amount: Decimal(string: "1000.00")!))
    }

    @Test("Test monetary field with invalid currency")
    func testMonetaryFieldWithInvalidCurrency() throws {
        let rawEntries = [CustomFieldRawEntry(field: 5, value: .string("ABCD1000"))]
        let instances = [CustomFieldInstance].fromRawEntries(
            rawEntries, customFields: Self.customFields, locale: Self.locale
        )
        #expect(instances.isEmpty)
    }

    @Test("Test monetary field without decimals")
    func testMonetaryFieldWithoutDecimals() throws {
        let rawEntries = [CustomFieldRawEntry(field: 5, value: .string("AUD1000"))]
        let instance = try #require(
            [CustomFieldInstance].fromRawEntries(
                rawEntries, customFields: Self.customFields, locale: Self.locale
            ).first)

        #expect(instance.field.id == 5)
        #expect(instance.field.dataType == .monetary)
        #expect(instance.value == .monetary(currency: "AUD", amount: Decimal(string: "1000")!))
    }

    @Test("Test monetary field conversion without currency")
    func testMonetaryFieldConversionWithoutCurrency() throws {
        // Current locale determines currency
        let rawEntries = [CustomFieldRawEntry(field: 5, value: .string("1000.00"))]
        let instance = try #require(
            [CustomFieldInstance].fromRawEntries(
                rawEntries, customFields: Self.customFields, locale: Locale(identifier: "en_CA")
            ).first)

        #expect(instance.field.id == 5)
        #expect(instance.field.dataType == .monetary)
        #expect(instance.value == .monetary(currency: "CAD", amount: Decimal(string: "1000.00")!))

        // Explicitly default currency
        let rawEntries2 = [CustomFieldRawEntry(field: 6, value: .string("1000.00"))]
        let instance2 = try #require(
            [CustomFieldInstance].fromRawEntries(
                rawEntries2, customFields: Self.customFields, locale: Self.locale
            ).first
        )

        #expect(instance2.field.id == 6)
        #expect(instance2.field.dataType == .monetary)
        #expect(instance2.value == .monetary(currency: "NOK", amount: Decimal(string: "1000.00")!))
    }

    @Test("Test string field conversion")
    func testStringFieldConversion() throws {
        let rawEntries = [CustomFieldRawEntry(field: 7, value: .string("Super duper text"))]
        let instances = [CustomFieldInstance].fromRawEntries(
            rawEntries, customFields: Self.customFields, locale: Self.locale
        )

        #expect(instances.count == 1)
        let instance = try #require(instances.first)
        #expect(instance.field.id == 7)
        #expect(instance.field.dataType == .string)
        #expect(instance.value == .string("Super duper text"))
    }

    @Test("Test URL field conversion")
    func testURLFieldConversion() throws {
        let rawEntries = [
            CustomFieldRawEntry(field: 8, value: .string("https://paperless-ngx.com")),
        ]
        let instances = [CustomFieldInstance].fromRawEntries(
            rawEntries, customFields: Self.customFields, locale: Self.locale
        )

        #expect(instances.count == 1)
        let instance = try #require(instances.first)
        #expect(instance.field.id == 8)
        #expect(instance.field.dataType == .url)
        #expect(instance.value == .url(#URL("https://paperless-ngx.com")))
    }

    @Test("Test document link field conversion")
    func testDocumentLinkFieldConversion() throws {
        let rawEntries = [CustomFieldRawEntry(field: 9, value: .idList([1, 6]))]
        let instances = [CustomFieldInstance].fromRawEntries(
            rawEntries, customFields: Self.customFields, locale: Self.locale
        )

        #expect(instances.count == 1)
        let instance = try #require(instances.first)
        #expect(instance.field.id == 9)
        #expect(instance.field.dataType == .documentLink)
        #expect(instance.value == .documentLink([1, 6]))
    }

    @Test("Test select field conversion")
    func testSelectFieldConversion() throws {
        let rawEntries = [CustomFieldRawEntry(field: 10, value: .string("bb"))]
        let instances = [CustomFieldInstance].fromRawEntries(
            rawEntries, customFields: Self.customFields, locale: Self.locale
        )

        #expect(instances.count == 1)
        let instance = try #require(instances.first)
        #expect(instance.field.id == 10)
        #expect(instance.field.dataType == .select)
        #expect(instance.value == .select(CustomField.SelectOption(id: "bb", label: "Option B")))
    }

    @Test("Test nil initializer with type mismatch")
    func testNilInitializerWithTypeMismatch() throws {
        // String field with boolean value
        let stringField = try #require(Self.customFields[7])
        let stringInstance = CustomFieldInstance(field: stringField, value: .boolean(true))
        #expect(stringInstance == nil)

        // Boolean field with integer value
        let boolField = try #require(Self.customFields[2])
        let boolInstance = CustomFieldInstance(field: boolField, value: .integer(42))
        #expect(boolInstance == nil)

        // Date field with float value
        let dateField = try #require(Self.customFields[3])
        let dateInstance = CustomFieldInstance(field: dateField, value: .float(123.45))
        #expect(dateInstance == nil)

        // Select field with URL value
        let selectField = try #require(Self.customFields[10])
        let selectInstance = CustomFieldInstance(
            field: selectField, value: .url(#URL("https://example.com"))
        )
        #expect(selectInstance == nil)
    }

    @Test("Test field validation")
    func testFieldValidation() throws {
        // Test select field validation
        let selectField = try #require(Self.customFields[10])
        let validSelect = CustomFieldInstance(
            field: selectField,
            value: .select(CustomField.SelectOption(id: "bb", label: "Option B"))
        )
        let invalidSelect = CustomFieldInstance(
            field: selectField,
            value: .select(CustomField.SelectOption(id: "invalid", label: "Invalid"))
        )
        #expect(validSelect != nil)
        #expect(invalidSelect == nil)

        // Test monetary field validation
        let monetaryField = try #require(Self.customFields[5])
        let validMonetary = CustomFieldInstance(
            field: monetaryField,
            value: .monetary(currency: "USD", amount: 100)
        )
        let invalidMonetary = CustomFieldInstance(
            field: monetaryField,
            value: .monetary(currency: "usd", amount: 100)
        )
        #expect(validMonetary != nil)
        #expect(invalidMonetary == nil)
    }

    @Test("Test in-place modification validation")
    func testInPlaceModificationValidation() throws {
        // Test select field modification
        let selectField = try #require(Self.customFields[10])
        var selectInstance = try #require(
            CustomFieldInstance(
                field: selectField,
                value: .select(CustomField.SelectOption(id: "bb", label: "Option B"))
            ))
        #expect(selectInstance.isValid)

        // Modify to invalid option
        selectInstance.value = .select(CustomField.SelectOption(id: "invalid", label: "Invalid"))
        #expect(!selectInstance.isValid)

        // Test monetary field modification
        let monetaryField = try #require(Self.customFields[5])
        var monetaryInstance = try #require(
            CustomFieldInstance(
                field: monetaryField,
                value: .monetary(currency: "USD", amount: 100)
            ))
        #expect(monetaryInstance.isValid)

        // Modify to invalid currency
        monetaryInstance.value = .monetary(currency: "usd", amount: 100)
        #expect(!monetaryInstance.isValid)

        // Test type mismatch modification
        var stringInstance = try #require(
            CustomFieldInstance(
                field: Self.customFields[7]!,
                value: .string("test")
            ))
        #expect(stringInstance.isValid)

        // Modify to wrong type
        stringInstance.value = .boolean(true)
        #expect(!stringInstance.isValid)
    }
}

@Suite
struct CustomFieldInstanceToRawEntryTest {
    static let customFields: [UInt: CustomField] = CustomFieldInstanceTest.customFields

    @Test("Test float field conversion to raw entry")
    func testFloatFieldToRawEntry() throws {
        let instance = try #require(
            CustomFieldInstance(
                field: Self.customFields[1]!,
                value: .float(123.45)
            ))
        let rawEntry = instance.rawEntry

        #expect(rawEntry.field == 1)
        #expect(rawEntry.value == .float(123.45))
    }

    @Test("Test boolean field conversion to raw entry")
    func testBooleanFieldToRawEntry() throws {
        let instance = try #require(
            CustomFieldInstance(
                field: Self.customFields[2]!,
                value: .boolean(true)
            ))
        let rawEntry = instance.rawEntry

        #expect(rawEntry.field == 2)
        #expect(rawEntry.value == .boolean(true))
    }

    @Test("Test date field conversion to raw entry")
    func testDateFieldToRawEntry() throws {
        let date = Calendar(identifier: .gregorian).date(
            from: DateComponents(
                year: 2025,
                month: 6,
                day: 25,
                hour: 0,
                minute: 0,
                second: 0
            ))!

        let instance = try #require(
            CustomFieldInstance(
                field: Self.customFields[3]!,
                value: .date(date)
            ))
        let rawEntry = instance.rawEntry

        #expect(rawEntry.field == 3)
        #expect(rawEntry.value == .string("2025-06-25"))
    }

    @Test("Test integer field conversion to raw entry")
    func testIntegerFieldToRawEntry() throws {
        let instance = try #require(
            CustomFieldInstance(
                field: Self.customFields[4]!,
                value: .integer(42)
            ))
        let rawEntry = instance.rawEntry

        #expect(rawEntry.field == 4)
        #expect(rawEntry.value == .integer(42))
    }

    @Test("Test monetary field conversion to raw entry")
    func testMonetaryFieldToRawEntry() throws {
        let usdInstance = try #require(
            CustomFieldInstance(
                field: Self.customFields[5]!,
                value: .monetary(currency: "USD", amount: Decimal(string: "1000.00")!)
            ))
        let eurInstance = try #require(
            CustomFieldInstance(
                field: Self.customFields[6]!,
                value: .monetary(currency: "EUR", amount: Decimal(string: "1000.00")!)
            ))

        let usdRawEntry = usdInstance.rawEntry
        let eurRawEntry = eurInstance.rawEntry

        #expect(usdRawEntry.field == 5)
        #expect(usdRawEntry.value == .string("USD1000.00"))
        #expect(eurRawEntry.field == 6)
        #expect(eurRawEntry.value == .string("EUR1000.00"))
    }

    @Test("Test string field conversion to raw entry")
    func testStringFieldToRawEntry() throws {
        let instance = try #require(
            CustomFieldInstance(
                field: Self.customFields[7]!,
                value: .string("Super duper text")
            ))
        let rawEntry = instance.rawEntry

        #expect(rawEntry.field == 7)
        #expect(rawEntry.value == .string("Super duper text"))
    }

    @Test("Test URL field conversion to raw entry")
    func testURLFieldToRawEntry() throws {
        let instance = try #require(
            CustomFieldInstance(
                field: Self.customFields[8]!,
                value: .url(#URL("https://paperless-ngx.com"))
            ))
        let rawEntry = instance.rawEntry

        #expect(rawEntry.field == 8)
        #expect(rawEntry.value == .string("https://paperless-ngx.com"))
    }

    @Test("Test document link field conversion to raw entry")
    func testDocumentLinkFieldToRawEntry() throws {
        let instance = try #require(
            CustomFieldInstance(
                field: Self.customFields[9]!,
                value: .documentLink([1, 6])
            ))
        let rawEntry = instance.rawEntry

        #expect(rawEntry.field == 9)
        #expect(rawEntry.value == .idList([1, 6]))
    }

    @Test("Test select field conversion to raw entry")
    func testSelectFieldToRawEntry() throws {
        let instance = try #require(
            CustomFieldInstance(
                field: Self.customFields[10]!,
                value: .select(CustomField.SelectOption(id: "bb", label: "Option B"))
            ))
        let rawEntry = instance.rawEntry

        #expect(rawEntry.field == 10)
        #expect(rawEntry.value == .string("bb"))
    }
}
