// This file was autogenerated by `generate_filterrules.py` from
// https://raw.githubusercontent.com/paperless-ngx/paperless-ngx/dev/src-ui/src/app/data/filter-rule-type.ts
// Commit: f8d79b012fe9c49dd378d16065dcd28b34cc3967
// URL: https://github.com/paperless-ngx/paperless-ngx/commit/f8d79b012fe9c49dd378d16065dcd28b34cc3967
// Date: 2024-10-03T00:15:42Z
// DO NOT MODIFY BY HAND

import Foundation

enum FilterRuleType: RawRepresentable, Equatable, CaseIterable, Hashable {
  init?(rawValue: Int) {
    self =
      switch rawValue {
      case 0: .title
      case 1: .content
      case 2: .asn
      case 3: .correspondent
      case 4: .documentType
      case 5: .isInInbox
      case 6: .hasTagsAll
      case 7: .hasAnyTag
      case 8: .createdBefore
      case 9: .createdAfter
      case 10: .createdYear
      case 11: .createdMonth
      case 12: .createdDay
      case 13: .addedBefore
      case 14: .addedAfter
      case 15: .modifiedBefore
      case 16: .modifiedAfter
      case 17: .doesNotHaveTag
      case 18: .asnIsnull
      case 19: .titleContent
      case 20: .fulltextQuery
      case 21: .fulltextMorelike
      case 22: .hasTagsAny
      case 23: .asnGt
      case 24: .asnLt
      case 25: .storagePath
      case 26: .hasCorrespondentAny
      case 27: .doesNotHaveCorrespondent
      case 28: .hasDocumentTypeAny
      case 29: .doesNotHaveDocumentType
      case 30: .hasStoragePathAny
      case 31: .doesNotHaveStoragePath
      case 32: .owner
      case 33: .ownerAny
      case 34: .ownerIsnull
      case 35: .ownerDoesNotInclude
      case 36: .customFieldsText
      case 37: .sharedByUser
      case 38: .hasCustomFieldsAll
      case 39: .hasCustomFieldsAny
      case 40: .doesNotHaveCustomFields
      case 41: .hasAnyCustomFields
      case 42: .customFieldsQuery
      default: .other(rawValue)
      }
  }

  var rawValue: Int {
    switch self {
    case .title: 0
    case .content: 1
    case .asn: 2
    case .correspondent: 3
    case .hasCorrespondentAny: 26
    case .doesNotHaveCorrespondent: 27
    case .storagePath: 25
    case .hasStoragePathAny: 30
    case .doesNotHaveStoragePath: 31
    case .documentType: 4
    case .hasDocumentTypeAny: 28
    case .doesNotHaveDocumentType: 29
    case .isInInbox: 5
    case .hasTagsAll: 6
    case .hasTagsAny: 22
    case .doesNotHaveTag: 17
    case .hasAnyTag: 7
    case .createdBefore: 8
    case .createdAfter: 9
    case .createdYear: 10
    case .createdMonth: 11
    case .createdDay: 12
    case .addedBefore: 13
    case .addedAfter: 14
    case .modifiedBefore: 15
    case .modifiedAfter: 16
    case .asnIsnull: 18
    case .asnGt: 23
    case .asnLt: 24
    case .titleContent: 19
    case .fulltextQuery: 20
    case .fulltextMorelike: 21
    case .owner: 32
    case .ownerAny: 33
    case .ownerIsnull: 34
    case .ownerDoesNotInclude: 35
    case .sharedByUser: 37
    case .customFieldsText: 36
    case .hasCustomFieldsAll: 38
    case .hasCustomFieldsAny: 39
    case .doesNotHaveCustomFields: 40
    case .hasAnyCustomFields: 41
    case .customFieldsQuery: 42
    case let .other(value): value
    }
  }

