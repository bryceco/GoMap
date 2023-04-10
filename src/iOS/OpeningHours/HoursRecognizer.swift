//
//  HoursRecognizer.swift
//
//  Created by Bryce Cogswell on 4/5/21.
//

#if arch(arm64) || arch(x86_64) // old architectures don't support SwiftUI

import Combine
import Vision
import VisionKit

@available(iOS 13.0, macCatalyst 14.0, *)
fileprivate extension String.StringInterpolation {
	mutating func appendInterpolation(_ time: Time) {
		appendLiteral(time.text)
	}

	mutating func appendInterpolation(_ dash: Dash) {
		appendLiteral("-")
	}

	mutating func appendInterpolation(_ token: Token) {
		switch token {
		case let .day(day):
			appendInterpolation(day)
		case let .time(time):
			appendInterpolation(time)
		case let .dash(dash):
			appendInterpolation(dash)
		case let .modifier(modifier):
			appendInterpolation(modifier)
		case .unknown:
			appendLiteral("?")
		}
	}
}

fileprivate extension CGRect {
	// 0..1 depending on the amount of overlap
	func overlap(_ rect: CGRect) -> Float {
		let overlap = max(0.0, min(maxX, rect.maxX) - max(minX, rect.minX))
			* max(0.0, min(maxY, rect.maxY) - max(minY, rect.minY))
		let size1 = width * height
		let size2 = rect.width * rect.height
		return Float(overlap / (size1 + size2 - overlap))
	}
}

// return a list where all items are removed except the two with highest confidence (preserving their order)
fileprivate extension Array {
	func bestTwo(_ lessThan: (_ lhs: Self.Element, _ rhs: Self.Element) -> Bool) -> [Self.Element] {
		if count <= 2 {
			return self
		}
		var b0 = 0
		var b1 = 1
		for i in 2..<count {
			if lessThan(self[b0], self[i]) {
				b0 = i
			} else if lessThan(self[b1], self[i]) {
				b1 = i
			}
		}
		if b0 < b1 {
			return [self[b0], self[b1]]
		} else {
			return [self[b1], self[b0]]
		}
	}
}

fileprivate typealias SubstringRectf = (string: Substring, rectf: (Range<String.Index>) -> CGRect)
fileprivate typealias StringRect = (string: String, rect: CGRect)

// A version of Scanner that returns a rect for each string
@available(iOS 13.0, *)
@available(iOS 13.0, *)
fileprivate class RectScanner {
	let substring: Substring
	private let rectf: (Range<String.Index>) -> CGRect
	private let scanner: Scanner

	private static let allLetters = CharacterSet.uppercaseLetters.union(CharacterSet.lowercaseLetters)

	init(substring: Substring, rectf: @escaping (Range<String.Index>) -> CGRect) {
		self.substring = substring
		scanner = Scanner(string: String(substring))
		scanner.caseSensitive = false
		scanner.charactersToBeSkipped = nil
		self.rectf = rectf
	}

	var currentIndex: String.Index {
		get { scanner.currentIndex }
		set { scanner.currentIndex = newValue }
	}

	var string: String { return scanner.string }

	var isAtEnd: Bool { return scanner.isAtEnd }

	private func result(_ sub: Substring) -> StringRect {
		// get offset of start and end of sub relative to scanner string
		let d1 = sub.base.distance(from: sub.base.startIndex, to: sub.startIndex)
		let d2 = sub.base.distance(from: sub.base.startIndex, to: sub.endIndex)

		// convert offset to be relative to substring
		let p1 = substring.index(substring.startIndex, offsetBy: d1)
		let p2 = substring.index(substring.startIndex, offsetBy: d2)
		let rect = rectf(p1..<p2)
		return (String(sub), rect)
	}

	func lastChar() -> StringRect {
		let last = scanner.string.index(before: scanner.string.endIndex)
		return result(scanner.string[last..<scanner.string.endIndex])
	}

	func scanString(_ string: String) -> StringRect? {
		let index = scanner.currentIndex
		if let _ = scanner.scanString(string) {
			return result(scanner.string[index..<scanner.currentIndex])
		}
		return nil
	}

	func scanWhitespace() -> StringRect? {
		let index = scanner.currentIndex
		if let _ = scanner.scanCharacters(from: CharacterSet.whitespacesAndNewlines) {
			return result(scanner.string[index..<scanner.currentIndex])
		}
		return nil
	}

	func scanUpToWhitespace() -> StringRect? {
		let index = scanner.currentIndex
		if index == scanner.string.endIndex {
			return nil
		}
		if let _ = scanner.scanCharacters(from: RectScanner.allLetters) ??
			scanner.scanCharacters(from: CharacterSet.decimalDigits)
		{
			return result(scanner.string[index..<scanner.currentIndex])
		}
		// skip forward a single character
		scanner.currentIndex = scanner.string.index(after: scanner.currentIndex)
		return result(scanner.string[index..<scanner.currentIndex])
	}

	func scanInt() -> StringRect? {
		let index = scanner.currentIndex
		if let _ = scanner.scanInt() {
			return result(scanner.string[index..<scanner.currentIndex])
		}
		return nil
	}

	func scanWord(_ word: String) -> StringRect? {
		return scanAnyWord([word])?.1
	}

	static func distanceFrom<T: StringProtocol>(_ s1: T, _ s2: T) -> Float {
		if s1.count > 4 {
			return Float(LevenshteinDistance(s1, s2)) / Float(s1.count)
		} else {
			if s1.compare(s2, options: [.diacriticInsensitive, .caseInsensitive]) == .orderedSame {
				return 0.0
			}
		}
		return 1.0
	}

	func scanAnyWord(_ words: [String]) -> (Float, StringRect)? {
		let index = currentIndex
		if let scan = scanner.scanCharacters(from: RectScanner.allLetters) {
			// we match if the scanned word is a 2-3 letter prefix of the first word in the list
			if (2...3).contains(scan.count) {
				if words
					.first(where: { RectScanner.distanceFrom($0.prefix(scan.count), Substring(scan)) == 0.0 }) != nil
				{
					return (0.0, result(scanner.string[index..<scanner.currentIndex]))
				}
			} else {
				var bestDistance: Float = 1.0
				for word in words {
					let dist = RectScanner.distanceFrom(word, scan)
					if dist < bestDistance {
						bestDistance = dist
					}
				}
				if bestDistance <= 0.2 {
					return (bestDistance, result(scanner.string[index..<scanner.currentIndex]))
				}
			}
			scanner.currentIndex = index
		}
		return nil
	}

	func remainder() -> String {
		return String(scanner.string[scanner.currentIndex...])
	}
}

