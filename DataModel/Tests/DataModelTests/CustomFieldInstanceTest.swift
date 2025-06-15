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
        let rawEntry = CustomFieldRawEntry(field: 5, value: .string("ABCD1000"))
        let instance = CustomFieldInstance(
            field: Self.customFields[5]!, rawValue: rawEntry.value, locale: Self.locale
        )
        #expect(instance.value == .invalid(.invalidMonetary("ABCD1000")))
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
            CustomFieldRawEntry(field: 8, value: .string("")),
        ]
        let instances = [CustomFieldInstance].fromRawEntries(
            rawEntries, customFields: Self.customFields, locale: Self.locale
        )

        try #require(instances.count == 2)

        // Test valid URL
        let validInstance = try #require(instances.first)
        #expect(validInstance.field.id == 8)
        #expect(validInstance.field.dataType == .url)
        #expect(validInstance.value == .url(#URL("https://paperless-ngx.com")))

        // Test nil URL
        let nilInstance = try #require(instances.last)
        #expect(nilInstance.field.id == 8)
        #expect(nilInstance.field.dataType == .url)
        #expect(nilInstance.value == .url(nil))

        // Test conversion back to raw entries
        let rawEntries2 = instances.map(\.rawEntry)
        #expect(rawEntries2[0].value == .string("https://paperless-ngx.com"))
        #expect(rawEntries2[1].value == .string(""))
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
        // Test valid select option
        let rawEntries = [CustomFieldRawEntry(field: 10, value: .string("bb"))]
        let instances = [CustomFieldInstance].fromRawEntries(
            rawEntries, customFields: Self.customFields, locale: Self.locale
        )

        #expect(instances.count == 1)
        let instance = try #require(instances.first)
        #expect(instance.field.id == 10)
        #expect(instance.field.dataType == .select)
        #expect(instance.value == .select(CustomField.SelectOption(id: "bb", label: "Option B")))

        // Test nil select option
        let nilRawEntries = [CustomFieldRawEntry(field: 10, value: .none)]
        let nilInstances = [CustomFieldInstance].fromRawEntries(
            nilRawEntries, customFields: Self.customFields, locale: Self.locale
        )

        #expect(nilInstances.count == 1)
        let nilInstance = try #require(nilInstances.first)
        #expect(nilInstance.field.id == 10)
        #expect(nilInstance.field.dataType == .select)
        #expect(nilInstance.value == .select(nil))
    }

    @Test("Test select field to raw entry conversion")
    func testSelectFieldToRawEntry() throws {
        // Test valid select option
        let instance =
            CustomFieldInstance(
                field: Self.customFields[10]!,
                value: .select(CustomField.SelectOption(id: "bb", label: "Option B"))
            )
        let rawEntry = instance.rawEntry

        #expect(rawEntry.field == 10)
        #expect(rawEntry.value == .string("bb"))

        // Test nil select option
        let nilInstance = try #require(
            CustomFieldInstance(
                field: Self.customFields[10]!,
                value: .select(nil)
            ))
        let nilRawEntry = nilInstance.rawEntry

        #expect(nilRawEntry.field == 10)
        #expect(nilRawEntry.value == .none)
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
        let nilSelect = CustomFieldInstance(
            field: selectField,
            value: .select(nil)
        )
        #expect(validSelect.isValid)
        #expect(!invalidSelect.isValid)
        #expect(nilSelect.isValid)

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
        #expect(validMonetary.isValid)
        #expect(!invalidMonetary.isValid)
    }

    @Test("Test in-place modification validation")
    func testInPlaceModificationValidation() throws {
        // Test select field modification
        let selectField = try #require(Self.customFields[10])
        var selectInstance =
            CustomFieldInstance(
                field: selectField,
                value: .select(CustomField.SelectOption(id: "bb", label: "Option B"))
            )
        #expect(selectInstance.isValid)

        // Modify to invalid option
        selectInstance.value = .select(CustomField.SelectOption(id: "invalid", label: "Invalid"))
        #expect(!selectInstance.isValid)

        // Modify to nil option (should be valid)
        selectInstance.value = .select(nil)
        #expect(selectInstance.isValid)

        // Test monetary field modification
        let monetaryField = try #require(Self.customFields[5])
        var monetaryInstance =
            CustomFieldInstance(
                field: monetaryField,
                value: .monetary(currency: "USD", amount: 100)
            )
        #expect(monetaryInstance.isValid)

        // Modify to invalid currency
        monetaryInstance.value = .monetary(currency: "usd", amount: 100)
        #expect(!monetaryInstance.isValid)

        // Test type mismatch modification
        var stringInstance =
            CustomFieldInstance(
                field: Self.customFields[7]!,
                value: .string("test")
            )
        #expect(stringInstance.isValid)

        // Modify to wrong type
        stringInstance.value = .boolean(true)
        #expect(!stringInstance.isValid)
    }

    @Test("Test initialization with unknown value")
    func testInitializationWithUnknownValue() throws {
        let field = try #require(Self.customFields[7]) // string field
        let instance = CustomFieldInstance(
            field: field,
            rawValue: .unknown,
            locale: Self.locale
        )
        #expect(instance.value == .invalid(.unknownValue))
    }

    @Test("Test initialization with other data type")
    func testInitializationWithOtherDataType() throws {
        let field = CustomField(
            id: 11,
            name: "Other field",
            dataType: .other("unknown")
        )
        let instance = CustomFieldInstance(
            field: field,
            rawValue: .string("test"),
            locale: Self.locale
        )
        #expect(instance.value == .invalid(.unknownDataType("unknown")))
    }

    @Test("Test invalid field values")
    func testInvalidFieldValues() throws {
        // Test invalid date
        let dateField = try #require(Self.customFields[3])
        let invalidDate = CustomFieldInstance(
            field: dateField,
            rawValue: .string("not-a-date"),
            locale: Self.locale
        )
        #expect(invalidDate.value == .invalid(.invalidDate("not-a-date")))

        // Test invalid URL
        let urlField = try #require(Self.customFields[8])
        let invalidURL = CustomFieldInstance(
            field: urlField,
            rawValue: .string("+blurp:/bla"),
            locale: Self.locale
        )
        #expect(invalidURL.value == .invalid(.invalidURL("+blurp:/bla")))

        // Test invalid monetary format
        let monetaryField = try #require(Self.customFields[5])
        let invalidMonetaryFormat = CustomFieldInstance(
            field: monetaryField,
            rawValue: .string("not-a-monetary"),
            locale: Self.locale
        )
        #expect(invalidMonetaryFormat.value == .invalid(.invalidMonetary("not-a-monetary")))

        // Test invalid monetary amount
        let invalidMonetaryAmount = CustomFieldInstance(
            field: monetaryField,
            rawValue: .string("USD1.1"),
            locale: Self.locale
        )
        #expect(invalidMonetaryAmount.value == .invalid(.invalidMonetary("USD1.1")))

        // Test invalid select option
        let selectField = try #require(Self.customFields[10])
        let invalidSelect = CustomFieldInstance(
            field: selectField,
            rawValue: .string("invalid-option"),
            locale: Self.locale
        )
        #expect(invalidSelect.value == .invalid(.invalidSelectOption("invalid-option")))

        // Test unknown value
        let unknownValue = CustomFieldInstance(
            field: dateField,
            rawValue: .unknown,
            locale: Self.locale
        )
        #expect(unknownValue.value == .invalid(.unknownValue))

        // Test unknown data type
        let otherField = CustomField(
            id: 11,
            name: "Other field",
            dataType: .other("unknown")
        )
        let unknownDataType = CustomFieldInstance(
            field: otherField,
            rawValue: .string("test"),
            locale: Self.locale
        )
        #expect(unknownDataType.value == .invalid(.unknownDataType("unknown")))

        // Test type mismatch
        let typeMismatch = CustomFieldInstance(
            field: dateField,
            rawValue: .boolean(true),
            locale: Self.locale
        )
        #expect(
            typeMismatch.value == .invalid(.typeMismatch(dataType: .date, value: .boolean(true))))
    }
}

