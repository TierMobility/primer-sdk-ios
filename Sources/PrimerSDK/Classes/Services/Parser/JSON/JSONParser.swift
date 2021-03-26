//
//  JSONParser.swift
//  primer-checkout-api
//
//  Created by Evangelos Pittas on 26/2/21.
//

import Foundation

class JSONParser: Parser {
    private let jsonDecoder = JSONDecoder()
    
    func parse<T: Decodable>(_ type: T.Type, from data: Data, keyDecodingStrategy: JSONDecoder.KeyDecodingStrategy? = nil) throws -> T {
        if let keyDecodingStrategy = keyDecodingStrategy  {
            jsonDecoder.keyDecodingStrategy = keyDecodingStrategy
        }
        return try jsonDecoder.decode(T.self, from: data)
    }
}