// A version of Scanner that accepts an array of substrings and can extract rectangles for them
@available(iOS 13.0, *)
fileprivate class MultiScanner {
	let strings: [SubstringRectf]
	let scanners: [RectScanner]
	var scannerIndex: Int

	init(strings: [SubstringRectf]) {
		self.strings = strings
		scanners = strings.map { RectScanner(substring: $0.string, rectf: $0.rectf) }
		scannerIndex = 0
	}

	var currentIndex: (scanner: Int, index: String.Index) {
		get { (scannerIndex, scanners[scannerIndex].currentIndex) }
		set { scannerIndex = newValue.0
			scanners[scannerIndex].currentIndex = newValue.1
			for scan in scanners[(scannerIndex + 1)...] {
				scan.currentIndex = scan.string.startIndex
			}
		}
	}

	var scanner: RectScanner {
		while scanners[scannerIndex].isAtEnd, scannerIndex + 1 < scanners.count {
			scannerIndex += 1
		}
		return scanners[scannerIndex]
	}

	var isAtEnd: Bool { return scanner.isAtEnd }

	func scanString(_ string: String) -> StringRect? {
		// we need to fudge an implied space at the break between two observations:
		if string == " ", scannerIndex > 0, scanner.currentIndex == scanner.string.startIndex {
			// return rect for previous character
			let rect = scanners[scannerIndex - 1].lastChar().rect
			return (" ", rect)
		}
		return scanner.scanString(string)
	}

	func scanWhitespace() -> StringRect? {
		var sub = scanner.scanWhitespace()
		// repeat in case we need to switch to next scanner
		if sub != nil {
			while let s = scanner.scanWhitespace() {
				sub = (sub!.string + s.string, sub!.rect.union(s.rect))
			}
		}
		return sub
	}

	func scanUpToWhitespace() -> StringRect? {
		return scanner.scanUpToWhitespace()
	}

	func scanInt() -> StringRect? {
		return scanner.scanInt()
	}

	func scanWord(_ word: String) -> StringRect? {
		return scanner.scanWord(word)
	}

	func scanAnyWord(_ words: [String]) -> (Float, StringRect)? {
		return scanner.scanAnyWord(words)
	}

	func remainder() -> String {
		return scanners[scannerIndex...].map({ $0.remainder() }).joined(separator: " ")
	}
}

@available(iOS 13.0, macCatalyst 14.0, *)
fileprivate enum Modifier {
	case open, closed

	static func scan(scanner: MultiScanner,
	                 language: HoursRecognizer.Language) -> (modifier: Self, rect: CGRect, confidence: Float)?
	{
		if let open = scanner.scanWord(language.open) {
			return (.open,
			        open.rect,
			        Float(open.string.count))
		}
		if let closed = scanner.scanWord(language.closed) {
			return (.closed,
			        closed.rect,
			        Float(closed.string.count))
		}
		return nil
	}
}

@available(iOS 13.0, macCatalyst 14.0, *)
enum Day: Int, Strideable, CaseIterable {
	case Mo, Tu, We, Th, Fr, Sa, Su

	func toString() -> String {
		switch self {
		case .Mo: return "Mo"
		case .Tu: return "Tu"
		case .We: return "We"
		case .Th: return "Th"
		case .Fr: return "Fr"
		case .Sa: return "Sa"
		case .Su: return "Su"
		}
	}

	static func fromString(_ string: String) -> Self? {
		switch string {
		case "Mo": return .Mo
		case "Tu": return .Tu
		case "We": return .We
		case "Th": return .Th
		case "Fr": return .Fr
		case "Sa": return .Sa
		case "Su": return .Su
		default: return nil
		}
	}

	func distance(to other: Day) -> Int {
		return (other.rawValue - rawValue + 7) % 7
	}

