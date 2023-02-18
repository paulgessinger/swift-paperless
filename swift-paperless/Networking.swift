//
//  Networking.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 18.02.23.
//

import Foundation

let API_TOKEN = "***REMOVED***"
let API_BASE_URL = "https://***REMOVED***/api/"

func getDocuments(page: UInt) async -> DocumentResponse? {
    let urlStr = API_BASE_URL + "documents/?page=\(page)"
    print(urlStr)
    guard let url = URL(string: urlStr) else {
        fatalError("Invalid URL")
    }

//    print("Go getDocuments")

    var request = URLRequest(url: url)
    request.setValue("Token \(API_TOKEN)", forHTTPHeaderField: "Authorization")

    do {
        let (data, _) = try await URLSession.shared.data(for: request)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let decoded = try decoder.decode(DocumentResponse.self, from: data)

        return decoded
    }
    catch {
        print(error)
        return nil
    }
}