  static let allCases: [FilterRuleType] = [
    .title,
    .content,
    .asn,
    .correspondent,
    .documentType,
    .isInInbox,
    .hasTagsAll,
    .hasAnyTag,
    .createdBefore,
    .createdAfter,
    .createdYear,
    .createdMonth,
    .createdDay,
    .addedBefore,
    .addedAfter,
    .modifiedBefore,
    .modifiedAfter,
    .doesNotHaveTag,
    .asnIsnull,
    .titleContent,
    .fulltextQuery,
    .fulltextMorelike,
    .hasTagsAny,
    .asnGt,
    .asnLt,
    .storagePath,
    .hasCorrespondentAny,
    .doesNotHaveCorrespondent,
    .hasDocumentTypeAny,
    .doesNotHaveDocumentType,
    .hasStoragePathAny,
    .doesNotHaveStoragePath,
    .owner,
    .ownerAny,
    .ownerIsnull,
    .ownerDoesNotInclude,
    .customFieldsText,
    .sharedByUser,
    .hasCustomFieldsAll,
    .hasCustomFieldsAny,
    .doesNotHaveCustomFields,
    .hasAnyCustomFields,
    .customFieldsQuery,
  ]

  enum DataType {
    case boolean
    case correspondent
    case date
    case documentType
    case number
    case storagePath
    case string
    case tag
  }

  case title
  case content
  case asn
  case correspondent
  case hasCorrespondentAny
  case doesNotHaveCorrespondent
  case storagePath
  case hasStoragePathAny
  case doesNotHaveStoragePath
  case documentType
  case hasDocumentTypeAny
  case doesNotHaveDocumentType
  case isInInbox
  case hasTagsAll
  case hasTagsAny
  case doesNotHaveTag
  case hasAnyTag
  case createdBefore
  case createdAfter
  case createdYear
  case createdMonth
  case createdDay
  case addedBefore
  case addedAfter
  case modifiedBefore
  case modifiedAfter
  case asnIsnull
  case asnGt
  case asnLt
  case titleContent
  case fulltextQuery
  case fulltextMorelike
  case owner
  case ownerAny
  case ownerIsnull
  case ownerDoesNotInclude
  case sharedByUser
  case customFieldsText
  case hasCustomFieldsAll
  case hasCustomFieldsAny
  case doesNotHaveCustomFields
  case hasAnyCustomFields
  case customFieldsQuery
  case other(Int)

  func filterVar() -> String? {
    switch self {
    case .title: "title__icontains"
    case .content: "content__icontains"
    case .asn: "archive_serial_number"
    case .correspondent: "correspondent__id"
    case .hasCorrespondentAny: "correspondent__id__in"
    case .doesNotHaveCorrespondent: "correspondent__id__none"
    case .storagePath: "storage_path__id"
    case .hasStoragePathAny: "storage_path__id__in"
    case .doesNotHaveStoragePath: "storage_path__id__none"
    case .documentType: "document_type__id"
    case .hasDocumentTypeAny: "document_type__id__in"
    case .doesNotHaveDocumentType: "document_type__id__none"
    case .isInInbox: "is_in_inbox"
    case .hasTagsAll: "tags__id__all"
    case .hasTagsAny: "tags__id__in"
    case .doesNotHaveTag: "tags__id__none"
    case .hasAnyTag: "is_tagged"
    case .createdBefore: "created__date__lt"
    case .createdAfter: "created__date__gt"
    case .createdYear: "created__year"
    case .createdMonth: "created__month"
    case .createdDay: "created__day"
    case .addedBefore: "added__date__lt"
    case .addedAfter: "added__date__gt"
    case .modifiedBefore: "modified__date__lt"
    case .modifiedAfter: "modified__date__gt"
    case .asnIsnull: "archive_serial_number__isnull"
    case .asnGt: "archive_serial_number__gt"
    case .asnLt: "archive_serial_number__lt"
    case .titleContent: "title_content"
    case .fulltextQuery: "query"
    case .fulltextMorelike: "more_like_id"
    case .owner: "owner__id"
    case .ownerAny: "owner__id__in"
    case .ownerIsnull: "owner__isnull"
    case .ownerDoesNotInclude: "owner__id__none"
    case .sharedByUser: "shared_by__id"
    case .customFieldsText: "custom_fields__icontains"
    case .hasCustomFieldsAll: "custom_fields__id__all"
    case .hasCustomFieldsAny: "custom_fields__id__in"
    case .doesNotHaveCustomFields: "custom_fields__id__none"
    case .hasAnyCustomFields: "has_custom_fields"
    case .customFieldsQuery: "custom_field_query"
    default: nil
    }
  }