	func advanced(by n: Int) -> Day {
		return Day(rawValue: (rawValue + n + 7) % 7)!
	}

	fileprivate static func scan(scanner: MultiScanner,
	                             language: HoursRecognizer.Language) -> (day: Self, rect: CGRect, confidence: Float)?
	{
		var bestDistance: Float = 1.0
		var bestDay: Day?
		var bestString: StringRect?
		for (day, strings) in language.days {
			if let (dist, string) = scanner.scanAnyWord(strings) {
				if dist < bestDistance {
					bestDistance = dist
					bestDay = day
					bestString = string
				}
			}
		}
		if let bestString = bestString,
		   let bestDay = bestDay
		{
			return (bestDay, bestString.rect, Float(bestString.string.count))
		}
		return nil
	}

	fileprivate static func rangeForSet(_ set: Set<Day>) -> [DayRange] {
		var dayList = [DayRange]()
		var dayRange: DayRange?
		for d in Day.allCases {
			if set.contains(d) {
				if let range = dayRange {
					dayRange = DayRange(start: range.start, end: d)
				} else {
					dayRange = DayRange(start: d, end: d)
				}
			} else {
				if let range = dayRange {
					dayList.append(range)
				}
				dayRange = nil
			}
		}
		if let range = dayRange {
			dayList.append(range)
		}
		return dayList.sorted(by: { $0.start < $1.start })
	}
}

@available(iOS 13.0, macCatalyst 14.0, *)
fileprivate struct Time: Hashable {
	let minutes: Int
	let is24: Bool

	var text: String { return String(format: "%02d:%02d", minutes / 60, minutes % 60) }

	init(hour: Int, minute: Int, is24: Bool) {
		minutes = hour * 60 + minute
		self.is24 = is24
	}

	static func scan(scanner: MultiScanner,
	                 language: HoursRecognizer.Language) -> (time: Self, rect: CGRect, confidence: Float)?
	{
		let index = scanner.currentIndex
		var minutes: StringRect?

		if let noon = scanner.scanString(language.noon) {
			return (Time(hour: 12, minute: 0, is24: true),
			        noon.rect,
			        8.0)
		}
		if let midnight = scanner.scanString(language.midnight) {
			return (Time(hour: 0, minute: 0, is24: true),
			        midnight.rect,
			        8.0)
		}

		guard let hour = scanner.scanInt() else { return nil }
		if let iHour = Int(hour.string),
		   iHour >= 0, iHour <= 24
		{
			let index2 = scanner.currentIndex
			if language.minuteSeparators.map({ String($0) }).first(where: { scanner.scanString($0) != nil }) != nil,
			   let minute = scanner.scanInt(),
			   minute.string.count == 2,
			   minute.string >= "00", minute.string < "60"
			{
				minutes = minute
			} else {
				scanner.currentIndex = index2
			}

			_ = scanner.scanWhitespace()
			let iMinutes = Int(minutes?.string ?? "0")!
			if let am = scanner.scanString("AM") ?? scanner.scanString("A.M.") {
				return (Time(hour: iHour % 12, minute: iMinutes, is24: true),
				        hour.rect.union(am.rect),
				        (minutes != nil) ? 8.0 : 4.0)
			}
			if let pm = scanner.scanString("PM") ?? scanner.scanString("P.M.") {
				return (Time(hour: (iHour % 12) + 12, minute: iMinutes, is24: true),
				        hour.rect.union(pm.rect),
				        (minutes != nil) ? 8.0 : 4.0)
			}
			return (Time(hour: iHour, minute: 0, is24: iHour > 12 || hour.string >= "00" && hour.string <= "09"),
			        (minutes != nil) ? hour.rect.union(minutes!.rect) : hour.rect,
			        (minutes != nil) ? 6.0 : 1.0)
		}
		scanner.currentIndex = index
		return nil
	}
}

@available(iOS 13.0, macCatalyst 14.0, *)
fileprivate struct Dash {
	static func scan(scanner: MultiScanner, language: HoursRecognizer.Language) -> (Self, CGRect, Float)? {
		if let s = scanner.scanString("-") ?? scanner.scanWord(language.through) {
			return (Dash(), s.rect, Float(s.string.count))
		}
		return nil
	}
}

@available(iOS 13.0, macCatalyst 14.0, *)
fileprivate struct Unknown {
	let string: String
	static func scan(scanner: MultiScanner) -> (Self, CGRect, Float)? {
		if let s = scanner.scanUpToWhitespace() {
			return (Unknown(string: s.string), s.rect, 0.0)
		}
		return nil
	}
}

@available(iOS 13.0, macCatalyst 14.0, *)
fileprivate struct DayRange: Hashable {
	let start: Day
	let end: Day
}

@available(iOS 13.0, macCatalyst 14.0, *)
fileprivate struct TimeRange: Hashable {
	let start: Time
	let end: Time
	static let open = TimeRange(
		start: Time(hour: -1, minute: 0, is24: true),
		end: Time(hour: -1, minute: 0, is24: true))
}

fileprivate typealias SubstringRectConfidence = (
	substring: Substring,
	rect: CGRect,
	rectf: (Range<String.Index>) -> CGRect,
	confidence: Float)
