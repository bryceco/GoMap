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
	case open(Int32, String)
	case close(Int32, String)
	case exec(String, Int32, String)
	case prepare(String, Int32, String)
	case clearBindings(Int32, String)
	case bind(Int32, String)
	case step(Int32, String)

	public var errorDescription: String? {
		switch self {
		case let .open(rc, msg): return "SqliteError.open() -> \(Sqlite.errorMessageFor(code: rc)) - \(msg)"
		case let .close(rc, msg): return "SqliteError.close() -> \(Sqlite.errorMessageFor(code: rc)) - \(msg)"
		case let .exec(stmt, rc,
		               msg): return "SqliteError.exec('\(stmt)') -> \(Sqlite.errorMessageFor(code: rc)) - \(msg)"
		case let .prepare(stmt, rc,
		                  msg): return "SqliteError.prepare('\(stmt)') -> \(Sqlite.errorMessageFor(code: rc)) - \(msg)"
		case let .clearBindings(rc,
		                        msg): return "SqliteError.clearBindings() -> \(Sqlite.errorMessageFor(code: rc)) - \(msg)"
		case let .bind(rc, msg): return "SqliteError.bind() -> \(Sqlite.errorMessageFor(code: rc)) - \(msg)"
		case let .step(rc, msg): return "SqliteError.step() -> \(Sqlite.errorMessageFor(code: rc)) - \(msg)"
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

	class func pathForOsmName(_ name: String) -> String {
		let basename = "data.sqlite3"
		let name = name.isEmpty ? basename : "\(name).\(basename)"
		return ArchivePath.sqlite(name).path()
	}

	// return self if database can be opened
	init(path: String, readonly: Bool) throws {
		var db: sqlite3_db?
		let rc = sqlite3_open_v2(path, &db, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE, nil)
		guard rc == SQLITE_OK,
		      let db = db
		else {
			throw SqliteError.open(rc, String(utf8String: sqlite3_errmsg(db)) ?? "")
		}
		self.path = path
		self.db = db
		// Enable extended result codes
		sqlite3_extended_result_codes(db, 1)
	}

	convenience init(osmName: String) throws {
		let path = Sqlite.pathForOsmName(osmName)
		try self.init(path: path, readonly: false)
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

	static func errorMessageFor(code: Int32) -> String {
		if let msg = sqlite3_errstr(code) {
			return String(cString: msg)
		}
		return ""
	}

	func exec(_ command: String) throws {
		let result = sqlite3_exec(db, command, nil, nil, nil)
		if result != SQLITE_OK {
			throw SqliteError.exec(command, result, String(utf8String: sqlite3_errmsg(db)) ?? "")
		}
	}

	func prepare(_ command: String) throws -> SqliteStatement {
		var statement: sqlite3_stmt?
		let result = sqlite3_prepare_v2(db, command, -1, &statement, nil)
		if result != SQLITE_OK || statement == nil {
			throw SqliteError.prepare(command, result, String(utf8String: sqlite3_errmsg(db)) ?? "")
		}
		return SqliteStatement(value: statement!)
	}

	func clearBindings(_ statement: SqliteStatement) throws {
		let rc = sqlite3_clear_bindings(statement.value)
		if rc != SQLITE_OK {
			throw SqliteError.clearBindings(rc, String(utf8String: sqlite3_errmsg(db)) ?? "")
		}
	}

	func reset(_ statement: SqliteStatement) throws {
		let rc = sqlite3_reset(statement.value)
		if rc != SQLITE_OK {
			throw SqliteError.clearBindings(rc, String(utf8String: sqlite3_errmsg(db)) ?? "")
		}
	}

	func bindText(_ statement: SqliteStatement, _ index: Int32, _ value: String?) throws {
		let rc = sqlite3_bind_text(statement.value, index, value, -1, SQLITE_TRANSIENT)
		if rc != SQLITE_OK {
			throw SqliteError.bind(rc, String(utf8String: sqlite3_errmsg(db)) ?? "")
		}
	}

	func bindInt32(_ statement: SqliteStatement, _ index: Int32, _ value: Int32) throws {
		let rc = sqlite3_bind_int(statement.value, index, value)
		if rc != SQLITE_OK {
			throw SqliteError.bind(rc, String(utf8String: sqlite3_errmsg(db)) ?? "")
		}
	}

	func bindInt64(_ statement: SqliteStatement, _ index: Int32, _ value: Int64) throws {
		let rc = sqlite3_bind_int64(statement.value, index, value)
		if rc != SQLITE_OK {
			throw SqliteError.bind(rc, String(utf8String: sqlite3_errmsg(db)) ?? "")
		}
	}

	func bindDouble(_ statement: SqliteStatement, _ index: Int32, _ value: Double) throws {
		let rc = sqlite3_bind_double(statement.value, index, value)
		if rc != SQLITE_OK {
			throw SqliteError.bind(rc, String(utf8String: sqlite3_errmsg(db)) ?? "")
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
		throw SqliteError.step(rc, String(utf8String: sqlite3_errmsg(db)) ?? "")
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

	func printAllTables() throws {
		print("")
		print("Sqlite3 Tables:")
		let stmt = try prepare("SELECT * FROM sqlite_master where type='table';")
		while try step(stmt, hasResult: Sqlite.ROW) {
			let msg = columnText(stmt, 1)
			print("\(msg)")
		}
	}
}