@Suite
struct CustomFieldInstanceToRawEntryTest {
    static let customFields: [UInt: CustomField] = CustomFieldInstanceTest.customFields

    @Test("Test float field conversion to raw entry")
    func testFloatFieldToRawEntry() throws {
        let instance =
            CustomFieldInstance(
                field: Self.customFields[1]!,
                value: .float(123.45)
            )
        let rawEntry = instance.rawEntry

        #expect(rawEntry.field == 1)
        #expect(rawEntry.value == .float(123.45))
    }

    @Test("Test boolean field conversion to raw entry")
    func testBooleanFieldToRawEntry() throws {
        let instance =
            CustomFieldInstance(
                field: Self.customFields[2]!,
                value: .boolean(true)
            )
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

        let instance =
            CustomFieldInstance(
                field: Self.customFields[3]!,
                value: .date(date)
            )
        let rawEntry = instance.rawEntry

        #expect(rawEntry.field == 3)
        #expect(rawEntry.value == .string("2025-06-25"))
    }

    @Test("Test integer field conversion to raw entry")
    func testIntegerFieldToRawEntry() throws {
        let instance =
            CustomFieldInstance(
                field: Self.customFields[4]!,
                value: .integer(42)
            )
        let rawEntry = instance.rawEntry

        #expect(rawEntry.field == 4)
        #expect(rawEntry.value == .integer(42))
    }