  func dataType() -> DataType {
    switch self {
    case .title: .string
    case .content: .string
    case .asn: .number
    case .correspondent: .correspondent
    case .hasCorrespondentAny: .correspondent
    case .doesNotHaveCorrespondent: .correspondent
    case .storagePath: .storagePath
    case .hasStoragePathAny: .storagePath
    case .doesNotHaveStoragePath: .storagePath
    case .documentType: .documentType
    case .hasDocumentTypeAny: .documentType
    case .doesNotHaveDocumentType: .documentType
    case .isInInbox: .boolean
    case .hasTagsAll: .tag
    case .hasTagsAny: .tag
    case .doesNotHaveTag: .tag
    case .hasAnyTag: .boolean
    case .createdBefore: .date
    case .createdAfter: .date
    case .createdYear: .number
    case .createdMonth: .number
    case .createdDay: .number
    case .addedBefore: .date
    case .addedAfter: .date
    case .modifiedBefore: .date
    case .modifiedAfter: .date
    case .asnIsnull: .boolean
    case .asnGt: .number
    case .asnLt: .number
    case .titleContent: .string
    case .fulltextQuery: .string
    case .fulltextMorelike: .number
    case .owner: .number
    case .ownerAny: .number
    case .ownerIsnull: .boolean
    case .ownerDoesNotInclude: .number
    case .sharedByUser: .number
    case .customFieldsText: .string
    case .hasCustomFieldsAll: .number
    case .hasCustomFieldsAny: .number
    case .doesNotHaveCustomFields: .number
    case .hasAnyCustomFields: .boolean
    case .customFieldsQuery: .string
    default: .string
    }
  }

  func defaultValue() -> Bool {
    switch self {
    case .isInInbox: true
    case .hasAnyTag: true
    case .hasAnyCustomFields: true
    default: false
    }
  }

  func multiple() -> Bool {
    switch self {
    case .hasCorrespondentAny: true
    case .doesNotHaveCorrespondent: true
    case .hasStoragePathAny: true
    case .doesNotHaveStoragePath: true
    case .hasDocumentTypeAny: true
    case .doesNotHaveDocumentType: true
    case .hasTagsAll: true
    case .hasTagsAny: true
    case .doesNotHaveTag: true
    case .ownerAny: true
    case .ownerDoesNotInclude: true
    case .sharedByUser: true
    case .hasCustomFieldsAll: true
    case .hasCustomFieldsAny: true
    case .doesNotHaveCustomFields: true
    default: false
    }
  }

  static func allMultiples() -> Set<FilterRuleType> {
    [
      .hasCorrespondentAny,
      .doesNotHaveCorrespondent,
      .hasStoragePathAny,
      .doesNotHaveStoragePath,
      .hasDocumentTypeAny,
      .doesNotHaveDocumentType,
      .hasTagsAll,
      .hasTagsAny,
      .doesNotHaveTag,
      .ownerAny,
      .ownerDoesNotInclude,
      .sharedByUser,
      .hasCustomFieldsAll,
      .hasCustomFieldsAny,
      .doesNotHaveCustomFields,
    ]
  }

  func isNullFilterVar() -> String? {
    switch self {
    case .correspondent: "correspondent__isnull"
    case .storagePath: "storage_path__isnull"
    case .documentType: "document_type__isnull"
    default: nil
    }
  }
}