@available(iOS 13.0, macCatalyst 14.0, *)
fileprivate typealias TokenRectConfidence = (token: Token, rect: CGRect, confidence: Float)

@available(iOS 13.0, macCatalyst 14.0, *)
fileprivate enum Token: Equatable {
	case time(Time)
	case day(Day)
	case dash(Dash)
	case modifier(Modifier)
	case unknown(Unknown)

	static func ==(lhs: Token, rhs: Token) -> Bool {
		return "\(lhs)" == "\(rhs)"
	}

	func day() -> Day? {
		switch self {
		case let .day(day): return day
		default: return nil
		}
	}

	func time() -> Time? {
		switch self {
		case let .time(time): return time
		default: return nil
		}
	}

	func dash() -> Dash? {
		switch self {
		case let .dash(dash): return dash
		default: return nil
		}
	}

	func modifier() -> Modifier? {
		switch self {
		case let .modifier(mod): return mod
		default: return nil
		}
	}

	func unknown() -> Unknown? {
		switch self {
		case let .unknown(unk): return unk
		default: return nil
		}
	}

	func isDay() -> Bool { return day() != nil }
	func isTime() -> Bool { return time() != nil }
	func isDash() -> Bool { return dash() != nil }
	func isModifier() -> Bool { return modifier() != nil }
	func isUnknown() -> Bool { return unknown() != nil }

	static func scan(scanner: MultiScanner, language: HoursRecognizer.Language) -> TokenRectConfidence? {
		if let (day, rect, confidence) = Day.scan(scanner: scanner, language: language) {
			return (.day(day), rect, confidence)
		}
		if let (time, rect, confidence) = Time.scan(scanner: scanner, language: language) {
			return (.time(time), rect, confidence)
		}
		if let (dash, rect, confidence) = Dash.scan(scanner: scanner, language: language) {
			return (.dash(dash), rect, confidence)
		}
		if let (modifier, rect, confidence) = Modifier.scan(scanner: scanner, language: language) {
			return (.modifier(modifier), rect, confidence)
		}
		// skip to next token
		if let (unknown, rect, confidence) = Unknown.scan(scanner: scanner) {
			return (.unknown(unknown), rect, confidence)
		}
		return nil
	}
}

@available(iOS 13.0, macCatalyst 14.0, *)
public class HoursRecognizer: ObservableObject {
	public var onRecognize: ((String) -> Void)?

	private var resultHistory = [String: Int]()
	@Published private(set) var finished = false {
		willSet {
			objectWillChange.send()
			if newValue {
				onRecognize?(text)
			}
		}
	}

	private static var lastLanguageSelected = { () -> Language in
		if let raw = UserPrefs.shared.string(forKey: .hoursRecognizerLanguage),
		   let lang = languageList.first(where: { $0.isoCode == raw })
		{
			return lang
		}
		return languageList.first(where: { $0.isoCode == "en" })!
	}()

	@Published public var language: Language = lastLanguageSelected {
		willSet {
			HoursRecognizer.lastLanguageSelected = newValue
			UserPrefs.shared.set(newValue.isoCode, forKey: .hoursRecognizerLanguage)
		}
	}

	@Published var text = "" {
		willSet {
			objectWillChange.send()
		}
	}

	init() {}

	public struct Language: Codable, Identifiable, Hashable {
		let isoCode: String
		let days: [Day: [String]]
		let open: String
		let closed: String
		let through: String
		let noon: String
		let midnight: String
		let minuteSeparators: String

		public var id: String { isoCode }
		var name: String { Locale(identifier: isoCode).localizedString(forIdentifier: isoCode) ?? "<??>" }

		enum CodingKeys: String, CodingKey {
			case isoCode
			case days
			case open
			case closed
			case through
			case noon
			case midnight
			case minuteSeparators
		}

		init(
			isoCode: String,
			days: [Day: [String]],
			open: String,
			closed: String,
			through: String,
			noon: String,
			midnight: String,
			minuteSeparators: String)
		{
			self.isoCode = isoCode
			self.days = days
			self.open = open
			self.closed = closed
			self.through = through
			self.noon = noon
			self.midnight = midnight
			self.minuteSeparators = minuteSeparators
		}

		public func encode(to encoder: Encoder) throws {
			var container = encoder.container(keyedBy: CodingKeys.self)
			try container.encode(isoCode, forKey: .isoCode)
			try container.encode(open, forKey: .open)
			try container.encode(closed, forKey: .closed)
			try container.encode(through, forKey: .through)
			try container.encode(noon, forKey: .noon)
			try container.encode(midnight, forKey: .midnight)
			try container.encode(minuteSeparators, forKey: .minuteSeparators)
			// special handling for days to map keys to strings
			let days2 = days.reduce(into: [:], { result, item in
				result[item.key.toString()] = item.value })
			try container.encode(days2, forKey: .days)
		}

		public init(from decoder: Decoder) throws {
			let container: KeyedDecodingContainer<HoursRecognizer.Language.CodingKeys> = try decoder
				.container(keyedBy: HoursRecognizer.Language.CodingKeys.self)
			isoCode = try container.decode(String.self, forKey: .isoCode)
			open = try container.decode(String.self, forKey: .open)
			closed = try container.decode(String.self, forKey: .closed)
			through = try container.decode(String.self, forKey: .through)
			noon = try container.decode(String.self, forKey: .noon)
			midnight = try container.decode(String.self, forKey: .midnight)
			minuteSeparators = try container.decode(String.self, forKey: .minuteSeparators)
			// special handling for days to map keys to strings
			let days2 = try container.decode([String: [String]].self, forKey: .days)
			days = days2.reduce(into: [:], { result, item in
				result[Day.fromString(item.key)!] = item.value
			})
		}
	}

