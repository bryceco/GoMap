//
//  Sqlite3.swift
//  Go Map!!
//
//  Created by Bryce Cogswell on 5/26/21.
//  Copyright © 2021 Bryce Cogswell. All rights reserved.
//

import Foundation
import SQLite3

enum SqliteError: LocalizedError {
	case open(Int32)
	case close(Int32)
	case exec(String, Int32)
	case prepare(String, Int32)
	case clearBindings(Int32)
	case bind(Int32)
	case step(Int32)

	public var errorDescription: String? {
		switch self {
		case let .open(rc): return "SqliteError.open() -> \(rc)"
		case let .close(rc): return "SqliteError.close() -> \(rc)"
		case let .exec(stmt, rc): return "SqliteError.exec(\(stmt) -> \(rc)"
		case let .prepare(stmt, rc): return "SqliteError.prepare(\(stmt) -> \(rc)"
		case let .clearBindings(rc): return "SqliteError.clearBindings() -> \(rc)"
		case let .bind(rc): return "SqliteError.bind() -> \(rc)"
		case let .step(rc): return "SqliteError.step() -> \(rc)"
		}
	}
}

private typealias sqlite3_db = OpaquePointer
private typealias sqlite3_stmt = OpaquePointer

final class SqliteStatement {
	fileprivate let value: sqlite3_stmt
	deinit {
		sqlite3_finalize(value)
	}

	init(value: OpaquePointer) {
		self.value = value
	}
}

final class Sqlite {
	static let ROW = SQLITE_ROW
	static let CONSTRAINT = SQLITE_CONSTRAINT

	let path: String
	private let db: sqlite3_db

	private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

	class func pathForName(_ name: String) -> String {
		let paths = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).map(\.path)
		let bundleName = Bundle.main.infoDictionary?["CFBundleIdentifier"] as! String
		let basename = "data.sqlite3"
		let name = name.isEmpty ? basename : "\(name).\(basename)"
		let url = URL(fileURLWithPath: paths[0])
			.appendingPathComponent(bundleName, isDirectory: true)
			.appendingPathComponent(name, isDirectory: false)
		try? FileManager.default.createDirectory(
			atPath: url.deletingLastPathComponent().path,
			withIntermediateDirectories: true,
			attributes: nil)
		return url.path
	}

	// return self if database can be opened
	init(name: String) throws {
		path = Sqlite.pathForName(name)

		var db: sqlite3_db?
		let rc = sqlite3_open_v2(path, &db, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE, nil)
		guard rc == SQLITE_OK,
		      let db = db
		else {
			throw SqliteError.open(rc)
		}
		self.db = db
	}

	deinit {
		sqlite3_close(db)
	}

	func errorMessage() -> String {
		if let msg = sqlite3_errmsg(db) {
			return String(cString: msg)
		}
		return ""
	}

	func exec(_ command: String) throws {
		let result = sqlite3_exec(db, command, nil, nil, nil)
		if result != SQLITE_OK {
			throw SqliteError.exec(command, result)
		}
	}

	func prepare(_ command: String) throws -> SqliteStatement {
		var statement: sqlite3_stmt?
		let result = sqlite3_prepare_v2(db, command, -1, &statement, nil)
		if result != SQLITE_OK || statement == nil {
			throw SqliteError.prepare(command, result)
		}
		return SqliteStatement(value: statement!)
	}

	func clearBindings(_ statement: SqliteStatement) throws {
		let rc = sqlite3_clear_bindings(statement.value)
		if rc != SQLITE_OK {
			throw SqliteError.clearBindings(rc)
		}
	}

	func reset(_ statement: SqliteStatement) throws {
		let rc = sqlite3_reset(statement.value)
		if rc != SQLITE_OK {
			throw SqliteError.clearBindings(rc)
		}
	}

	func bindText(_ statement: SqliteStatement, _ index: Int32, _ value: String?) throws {
		let rc = sqlite3_bind_text(statement.value, index, value, -1, SQLITE_TRANSIENT)
		if rc != SQLITE_OK {
			throw SqliteError.bind(rc)
		}
	}

	func bindInt32(_ statement: SqliteStatement, _ index: Int32, _ value: Int32) throws {
		let rc = sqlite3_bind_int(statement.value, index, value)
		if rc != SQLITE_OK {
			throw SqliteError.bind(rc)
		}
	}

	func bindInt64(_ statement: SqliteStatement, _ index: Int32, _ value: Int64) throws {
		let rc = sqlite3_bind_int64(statement.value, index, value)
		if rc != SQLITE_OK {
			throw SqliteError.bind(rc)
		}
	}

	func bindDouble(_ statement: SqliteStatement, _ index: Int32, _ value: Double) throws {
		let rc = sqlite3_bind_double(statement.value, index, value)
		if rc != SQLITE_OK {
			throw SqliteError.bind(rc)
		}
	}

	func step(_ statement: SqliteStatement, hasResult: Int32?) throws -> Bool {
		let rc = sqlite3_step(statement.value)
		if rc == SQLITE_DONE {
			return false
		}
		if let hasResult = hasResult,
		   rc == hasResult
		{
			return true
		}
		throw SqliteError.step(rc)
	}

	func step(_ statement: SqliteStatement) throws {
		_ = try step(statement, hasResult: nil)
	}

	func columnText(_ statement: SqliteStatement, _ index: Int32) -> String {
		let text = sqlite3_column_text(statement.value, index)
		assert(text != nil)
		return String(cString: text!)
	}

	func columnInt32(_ statement: SqliteStatement, _ index: Int32) -> Int32 {
		return sqlite3_column_int(statement.value, index)
	}

	func columnInt64(_ statement: SqliteStatement, _ index: Int32) -> Int64 {
		return sqlite3_column_int64(statement.value, index)
	}

	func columnDouble(_ statement: SqliteStatement, _ index: Int32) -> Double {
		return sqlite3_column_double(statement.value, index)
	}
}
