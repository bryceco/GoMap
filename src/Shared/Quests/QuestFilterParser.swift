//
//  QuestFilterParser.swift
//  Go Map!!
//
//  Created by Bryce Cogswell on 9/21/21.
//  Copyright © 2021 Bryce. All rights reserved.
//

// Derived from StreetComplete
// https://github.com/streetcomplete/StreetComplete/blob/6bb4e0c11ee109262d26f4473a4c14375729f3d7/app/src/main/java/de/westnordost/streetcomplete/data/elementfilter/ElementFiltersParser.kt
//

import Foundation

private let WITH = "with"
private let OR = "or"
private let AND = "and"

private let YEARS = "years"
private let MONTHS = "months"
private let WEEKS = "weeks"
private let DAYS = "days"

private let EQUALS = "="
private let NOT_EQUALS = "!="
private let LIKE = "~"
private let NOT = "!"
private let NOT_LIKE = "!~"
private let GREATER_THAN = ">"
private let LESS_THAN = "<"
private let GREATER_OR_EQUAL_THAN = ">="
private let LESS_OR_EQUAL_THAN = "<="
private let OLDER = "older"
private let NEWER = "newer"
private let TODAY = "today"
private let PLUS = "+"
private let MINUS = "-"

private var RESERVED_WORDS = [WITH, OR, AND]
private var QUOTATION_MARKS = ["\"", "'"]
private var KEY_VALUE_OPERATORS = [EQUALS, NOT_EQUALS, LIKE, NOT_LIKE]
private var COMPARISON_OPERATORS = [
	GREATER_THAN, GREATER_OR_EQUAL_THAN,
	LESS_THAN, LESS_OR_EQUAL_THAN
]

// must be in that order because if ">=" would be after ">", parser would match ">" also when encountering ">="
private var OPERATORS = [
	GREATER_OR_EQUAL_THAN,
	LESS_OR_EQUAL_THAN,
	GREATER_THAN,
	LESS_THAN,
	NOT_EQUALS,
	EQUALS,
	NOT_LIKE,
	LIKE,
	OLDER,
	NEWER
]

private var NUMBER_WORD_REGEX = try! NSRegularExpression(pattern: "(?:([0-9]+(?:\\.[0-9]*)?)|(\\.[0-9]+))(?:$| |\\))")

enum Exception: LocalizedError {
	case ParseException(String, String.Index)
	case IllegalStateException
}

typealias QuestElementFilter = (OsmBaseObject) -> Bool

class QuestFilterParser {
	private let string: String
	private var cursorPos: String.Index

	init(_ string: String) {
		self.string = string
		cursorPos = string.startIndex
	}

	private var char: Character? { cursorPos < string.endIndex ? string[cursorPos] : nil }

	private func nextIs(_ str: String) -> Bool {
		return string[cursorPos...].hasPrefix(str)
	}

	private func isAtEnd(_ offset: Int = 0) -> Bool {
		let dist = string.distance(from: cursorPos, to: string.endIndex)
		return dist <= offset
	}

	private func nextIsIgnoreCase(_ str: String) -> Bool {
		return nextIs(str.lowercased()) || nextIs(str.uppercased())
	}

	private func advanceBy(_ x: Int) -> Substring {
		let pos = cursorPos
		cursorPos = string.index(cursorPos, offsetBy: x, limitedBy: string.endIndex) ?? string.endIndex
		return string[pos..<cursorPos]
	}

	private func expectAnyNumberOfSpaces() {
		while cursorPos < string.endIndex, string[cursorPos].isWhitespace {
			cursorPos = string.index(after: cursorPos)
		}
	}

	private func nextIsAndAdvance(_ str: String) -> Bool {
		if !nextIs(str) {
			return false
		}
		_ = advanceBy(str.count)
		return true
	}

	private func ParseException(_ msg: String, _ loc: String.Index) -> Error {
		return Exception.ParseException(msg, loc)
	}

	func parseFilter() throws -> QuestElementFilter {
		let types = try parseElementsDeclaration()
		expectAnyNumberOfSpaces()
		guard nextIsAndAdvance(WITH) else {
			if !isAtEnd() {
				throw ParseException("Expected end of string or '\(WITH)' keyword", cursorPos)
			}
			return types
		}
		let expr = try parseTags()
		if !isAtEnd() {
			throw ParseException("Unexpected extra text", cursorPos)
		}
		return { types($0) && expr($0) }
	}