	struct HoursRecognizerJson: Decodable {
		let languages: [Language]
	}

	static let languageList: [Language] = {
		let path = Bundle.main.path(forResource: "HoursRecognizer", ofType: "json")!
		let data = NSData(contentsOfFile: path)! as Data
		let json = try! JSONDecoder().decode(HoursRecognizerJson.self, from: data)
		return json.languages
	}()

	public func restart() {
		text = ""
		resultHistory.removeAll()
		finished = false
	}

	// takes an array of image observations and returns blocks of text along with their locations
	private class func stringsForImage(observations: [VNRecognizedTextObservation],
	                                   transform: CGAffineTransform) -> [SubstringRectConfidence]
	{
		var wordList = [SubstringRectConfidence]()
		for observation in observations {
			guard let candidate = observation.topCandidates(1).first else { continue }
			// Each observation can contain text in disconnected parts of the screen,
			// so we tokenize the string and extract the screen location of each token
			let rectf: (Range<String.Index>) -> CGRect = {
				let rect = try! candidate.boundingBox(for: $0)!.boundingBox
				let rect2 = rect.applying(transform)
				return rect2
			}
			let words = candidate.string.split(separator: " ")
			let words2 = words.map({ word -> SubstringRectConfidence in
				// Previous call returns tokens with substrings, which we can pass to candidate to get the rect
				let rect = rectf(word.startIndex..<word.endIndex)
				return (word, rect, rectf, candidate.confidence)
			})
			wordList += words2
		}
		return wordList
	}

	// split observed text text blocks into lines of text, sorted left-to-right and top-to-bottom
	private class func getStringLines(_ allStrings: [SubstringRectConfidence]) -> [[SubstringRectConfidence]] {
		var lines = [[SubstringRectConfidence]]()

		var list = allStrings

		while !list.isEmpty {
			// get highest confidence string
			let bestIndex = list.indices.max(by: { list[$0].confidence < list[$1].confidence })!
			let best = list[bestIndex]
			list.remove(at: bestIndex)
			var lineStrings = [best]

			// find tokens to left
			var prev = best
			while true {
				let strings = list.indices
					.filter({
						list[$0].rect.maxX <= prev.rect.minX && (prev.rect.minY...prev.rect.maxY)
							.contains(list[$0].rect.midY) })
				if strings.isEmpty { break }
				let closest = strings
					.min(by: { prev.rect.minX - list[$0].rect.maxX < prev.rect.minX - list[$1].rect.maxX })!
				prev = list[closest]
				lineStrings.insert(prev, at: 0)
				list.remove(at: closest)
			}

			// find tokens to right
			prev = best
			while true {
				let strings = list.indices
					.filter({
						list[$0].rect.minX >= prev.rect.maxX && (prev.rect.minY...prev.rect.maxY)
							.contains(list[$0].rect.midY) })
				if strings.isEmpty { break }
				let closest = strings
					.min(by: { list[$0].rect.minX - prev.rect.maxX < list[$1].rect.minX - prev.rect.maxX })!
				prev = list[closest]
				lineStrings.append(prev)
				list.remove(at: closest)
			}

			// save the line of strings
			lines.append(lineStrings)
		}

		// sort lines top-to-bottom
		lines.sort(by: { $0.first!.rect.minY < $1.first!.rect.minY })

		return lines
	}

	private class func tokensForStrings(_ strings: [SubstringRectConfidence],
	                                    language: Language) -> [TokenRectConfidence]
	{
		var list = [TokenRectConfidence]()

		let scanner = MultiScanner(strings: strings.map { ($0.substring, $0.rectf) })
		_ = scanner.scanWhitespace()
		while !scanner.isAtEnd {
			if let token = Token.scan(scanner: scanner, language: language) {
				list.append(token)
			}
			_ = scanner.scanWhitespace()
		}
		return list
	}

	// convert lines of strings to lines of tokens
	private class func tokenLinesForStringLines(_ stringLines: [[SubstringRectConfidence]],
	                                            language: Language) -> [[TokenRectConfidence]]
	{
		let tokenLines = stringLines.compactMap { line -> [TokenRectConfidence]? in
			let tokens = HoursRecognizer.tokensForStrings(line, language: language)
			return tokens.isEmpty ? nil : tokens
		}
		return tokenLines
	}

	// remove blocks of lines where the ratio of unknown to known tokens is high
	private class func removeUnknownTokens(_ tokenLines: [[TokenRectConfidence]]) -> [[TokenRectConfidence]] {
		var tokenLines = tokenLines

		if tokenLines.count > 10 {
#if false
			print("hit")
#endif
		}

