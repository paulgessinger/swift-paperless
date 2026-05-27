//
//  ApiCustomField.swift
//  Networking
//

import DataModel

// MARK: - Wire type for reading custom fields

struct ApiCustomField: Codable, Sendable {
  var id: UInt
  var name: String
  var data_type: CustomFieldDataType
  var extra_data: ApiCustomFieldExtraData?
  var document_count: UInt?
}

extension ApiCustomField {
  var domain: CustomField {
    CustomField(
      id: id,
      name: name,
      dataType: data_type,
      extraData: extra_data?.domain ?? CustomFieldExtraData(),
      documentCount: document_count
    )
  }
}

struct ApiCustomFieldExtraData: Codable, Sendable {
  // The API has been observed to emit `null` elements inside select_options
  // (see paperless-ngx behaviour with non-select fields that still carry the
  // key); declare each element optional and filter at .domain.
  var select_options: [CustomFieldSelectOption?]?
  var default_currency: String?
}

extension ApiCustomFieldExtraData {
  var domain: CustomFieldExtraData {
    CustomFieldExtraData(
      selectOptions: (select_options ?? []).compactMap { $0 },
      defaultCurrency: default_currency
    )
  }
}
