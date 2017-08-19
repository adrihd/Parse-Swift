//
//  ParseObjectType.swift
//  Parse
//
//  Created by Florent Vilmart on 17-07-24.
//  Copyright © 2017 Parse. All rights reserved.
//

import Foundation

public struct NoBody: Codable {}

public protocol Saving: Codable {
    func save() -> RESTCommand<Self, Self>
}

public protocol Fetching: Codable {
    func fetch() throws -> RESTCommand<Self, Self>
}

public protocol ObjectType: Fetching, Saving, CustomDebugStringConvertible {
    static var className: String { get }
    var objectId: String? { get set }
    var createdAt: Date? { get set }
    var updatedAt: Date? { get set }
    var ACL: ACL? { get set }
}

extension ObjectType {
    public var className: String {
        return Self.className
    }
}

extension ObjectType {
    public var debugDescription: String {
        guard let descriptionData = try? JSONEncoder().encode(self),
            let descriptionString = String(data: descriptionData, encoding: .utf8) else {
                return "\(className) ()"
        }
        return "\(className) (\(descriptionString))"
    }
}

public extension ObjectType {
    static var className: String {
        let t = "\(type(of: self))"
        return t.components(separatedBy: ".").first! // strip .Type
    }
}

public extension ObjectType {
    func toPointer() -> Pointer<Self> {
        return Pointer(self)
    }
}

public struct SaveResponse: Decodable {
    var objectId: String
    var createdAt: Date
    var updatedAt: Date {
        return createdAt
    }

    func apply<T>(_ object: T) -> T where T: ObjectType {
        var object = object
        object.objectId = objectId
        object.createdAt = createdAt
        object.updatedAt = updatedAt
        return object
    }
}

struct UpdateResponse: Decodable {
    var updatedAt: Date

    func apply<T>(_ object: T) -> T where T: ObjectType {
        var object = object
        object.updatedAt = updatedAt
        return object
    }
}

struct SaveOrUpdateResponse: Decodable {
    var objectId: String?
    var createdAt: Date?
    var updatedAt: Date?

    var isCreate: Bool {
        return objectId != nil && createdAt != nil
    }

    func asSaveResponse() -> SaveResponse {
        guard let objectId = objectId, let createdAt = createdAt else {
            fatalError("Cannot create a SaveResponse without objectId")
        }
        return SaveResponse(objectId: objectId, createdAt: createdAt)
    }

    func asUpdateResponse() -> UpdateResponse {
        guard let updatedAt = updatedAt else {
            fatalError("Cannot create an UpdateResponse without updatedAt")
        }
        return UpdateResponse(updatedAt: updatedAt)
    }

    func apply<T>(_ object: T) -> T where T: ObjectType {
        if isCreate {
            return asSaveResponse().apply(object)
        } else {
            return asUpdateResponse().apply(object)
        }
    }
}

public struct ParseError: Error, Decodable {
    let code: Int
    let error: String
}

enum DateEncodingKeys: String, CodingKey {
    case iso
    case __type
}

let dateFormatter: DateFormatter = {
    var dateFormatter = DateFormatter()
    dateFormatter.locale = Locale(identifier: "")
    dateFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSS'Z'"
    return dateFormatter
}()

let dateEncodingStrategy: JSONEncoder.DateEncodingStrategy = .custom({ (date, enc) in
    var container = enc.container(keyedBy: DateEncodingKeys.self)
    try container.encode("Date", forKey: .__type)
    let dateString = dateFormatter.string(from: date)
    try container.encode(dateString, forKey: .iso)
})

let dateDecodingStrategy: JSONDecoder.DateDecodingStrategy = .custom({ (dec) -> Date in
    do {
        let container = try dec.singleValueContainer()
        let decodedString = try container.decode(String.self)
        return dateFormatter.date(from: decodedString)!
    } catch let e {
        let container = try dec.container(keyedBy: DateEncodingKeys.self)
        if let decoded = try container.decodeIfPresent(String.self, forKey: .iso) {
            return dateFormatter.date(from: decoded)!
        }
    }
    throw NSError(domain: "", code: -1, userInfo: nil)
})

func getEncoder() -> JSONEncoder {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = dateEncodingStrategy
    return encoder
}

extension JSONEncoder {
    func encodeAsString<T>(_ value: T) throws -> String where T: Encodable {
        guard let string = String(data: try encode(value), encoding: .utf8) else {
            throw ParseError(code: -1, error: "Unable to encode object...")
        }
        return string
    }
}

func getDecoder() -> JSONDecoder {
    let encoder = JSONDecoder()
    encoder.dateDecodingStrategy = dateDecodingStrategy
    return encoder
}

public extension ObjectType {
    public func save() -> RESTCommand<Self, Self> {
        return RESTCommand<Self, Self>.save(self)
    }

    public func fetch() throws -> RESTCommand<Self, Self> {
        return try RESTCommand<Self, Self>.fetch(self)
    }
}

extension ObjectType {
    var remotePath: String {
        if let objectId = objectId {
            return "/classes/\(className)/\(objectId)"
        }
        return "/classes/\(className)"
    }

    var isSaved: Bool {
        return objectId != nil
    }
}

public struct FindResult<T>: Decodable where T: ObjectType {
    let results: [T]
    let count: Int?
}

public extension ObjectType {
    var mutationContainer: ParseMutationContainer<Self> {
        return ParseMutationContainer(target: self)
    }
}

public extension ObjectType {
    public static func saveAll(_ objects: Self...) -> RESTBatchCommand<Self> {
        return RESTBatchCommand(commands: objects.map { $0.save() })
    }
}

extension Sequence where Element: ObjectType {
    public func saveAll() -> RESTBatchCommand<Element> {
        return RESTBatchCommand(commands: map { $0.save() })
    }
}