	private func parseElementsDeclaration() throws -> QuestElementFilter {
		var result: [OSM_TYPE] = []
		while true {
			let element = try parseElementDeclaration()
			if result.contains(element) {
				throw ParseException("Mentioned the same element type \(element) twice", cursorPos)
			}
			result.append(element)
			if !nextIsAndAdvance(",") {
				break
			}
		}
		return { result.contains($0.extendedIdentifier.type) }
	}

	private let ElementsTypeFilter = [
		"nodes": OSM_TYPE.NODE,
		"ways": OSM_TYPE.WAY,
		"relations": OSM_TYPE.RELATION
	]
	private func parseElementDeclaration() throws -> OSM_TYPE {
		expectAnyNumberOfSpaces()
		for (k, v) in ElementsTypeFilter {
			if nextIsAndAdvance(k) {
				expectAnyNumberOfSpaces()
				return v
			}
		}
		throw ParseException(
			"Expected element types. Any of: nodes, ways or relations, separated by ','",
			cursorPos)
	}

	private func parseTags() throws -> QuestElementFilter {
		var result = try parseTag()
		while true {
			expectAnyNumberOfSpaces()
			if isAtEnd() {
				return result
			}

			if nextIsAndAdvance(OR) {
				let e1 = result
				let e2 = try parseTag()
				result = { e1($0) || e2($0) }
			} else if nextIsAndAdvance(AND) {
				let e1 = result
				let e2 = try parseTag()
				result = { e1($0) && e2($0) }
			} else {
				throw ParseException("Expected end of string, '$AND' or '$OR'", cursorPos)
			}
		}
	}

	private func isLikeFunc(_ string: String) throws -> ((String?) -> Bool) {
		guard let regex = try? NSRegularExpression(pattern: string) else {
			throw ParseException("Invalid regex '\(string)'", cursorPos)
		}
		return {
			guard let s = $0 else { return false }
			return regex.matches(in: s, range: NSMakeRange(0, s.count)).count > 0
		}
	}

	class func compareFloat(_ oper: String, _ string: String?, _ value: Double) -> Bool {
		guard let string2 = string,
		      let strVal = Double(string2)
		else {
			return false
		}
		switch oper {
		case GREATER_THAN: return strVal > value
		case GREATER_OR_EQUAL_THAN: return strVal >= value
		case LESS_THAN: return strVal < value
		case LESS_OR_EQUAL_THAN: return strVal <= value
		default: return false
		}
	}