    @Test("Test monetary field conversion to raw entry")
    func testMonetaryFieldToRawEntry() throws {
        let usdInstance =
            CustomFieldInstance(
                field: Self.customFields[5]!,
                value: .monetary(currency: "USD", amount: Decimal(string: "1000.00")!)
            )
        let eurInstance =
            CustomFieldInstance(
                field: Self.customFields[6]!,
                value: .monetary(currency: "EUR", amount: Decimal(string: "1000.00")!)
            )

        let usdRawEntry = usdInstance.rawEntry
        let eurRawEntry = eurInstance.rawEntry

        #expect(usdRawEntry.field == 5)
        #expect(usdRawEntry.value == .string("USD1000.00"))
        #expect(eurRawEntry.field == 6)
        #expect(eurRawEntry.value == .string("EUR1000.00"))
    }

    @Test("Test string field conversion to raw entry")
    func testStringFieldToRawEntry() throws {
        let instance =
            CustomFieldInstance(
                field: Self.customFields[7]!,
                value: .string("Super duper text")
            )
        let rawEntry = instance.rawEntry

        #expect(rawEntry.field == 7)
        #expect(rawEntry.value == .string("Super duper text"))
    }

    @Test("Test URL field conversion to raw entry")
    func testURLFieldToRawEntry() throws {
        let instance =
            CustomFieldInstance(
                field: Self.customFields[8]!,
                value: .url(#URL("https://paperless-ngx.com"))
            )
        let rawEntry = instance.rawEntry

        #expect(rawEntry.field == 8)
        #expect(rawEntry.value == .string("https://paperless-ngx.com"))
    }

    @Test("Test document link field conversion to raw entry")
    func testDocumentLinkFieldToRawEntry() throws {
        let instance =
            CustomFieldInstance(
                field: Self.customFields[9]!,
                value: .documentLink([1, 6])
            )
        let rawEntry = instance.rawEntry

        #expect(rawEntry.field == 9)
        #expect(rawEntry.value == .idList([1, 6]))
    }

    @Test("Test select field conversion to raw entry")
    func testSelectFieldToRawEntry() throws {
        let instance =
            CustomFieldInstance(
                field: Self.customFields[10]!,
                value: .select(CustomField.SelectOption(id: "bb", label: "Option B"))
            )
        let rawEntry = instance.rawEntry

        #expect(rawEntry.field == 10)
        #expect(rawEntry.value == .string("bb"))
    }
}
