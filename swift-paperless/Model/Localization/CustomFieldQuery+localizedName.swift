import DataModel

extension CustomFieldQuery.FieldOperator {
    var localizedName: String {
        switch self {
        case .exists: String(localized: .customFields(.queryExists))
        case .isnull: String(localized: .customFields(.queryIsNull))
        case .exact: String(localized: .customFields(.queryExact))
        case .gt: String(localized: .customFields(.queryGreaterThan))
        case .gte: String(localized: .customFields(.queryGreaterThanOrEqual))
        case .lt: String(localized: .customFields(.queryLessThan))
        case .lte: String(localized: .customFields(.queryLessThanOrEqual))
        case .in: String(localized: .customFields(.queryIn))
        case .contains: String(localized: .customFields(.queryContains))
        }
    }
}
