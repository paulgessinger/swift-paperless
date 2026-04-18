//
//  ApiRepository+Send.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 18.04.26.
//

import Common
import DataModel
import Foundation
import os

enum HttpMethod: String {
  case get = "GET"
  case post = "POST"
  case patch = "PATCH"
  case put = "PUT"
  case delete = "DELETE"
}

extension ApiRepository {
  fileprivate func buildRequest(
    _ method: HttpMethod, endpoint: Endpoint, jsonBody: Data?
  ) throws -> URLRequest {
    var request = try request(endpoint)
    request.httpMethod = method.rawValue
    if let jsonBody {
      request.setValue("application/json", forHTTPHeaderField: "Content-Type")
      request.httpBody = jsonBody
    }
    return request
  }

  // Typed response, no body.
  func send<Response: Decodable>(
    _ method: HttpMethod = .get,
    endpoint: Endpoint,
    expectedStatus: HTTPStatusCode = .ok,
    returns: Response.Type
  ) async throws -> Response {
    let request = try buildRequest(method, endpoint: endpoint, jsonBody: nil)
    do {
      return try await fetchData(for: request, as: returns, expectedStatus: expectedStatus)
    } catch {
      Logger.networking.error(
        "Api \(method.rawValue, privacy: .public) \(returns) failed: \(error)")
      throw error
    }
  }

  // Typed response, with body.
  func send<Response: Decodable>(
    _ method: HttpMethod,
    endpoint: Endpoint,
    body: some Encodable,
    expectedStatus: HTTPStatusCode = .ok,
    returns: Response.Type
  ) async throws -> Response {
    let request = try buildRequest(
      method, endpoint: endpoint, jsonBody: encoder.encode(body))
    do {
      return try await fetchData(for: request, as: returns, expectedStatus: expectedStatus)
    } catch {
      Logger.networking.error(
        "Api \(method.rawValue, privacy: .public) \(returns) failed: \(error)")
      throw error
    }
  }

  // Void response, no body.
  func send(
    _ method: HttpMethod,
    endpoint: Endpoint,
    expectedStatus: HTTPStatusCode = .ok
  ) async throws {
    let request = try buildRequest(method, endpoint: endpoint, jsonBody: nil)
    do {
      _ = try await fetchData(for: request, expectedStatus: expectedStatus)
    } catch {
      Logger.networking.error(
        "Api \(method.rawValue, privacy: .public) failed: \(error)")
      throw error
    }
  }

  // Void response, with body.
  func send(
    _ method: HttpMethod,
    endpoint: Endpoint,
    body: some Encodable,
    expectedStatus: HTTPStatusCode = .ok
  ) async throws {
    let request = try buildRequest(
      method, endpoint: endpoint, jsonBody: encoder.encode(body))
    do {
      _ = try await fetchData(for: request, expectedStatus: expectedStatus)
    } catch {
      Logger.networking.error(
        "Api \(method.rawValue, privacy: .public) failed: \(error)")
      throw error
    }
  }

  func create<Element>(element: some Encodable, endpoint: Endpoint, returns: Element.Type)
    async throws -> Element where Element: Decodable
  {
    try await send(
      .post, endpoint: endpoint, body: element, expectedStatus: .created, returns: returns)
  }

  func update<Element>(element: Element, endpoint: Endpoint) async throws -> Element
  where Element: Codable {
    try await send(.patch, endpoint: endpoint, body: element, returns: Element.self)
  }

  func update<Response: Decodable>(
    element: some Encodable, endpoint: Endpoint, returns: Response.Type
  ) async throws -> Response {
    try await send(.patch, endpoint: endpoint, body: element, returns: returns)
  }

  func get<T: Decodable>(
    _ type: T.Type, endpoint: Endpoint
  ) async throws -> T? {
    do {
      return try await send(.get, endpoint: endpoint, returns: type)
    } catch RequestError.unexpectedStatusCode(code: .notFound, _) {
      return nil
    }
  }

  func delete(_ type: Any.Type, endpoint: Endpoint) async throws {
    do {
      try await send(.delete, endpoint: endpoint, expectedStatus: .noContent)
    } catch {
      Logger.networking.error("Api delete \(type) failed: \(error)")
      throw error
    }
  }
}
