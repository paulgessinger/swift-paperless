//
//  CorrespondentModel.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 21.05.23.
//

import Foundation
import MetaCodable

public protocol CorrespondentProtocol: Equatable, MatchingModel {
    var name: String { get set }
}

@Codable
@CodingKeys(.snake_case)
@MemberInit
public struct Correspondent:
    Hashable, Identifiable, Model, CorrespondentProtocol, Named,
    Sendable
{
    public var id: UInt
    @Default(nil as UInt?)
    public var documentCount: UInt?
    @Default(nil as Date?)
    public var lastCorrespondence: Date?
    public var name: String
    public var slug: String

    public var matchingAlgorithm: MatchingAlgorithm
    public var match: String
    public var isInsensitive: Bool
}

@Codable
@CodingKeys(.snake_case)
@MemberInit
public struct ProtoCorrespondent:
    CorrespondentProtocol,
    Hashable,
    Sendable
{
    @Default("")
    public var name: String

    @Default(MatchingAlgorithm.auto)
    public var matchingAlgorithm: MatchingAlgorithm

    @Default("")
    public var match: String

    @Default(false)
    public var isInsensitive: Bool
}