		// find lines that don't have many known tokens
		let density = tokenLines.map { Float($0.filter({ !$0.token.isUnknown() }).count) / Float($0.count) }
		var keep = tokenLines.indices.map({ density[$0] > 0.3 })
		// also drop lines if it's neighbors are both ignored
		keep = keep.indices.map { $0 == 0 || $0 == keep.count - 1 || (keep[$0] && (keep[$0 - 1] || keep[$0 + 1])) }

		assert(keep.count == tokenLines.count)

		// filter token lines
		tokenLines = tokenLines.enumerated().compactMap { index, value in keep[index] ? value : nil }

		// remove any remaining unknown tokens
		tokenLines = tokenLines.map { $0.filter({ !$0.token.isUnknown() }) }
		tokenLines.removeAll(where: { $0.isEmpty })
		return tokenLines
	}

	// split the lines so each sequence of days or times is in its own group
	private class func homogeneousSequencesForTokenLines(_ tokenLines: [[TokenRectConfidence]])
		-> [[TokenRectConfidence]]
	{
		var tokenSets = [[TokenRectConfidence]]()
		for line in tokenLines {
			guard let first = line.indices.first(where: { !line[$0].token.isDash() }) else { continue }
			tokenSets.append([line[first]])
			var prevDash: TokenRectConfidence?

			for token in line[(first + 1)...] {
				if token.token.isDash() {
					prevDash = token
				} else if let prev = tokenSets.last?.first?.token,
				          (token.token.isDay() && prev.isDay()) ||
				          (token.token.isTime() && prev.isTime()) ||
				          (token.token.isModifier() && prev.isModifier())
				{
					if let dash = prevDash,
					   !prev.isModifier()
					{
						tokenSets[tokenSets.count - 1].append(dash)
					}
					tokenSets[tokenSets.count - 1].append(token)
					prevDash = nil
				} else {
					tokenSets.append([token])
					prevDash = nil
				}
			}
			tokenSets.append([])
		}
		tokenSets.removeAll(where: { $0.isEmpty })

		return tokenSets
	}

	// if a sequence has multiple days then take only the best 2
	private class func GoodDaysForTokenSequences(_ tokenSet: [TokenRectConfidence]) -> [TokenRectConfidence]? {
		// return tokenSets.map( { return $0.first!.token.isDay() ? $0.bestTwo( {$0.confidence < $1.confidence} ) : $0 })
		return tokenSet
	}

	// if a sequence has multiple times then take only the best even number
	private class func GoodTimesForTokenSequences(_ tokenSet: [TokenRectConfidence]) -> [TokenRectConfidence]? {
		var list = tokenSet
		var pairs = [(TokenRectConfidence, TokenRectConfidence)]()

		// pull out dash-seperated pairs
		while let dash = list.indices.first(where: { list[$0].token.isDash() }) {
			if dash > 1, dash + 1 < list.count {
				var priors = Array(list[0..<dash - 1])
				if priors.count % 2 == 1 {
					let worst = priors.indices.min(by: { priors[$0].confidence < priors[$1].confidence })!
					priors.remove(at: worst)
				}
				while !priors.isEmpty {
					pairs.append((priors[0], priors[1]))
					priors.removeSubrange(0...1)
				}
				pairs.append((list[dash - 1], list[dash + 1]))
				list.removeSubrange(0...dash + 1)
			} else {
				list.remove(at: dash)
			}
		}
		if list.count % 2 == 1 {
			let worst = list.indices.min(by: { list[$0].confidence < list[$1].confidence })!
			list.remove(at: worst)
		}
		while !list.isEmpty {
			pairs.append((list[0], list[1]))
			list.removeSubrange(0...1)
		}

		// look for suspicious pairs
		pairs.removeAll(where: { "\($0.0.token)" == "00:00" && "\($0.1.token)" == "00:00" })

		// if language is English then convert non-24 hour times that are ambiguous
		pairs = pairs.map {
			if let t1 = $0.0.token.time(),
			   let t2 = $0.1.token.time()
			{
				if !t1.is24, !t2.is24, t1.minutes >= t2.minutes, t2.minutes <= 12 * 60 {
					// both times are ambiguous and suspicious
					let newT2 = Time(hour: t2.minutes / 60 + 12, minute: t2.minutes % 60, is24: true)
					let newTok = TokenRectConfidence(Token.time(newT2), $0.1.rect, $0.1.confidence)
					return ($0.0, newTok)
				}
			}
			return $0
		}

		return pairs.count > 0 ? pairs.flatMap({ [$0.0, $0.1] }) : nil
	}

	// convert lists of tokens to a list of day/time ranges
	// an empty time range means closed
	private class func hoursForTokens(_ tokenLists: [[TokenRectConfidence]]) -> [([DayRange], [TimeRange])] {
		var days = [Day]()
		var times = [Time]()
		var modifiers = [Modifier]()
		var result = [([DayRange], [TimeRange])]()

		func flush() {
			// get days
			var dayRange = [DayRange]()
			if days.count > 0 {
				if days.count == 2 {
					// treat as a range of days
					dayRange = [DayRange(start: days[0], end: days[1])]
				} else {
					// treat as a list of days
					dayRange = days.map({ DayRange(start: $0, end: $0) })
				}
			}

			// get times
			let timeRange = times.count >= 2 ? stride(from: 0, to: times.count - 1, by: 2)
				.map({ TimeRange(start: times[$0], end: times[$0 + 1]) }) : []

			// update result if interesting
			if let mod = modifiers.last,
			   !dayRange.isEmpty
			{
				switch mod {
				case .closed: result.append((dayRange, []))
				case .open: result.append((dayRange, [TimeRange.open]))
				}
			} else if !timeRange.isEmpty {
				result.append((dayRange, timeRange))
			} else {
				return
			}
			days = []
			times = []
			modifiers = []
		}

