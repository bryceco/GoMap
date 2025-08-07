//
//  TypeCast.swift
//  Go Map!!
//
//  Created by Bryce Cogswell on 8/7/25.
//  Copyright © 2025 Bryce Cogswell. All rights reserved.
//

import Foundation

struct ContextualError: Error, CustomStringConvertible {
	let message: String
	let file: String
	let function: String
	let line: Int

	var description: String {
		"\(message) [\(function) @ \(file):\(line)]"
	}

	init(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
		self.message = message
		self.file = file
		self.function = function
		self.line = line
	}
}

protocol OptionalProtocol {}
extension Optional: OptionalProtocol {}
func isOptional<T>(_ type: T.Type) -> Bool {
	return type is OptionalProtocol.Type
}

func cast<T>(_ value: Any, to type: T.Type,
             file: String = #fileID, function: String = #function, line: Int = #line) throws -> T
{
	guard let result = value as? T else {
		let t = Mirror(reflecting: value).subjectType
		throw ContextualError("Failed to cast \(t) to \(T.self)", file: file, function: function, line: line)
	}
	return result
}

func cast<T>(_ value: Any?, to type: T.Type,
             file: String = #fileID, function: String = #function, line: Int = #line) throws -> T
{
	guard let unwrapped = value else {
		// If T is Optional, return nil as T
		if isOptional(T.self) {
			return Any?.none as! T
		}
		throw ContextualError("Value was nil", file: file, function: function, line: line)
	}
	return try cast(unwrapped, to: type, file: file, function: function, line: line)
}

func unwrap<T>(_ value: T?, file: String = #fileID, function: String = #function, line: Int = #line) throws -> T {
	guard let unwrapped = value else {
		throw ContextualError("Failed to unwrap \(T.self)", file: file, function: function, line: line)
	}
	return unwrapped
}

enum TypeCastError: Error {
	case invalidType
	case unexpectedNil
	case invalidEnum
}

infix operator -->: AssignmentPrecedence
func --> <T>(lhs: Any?, rhs: T.Type) throws -> T {
	guard let lhs = lhs as? T else {
		throw TypeCastError.invalidType
	}
	return lhs
}