	private func parseTag() throws -> QuestElementFilter {
		expectAnyNumberOfSpaces()

		if nextIsAndAdvance("(") {
			let expr = try parseTags()
			expectAnyNumberOfSpaces()
			if !nextIsAndAdvance(")") {
				throw ParseException("Missing ')'", cursorPos)
			}
			return expr
		}

		if nextIsAndAdvance(NOT) {
			expectAnyNumberOfSpaces()
			if nextIsAndAdvance(LIKE) {
				fatalError() // return NotHasKeyLike(parseKey())
			} else {
				let key = try parseKey()
				return { $0.tags[key] == nil }
			}
		}

		if nextIsAndAdvance(LIKE) {
			expectAnyNumberOfSpaces()
			let key = try parseKey()
			expectAnyNumberOfSpaces()

			guard let oper = parseOperator() else {
				let keyLike = try isLikeFunc(key)
				return {
					$0.tags.keys.first(where: { keyLike($0) }) != nil
				}
			}
			if oper == LIKE {
				expectAnyNumberOfSpaces()
				let word = try parseQuotableWord()
				let keyLike = try isLikeFunc(key)
				let valLike = try isLikeFunc(word)
				return {
					$0.tags.first(where: { k, v in keyLike(k) && valLike(v) }) != nil
				}
			}
			throw ParseException(
				"Unexpected operator '\(oper)': The key prefix operator '\(LIKE)' must be used together with the binary operator '\(LIKE)'",
				cursorPos)
		}

		if nextIsAndAdvance(OLDER) {
			try expectOneOrMoreSpaces()
			let date = try parseDate()
			return { $0.dateForTimestamp() < date }
		}
		if nextIsAndAdvance(NEWER) {
			try expectOneOrMoreSpaces()
			let date = try parseDate()
			return { $0.dateForTimestamp() > date }
		}

		let key = try parseKey()
		expectAnyNumberOfSpaces()
		guard let oper = parseOperator() else {
			// no operator, so just make sure key exists
			return { $0.tags[key] != nil }
		}

		if oper == OLDER {
			try expectOneOrMoreSpaces()
			let date = try parseDate()
			return { $0.tags[key] != nil && $0.dateForTimestamp() < date }
		}
		if oper == NEWER {
			try expectOneOrMoreSpaces()
			let date = try parseDate()
			return { $0.tags[key] != nil && $0.dateForTimestamp() > date }
		}

		if KEY_VALUE_OPERATORS.contains(oper) {
			expectAnyNumberOfSpaces()
			let value = try parseQuotableWord()

			switch oper {
			case EQUALS: return { $0.tags[key] == value }
			case NOT_EQUALS: return { $0.tags[key] != value }
			case LIKE:
				let re = try isLikeFunc(value)
				return { re($0.tags[key]) }
			case NOT_LIKE:
				let re = try isLikeFunc(value)
				return { !re($0.tags[key]) }
			default:
				fatalError()
			}
		}

		if COMPARISON_OPERATORS.contains(oper) {
			expectAnyNumberOfSpaces()
			if nextMatches(NUMBER_WORD_REGEX) != nil {
				let value = try parseNumber()
				switch oper {
				case GREATER_THAN: return { Self.compareFloat(oper, $0.tags[key], value) }
				case GREATER_OR_EQUAL_THAN: return { Self.compareFloat(oper, $0.tags[key], value) }
				case LESS_THAN: return { Self.compareFloat(oper, $0.tags[key], value) }
				case LESS_OR_EQUAL_THAN: return { Self.compareFloat(oper, $0.tags[key], value) }
				default: fatalError()
				}
			} else {
				let value = try parseDate()
				switch oper {
				case GREATER_THAN: return { $0.dateForTimestamp() > value }
				case GREATER_OR_EQUAL_THAN: return { $0.dateForTimestamp() >= value }
				case LESS_THAN: return { $0.dateForTimestamp() < value }
				case LESS_OR_EQUAL_THAN: return { $0.dateForTimestamp() <= value }
				default: fatalError()
				}
			}
			throw ParseException("must either be a number or a (relative) date", cursorPos)
		}
		throw ParseException("Unknown operator '$operator'", cursorPos)
	}

	private func parseKey() throws -> String {
		let reserved = try nextIsReservedWord()
		if reserved != nil {
			throw ParseException(
				"A key cannot be named like the reserved word '$reserved', surround it with quotation marks",
				cursorPos)
		}

		let length = try findKeyLength()
		if length == 0 {
			throw ParseException("Missing key (dangling prefix operator)", cursorPos)
		}
		return stripQuotes(String(advanceBy(length)))
	}

	private func parseOperator() -> String? {
		return OPERATORS.first(where: { nextIsAndAdvance($0) })
	}

	private let quotes = CharacterSet(charactersIn: "'\"")
	private func stripQuotes(_ s: String) -> String {
		return s.trimmingCharacters(in: quotes)
	}

	private func parseQuotableWord() throws -> String {
		let length = try findQuotableWordLength()
		if length == 0 {
			throw ParseException("Missing value (dangling operator)", cursorPos)
		}
		return stripQuotes(String(advanceBy(length)))
	}

	private func parseWord() throws -> String {
		let length = try findWordLength()
		if length == 0 {
			throw ParseException("Missing value (dangling operator)", cursorPos)
		}
		return String(advanceBy(length))
	}

	private func parseNumber() throws -> Double {
		let word = try parseWord()
		guard let val = Double(word) else {
			throw ParseException("Expected a number", cursorPos)
		}
		return val
	}

	private func parseDate() throws -> Date {
		let length = try findWordLength()
		if length == 0 {
			throw ParseException("Missing date", cursorPos)
		}
		let word = advanceBy(length)
		if word == TODAY {
			var deltaDays = 0.0
			if nextIsAndAdvance(" ") {
				expectAnyNumberOfSpaces()
				deltaDays = try parseDeltaDurationInDays()
			}
			return Date(timeIntervalSinceNow: deltaDays * 24 * 60 * 60)
		}

		if let date = toCheckDate(String(word)) {
			return date
		}

		throw ParseException("Expected either a date (YYYY-MM-DD) or '$TODAY'", cursorPos)
	}