		for line in tokenLists {
			// each line can have 1 or more days, and/or 2 or more hours
			// open/closed can be either before or after the days it applies to
			switch line.first!.token {
			case .modifier:
				modifiers += line.map({ $0.token.modifier()! })
				if !days.isEmpty {
					flush()
				}

			case .day:
				// a day line can contain dashes, so expand those to sets of days
				var line = line
				while let dashIndex = line.indices.first(where: { line[$0].token.isDash() }) {
					var prev = line[dashIndex - 1].token.day()!
					let next = line[dashIndex + 1].token.day()!
					line.removeSubrange((dashIndex - 1)...(dashIndex + 1))
					days.append(prev)
					while prev != next {
						prev = prev.advanced(by: 1)
						days.append(prev)
					}
				}
				days += line.map({ $0.token.day()! })
				if times.count >= 2 || !modifiers.isEmpty {
					flush()
				}
				times = []

			case .time:
				times += line.map({ $0.token.time()! })
				flush()

			case .dash:
				break

			case .unknown:
				assertionFailure()
			}
		}
		flush()
		return result
	}

	private class func coalesceDays(_ dayTimeRanges: [([DayRange], [TimeRange])]) -> [([DayRange], [TimeRange])] {
		var dict = [[TimeRange]: Set<Day>]()
		for dayTime in dayTimeRanges {
			var daySet = Set(dayTime.0.flatMap({ stride(from: $0.start, through: $0.end, by: 1) }))
			if let set = dict[dayTime.1] {
				daySet = daySet.union(set)
			}
			dict[dayTime.1] = daySet
		}

		var list = dict.map({ times, days -> ([DayRange], [TimeRange]) in
			let dayList = Day.rangeForSet(days)
			return (dayList, times)
		})
		list.sort(by: { ($0.0.first?.start.rawValue ?? -1) < ($1.0.first?.start.rawValue ?? -1) })
		return list
	}

	// convert lists of tokens to the final string
	private class func hoursStringForHours(_ dayTimeRanges: [([DayRange], [TimeRange])]) -> String {
		return dayTimeRanges.map { days, times in
			var result = ""
			if !days.isEmpty {
				result += days
					.sorted(by: { $0.start < $1.start })
					.map({ $0.start == $0.end ? "\($0.start)" : "\($0.start)-\($0.end)" })
					.joined(separator: ",")
				result += " "
			}
			if times.isEmpty {
				result += "\(Modifier.closed)"
			} else if times.count == 1, times.first! == TimeRange.open {
				result += "\(Modifier.open)"
			} else {
				result += times.map({ "\($0.start)-\($0.end)" })
					.joined(separator: ",")
			}
			return result
		}.joined(separator: ", ")
	}