	private let OSM_CHECK_DATE_REGEX = try! NSRegularExpression(pattern: "([0-9]{4})-([0-9]{2})(?:-([0-9]{2}))?")
	func toCheckDate(_ string: String) -> Date? {
		let matches = OSM_CHECK_DATE_REGEX.matches(in: string, options: .anchored, range: NSMakeRange(0, string.count))
		guard let groups: NSTextCheckingResult = matches.first,
		      groups.numberOfRanges >= 2
		else { return nil }
		let rYear = groups.range(at: 0)
		let rMonth = groups.range(at: 1)
		let rDay = groups.numberOfRanges > 2 ? groups.range(at: 2) : NSMakeRange(0, 0)
		guard let rrYear = Range(rYear, in: string),
		      let rrMonth = Range(rMonth, in: string),
		      let rrDay = Range(rDay, in: string)
		else { return nil }
		let sYear = string[rrYear]
		let sMonth = string[rrMonth]
		let sDay = string[rrDay]
		guard let year = Int(sYear),
		      let month = Int(sMonth)
		else { return nil }
		let day = Int(sDay) ?? 1
		let comps = DateComponents(calendar: nil,
		                           timeZone: nil,
		                           era: nil,
		                           year: year,
		                           month: month,
		                           day: day,
		                           hour: nil,
		                           minute: nil,
		                           second: nil,
		                           nanosecond: nil,
		                           weekday: nil,
		                           weekdayOrdinal: nil,
		                           quarter: nil,
		                           weekOfMonth: nil,
		                           weekOfYear: nil,
		                           yearForWeekOfYear: nil)
		return comps.date
	}

	private func parseDeltaDurationInDays() throws -> Double {
		if nextIsAndAdvance(PLUS) {
			expectAnyNumberOfSpaces()
			return try parseDurationInDays()
		}
		if nextIsAndAdvance(MINUS) {
			expectAnyNumberOfSpaces()
			return try -parseDurationInDays()
		}
		throw ParseException("Expected $PLUS or $MINUS", cursorPos)
	}

	private func parseDurationInDays() throws -> Double {
		let duration = try parseNumber()
		try expectOneOrMoreSpaces()
		if nextIsAndAdvance(YEARS) {
			return 365.25 * duration
		}
		if nextIsAndAdvance(MONTHS) {
			return 30.5 * duration
		}
		if nextIsAndAdvance(WEEKS) {
			return 7 * duration
		}
		if nextIsAndAdvance(DAYS) {
			return duration
		}
		throw ParseException("Expected $YEARS, $MONTHS, $WEEKS or $DAYS", cursorPos)
	}

	private func expectOneOrMoreSpaces() throws {
		if cursorPos < string.endIndex,
		   string[cursorPos].isWhitespace
		{
			expectAnyNumberOfSpaces()
			return
		}
		throw ParseException("Expected a whitespace", cursorPos)
	}

	private func findNext(_ str: String, _ offset: Int = 0) -> Int {
		let start = string.index(cursorPos, offsetBy: offset)
		if let range = string[start...].range(of: str) {
			return string.distance(from: cursorPos, to: range.lowerBound)
		} else {
			return string.distance(from: cursorPos, to: string.endIndex)
		}
	}

	private func nextIsReservedWord() throws -> String? {
		return RESERVED_WORDS.first(where: {
			nextIsIgnoreCase($0) && (isAtEnd($0.count) || findNext(" ", $0.count) == $0.count)
		})
	}

	private func nextMatches(_ regex: NSRegularExpression) -> NSTextCheckingResult? {
		let offset = string.distance(from: string.startIndex, to: cursorPos)
		let matches = regex.matches(in: string, options: [], range: NSMakeRange(offset, string.count - offset))
		guard let match = matches.first
		else {
			return nil
		}
		if string.index(string.startIndex, offsetBy: match.range.lowerBound) != cursorPos {
			return nil
		}
		return match
	}

	private func findKeyLength() throws -> Int {
		if let length = try findQuotationLength() {
			return length
		}

		var length = try findWordLength()
		for o in OPERATORS {
			let opLen = findNext(o)
			if opLen < length {
				length = opLen
			}
		}
		return length
	}

	private func findWordLength() throws -> Int {
		return min(findNext(" "), findNext(")"))
	}

	private func findQuotableWordLength() throws -> Int {
		return try findQuotationLength() ?? findWordLength()
	}

	private func findQuotationLength() throws -> Int? {
		for quot in QUOTATION_MARKS {
			if nextIs(quot) {
				let length = findNext(quot, 1)
				if isAtEnd(length) {
					let pos = string.index(cursorPos, offsetBy: -1)
					throw ParseException("Did not close quotation marks", pos)
				}
				// +1 because we want to include the closing quotation mark
				return length + 1
			}
		}
		return nil
	}
}