	private func updateWithObservations(observations: [VNRecognizedTextObservation],
	                                    transform: CGAffineTransform,
	                                    camera: CameraView?)
	{
		if finished {
			return
		}

#if false
		let raw = observations.compactMap { $0.topCandidates(1).first?.string }.joined(separator: " ")
		Swift.print("\"\(raw)\"")
#endif

		// get strings and locations
		let strings = HoursRecognizer.stringsForImage(observations: observations, transform: transform)

#if false
		print("")
		print("strings:")
		for s in strings {
			print("\(s.substring): \(s.rect)")
		}
#endif

		// split into lines of text
		let stringLines = HoursRecognizer.getStringLines(strings)

#if false
		print("")
		print("string lines:")
		for line in stringLines {
			let s1 = line.map({ $0.substring }).joined(separator: " ")
			let s2 = line.map({ "\($0.confidence)" }).joined(separator: " ")
			print("\(s1): \(s2)")
		}
#endif

		// convert strings to tokens
		var tokenSets = HoursRecognizer.tokenLinesForStringLines(stringLines, language: language)

#if false
		print("")
		print("token lines:")
		for s in tokenSets {
			let s1 = s.map({ "\($0.token)" }).joined(separator: " ")
			let s2 = s.map({ "\($0.confidence)" }).joined(separator: " ")
			print("\(s1): \(s2)")
		}
#endif

		// remove unknown tokens
		tokenSets = HoursRecognizer.removeUnknownTokens(tokenSets)

		// get homogeneous day/time sets
		tokenSets = HoursRecognizer.homogeneousSequencesForTokenLines(tokenSets)

#if false
		print("")
		print("homogeneous:")
		for line in tokenSets {
			let s1 = line.map({ "\($0.token)" }).joined(separator: " ")
			let s2 = line.map({ "\(Float(Int(100.0 * $0.confidence)) / 100.0)" }).joined(separator: " ")
			print("\(s1): \(s2)")
		}
#endif

		// rationalize sequences of tokens
		tokenSets = tokenSets.compactMap {
			switch $0.first!.token {
			case .day: return HoursRecognizer.GoodDaysForTokenSequences($0)
			case .time: return HoursRecognizer.GoodTimesForTokenSequences($0)
			case .modifier: return $0
			case .dash: return $0
			case .unknown: assertionFailure(); return $0
			}
		}

		// combine homogeneous tokens in adjacent sets into a single set
		var index = 1
		while index < tokenSets.count {
			let prev = tokenSets[index - 1].first!.token
			let this = tokenSets[index].first!.token
			let combine: Bool
			switch prev {
			case .time: combine = this.isTime()
			case .modifier: combine = this.isModifier()
			case .day: combine = this.isDay()
			case .dash: combine = this.isDash()
			case .unknown: assertionFailure(); combine = false
			}
			if combine {
				tokenSets[index - 1] += tokenSets[index]
				tokenSets.remove(at: index)
			} else {
				index += 1
			}
		}

#if false
		print("")
		for line in tokenSets {
			let s1 = line.map({ "\($0.token)" }).joined(separator: " ")
			let s2 = line.map({ "\(Float(Int(100.0 * $0.confidence)) / 100.0)" }).joined(separator: " ")
			print("\(s1): \(s2)")
		}
#endif

		// convert the final sets of tokens to structured Day/Time ranges
		var resultArray = HoursRecognizer.hoursForTokens(tokenSets)

		// convert various days with identical hours to ranges of days
		resultArray = HoursRecognizer.coalesceDays(resultArray)

		let resultString = HoursRecognizer.hoursStringForHours(resultArray)

		// show the selected tokens in the video feed
		let invertedTransform = transform.inverted()
		let tokenBoxes = tokenSets.joined().map({ $0.rect.applying(invertedTransform) })
		camera?.addBoxes(boxes: tokenBoxes, color: UIColor.green)

#if false
		print("\(text)")
#endif

		if resultString != "" {
			let count = (resultHistory[resultString] ?? 0) + 1
			resultHistory[resultString] = count

			let best = resultHistory.max { $0.value < $1.value }!

			if Thread.isMainThread {
				text = best.key
				finished = best.value >= 5
			} else {
				DispatchQueue.main.async {
					self.text = best.key
					self.finished = best.value >= 5
				}
			}
		}
	}

	func updateWithLiveObservations(observations: [VNRecognizedTextObservation], camera: CameraView?) {
		updateWithObservations(observations: observations,
		                       transform: CGAffineTransform(scaleX: 1, y: -1).translatedBy(x: 0, y: 1),
		                       camera: camera)
	}

	func setImage(image: CGImage, isRotated: Bool) {
		restart()

//		let rotationTransform = CGAffineTransform(translationX: 0, y: 1).rotated(by: -CGFloat.pi / 2)

		let transform = isRotated ? CGAffineTransform(scaleX: 1.0, y: -1.0).rotated(by: -CGFloat.pi / 2)
			: CGAffineTransform.identity

		let request = VNRecognizeTextRequest(completionHandler: { request, error in
			guard error == nil,
			      let observations = request.results as? [VNRecognizedTextObservation] else { return }
			self.updateWithObservations(observations: observations, transform: transform, camera: nil)
		})
		request.recognitionLevel = .accurate
//		request.customWords = ["AM","PM"]
//		request.usesLanguageCorrection = true
		let requestHandler = VNImageRequestHandler(cgImage: image, options: [:])
		try? requestHandler.perform([request])
	}
}

#if targetEnvironment(macCatalyst)
@available(iOS 13.0, macCatalyst 14.0, *)
class BulkProcess {
	init() {}

	func processFile(path: String) {
		do {
			let userDirectory = try FileManager.default.url(
				for: FileManager.SearchPathDirectory.downloadsDirectory,
				in: .userDomainMask,
				appropriateFor: nil,
				create: false)
			let filePath = userDirectory.appendingPathComponent(path)
			let recognizer = HoursRecognizer()
			guard let image = UIImage(contentsOfFile: filePath.path),
			      let cgImage = image.cgImage else { return }
			recognizer.setImage(image: cgImage, isRotated: true)
			print("\"\(filePath.lastPathComponent)\" => \"\(recognizer.text)\",")
		} catch {
			print(error.localizedDescription)
		}
	}

	func processFolder(path: String) {
		do {
			let userDirectory = try FileManager.default.url(
				for: FileManager.SearchPathDirectory.downloadsDirectory,
				in: .userDomainMask,
				appropriateFor: nil,
				create: false)
			let imageDirectory = userDirectory.appendingPathComponent(path)
			let fileList = try FileManager.default.contentsOfDirectory(
				at: imageDirectory,
				includingPropertiesForKeys: nil,
				options: [])
			let recognizer = HoursRecognizer()
			for fileName in fileList {
//				print("\(fileName.lastPathComponent):")
				guard let image = UIImage(contentsOfFile: fileName.path),
				      let cgImage = image.cgImage else { continue }
				recognizer.setImage(image: cgImage, isRotated: true)
				print("\"\(fileName.lastPathComponent)\" => \"\(recognizer.text)\",")
			}
		} catch {
			print(error.localizedDescription)
		}
	}
}
#endif

#endif // #if (arch(arm64) || arch(x86_64))	// old architectures don't support SwiftUI
