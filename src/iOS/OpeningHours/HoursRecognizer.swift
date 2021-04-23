//
//  HoursRecognizer.swift
//
//  Created by Bryce Cogswell on 4/5/21.
//

#if (arch(arm64) || arch(x86_64))	// old architectures don't support SwiftUI

import VisionKit
import Vision

@available(iOS 13.0, *)
extension String.StringInterpolation {
	fileprivate mutating func appendInterpolation(_ time: Time) {
		appendLiteral(time.text)
	}
	fileprivate mutating func appendInterpolation(_ dash: Dash) {
		appendLiteral("-")
	}
	fileprivate mutating func appendInterpolation(_ token: Token) {
		switch token {
		case let .day(day):
			appendInterpolation(day)
		case let .time(time):
			appendInterpolation(time)
		case let .dash(dash):
			appendInterpolation(dash)
		case .endOfText:
			appendLiteral("")
		}
	}
}

extension CGRect {
	// 0..1 depending on the amount of overlap
	fileprivate func overlap(_ rect: CGRect) -> Float {
		let overlap = max(0.0, min(self.maxX,rect.maxX) - max(self.minX,rect.minX))
					* max(0.0, min(self.maxY,rect.maxY) - max(self.minY,rect.minY))
		let size1 = self.width * self.height
		let size2 = rect.width * rect.height
		return Float(overlap / (size1+size2-overlap))
	}
}

// return a list where all items are removed except the two with highest confidence (preserving their order)
extension Array {
	fileprivate func bestTwo(_ lessThan: (_ lhs: Self.Element, _ rhs: Self.Element) -> Bool) -> [Self.Element] {
		if self.count <= 2 {
			return self
		}
		var b0 = 0
		var b1 = 1
		for i in 2..<self.count {
			if lessThan( self[b0], self[i] ) {
				b0 = i
			} else if lessThan( self[b1], self[i]) {
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

fileprivate typealias SubstringRectf = (string:Substring, rectf:(Range<String.Index>)->CGRect)
fileprivate typealias StringRect = (string:String, rect:CGRect)

// A version of Scanner that returns a rect for each string
@available(iOS 13.0, *)
@available(iOS 13.0, *)
fileprivate class RectScanner {

	let substring: Substring
	let scanner: Scanner
	let rectf:(Range<String.Index>)->CGRect

	static private let allLetters = CharacterSet.uppercaseLetters.union(CharacterSet.lowercaseLetters)

	init(substring: Substring, rectf:@escaping (Range<String.Index>)->CGRect) {
		self.substring = substring
		self.scanner = Scanner(string: String(substring))
		self.scanner.caseSensitive = false
		self.scanner.charactersToBeSkipped = nil
		self.rectf = rectf
	}

	var currentIndex: String.Index {
		get { scanner.currentIndex }
		set { scanner.currentIndex = newValue }
	}

	var string: String { return scanner.string }

	var isAtEnd: Bool { return scanner.isAtEnd }

	private func result(_ sub:Substring) -> StringRect {
		let d1 = sub.distance(from: sub.base.startIndex, to: sub.startIndex )
		let d2 = sub.distance(from: sub.base.startIndex, to: sub.endIndex )
		let p1 = substring.index(substring.startIndex, offsetBy: d1)
		let p2 = substring.index(substring.startIndex, offsetBy: d2)
		let rect = rectf(p1..<p2)
		return (String(sub),rect)
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
		return scanAnyWord([word])
	}

	func scanAnyWord(_ words: [String]) -> StringRect? {
		let index = self.currentIndex
		if let scan = scanner.scanCharacters(from: RectScanner.allLetters)?.lowercased() {
			// we match if the scanned word is a 2-3 letter prefix of the first word in the list
			if (2...3).contains(scan.count) && words.first!.hasPrefix(scan) {
				return result(scanner.string[index..<scanner.currentIndex])
			}
			for word in words {
				let word = word.lowercased()
				if scan.count > 4 {
					if LevenshteinDistance( word, scan) <= scan.count/4 {
						return result(scanner.string[index..<scanner.currentIndex])
					}
				} else {
					if word == scan {
						return result(scanner.string[index..<scanner.currentIndex])
					}
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
		self.scanners = strings.map { RectScanner(substring: $0.string, rectf:$0.rectf) }
		self.scannerIndex = 0
	}

	var currentIndex: (scanner:Int, index:String.Index) {
		get { (scannerIndex, scanners[scannerIndex].currentIndex) }
		set { scannerIndex = newValue.0
			scanners[scannerIndex].currentIndex = newValue.1
			for scan in scanners[(scannerIndex+1)...] {
				scan.currentIndex = scan.string.startIndex
			}
		}
	}

	var scanner:RectScanner {
		get {
			while scanners[scannerIndex].isAtEnd && scannerIndex+1 < scanners.count {
				scannerIndex += 1
			}
			return scanners[scannerIndex]
		}
	}

	var isAtEnd: Bool { return scanner.isAtEnd }

	func scanString(_ string: String) -> StringRect? {
		// we need to fudge an implied space at the break between two observations:
		if string == " " && scannerIndex > 0 && scanner.currentIndex == scanner.string.startIndex {
			// return rect for previous character
			let rect = scanners[scannerIndex-1].lastChar().rect
			return (" ",rect)
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
		return scanner.scanWord( word )
	}

	func scanAnyWord(_ words: [String]) -> StringRect? {
		return scanner.scanAnyWord(words)
	}

	func remainder() -> String {
		return scanners[scannerIndex...].map({$0.remainder()}).joined(separator: " ")
	}
}

@available(iOS 13.0, *)
fileprivate enum Day: Int, Strideable, CaseIterable {
	case Mo, Tu, We, Th, Fr, Sa, Su

	func distance(to other: Day) -> Int {
		return (other.rawValue - self.rawValue + 7) % 7
	}

	func advanced(by n: Int) -> Day {
		return Day(rawValue: (self.rawValue + n + 7) % 7)!
	}

	private static let english = [	Day.Mo: ["monday"],
									Day.Tu: ["tuesday"],
									Day.We: ["wednesday"],
									Day.Th: ["thursday", "thur"],
									Day.Fr: ["friday"],
									Day.Sa: ["saturday"],
									Day.Su: ["sunday"]
	]
	private static let french = [	Day.Mo: ["lundi"],
									Day.Tu: ["mardi"],
									Day.We: ["mercredi",	"mercr"],
									Day.Th: ["jeudi"],
									Day.Fr: ["vendredi", 	"vendr"],
									Day.Sa: ["samedi"],
									Day.Su: ["dimanche"]
	]
	private static let german = [	Day.Mo: ["montag"],
									Day.Tu: ["dienstag"],
									Day.We: ["mittwoch"],
									Day.Th: ["donnerstag"],
									Day.Fr: ["freitag"],
									Day.Sa: ["samstag"],
									Day.Su: ["sonntag"]
	]
	private static let italian = [	Day.Mo: ["lunedì"],
									Day.Tu: ["martedì"],
									Day.We: ["mercoledì"],
									Day.Th: ["giovedì"],
									Day.Fr: ["venerdì"],
									Day.Sa: ["sabato"],
									Day.Su: ["domenica"]
	]

	static func scan(scanner:MultiScanner, language:HoursRecognizer.Language) -> (day:Self, rect:CGRect, confidence:Float)? {
		let dict = { () -> [Day:[String]] in
			switch language {
			case .en: return english
			case .fr: return french
			case .de: return german
			case .it: return italian
			}
		}()
		for (day,strings) in dict {
			if let s = scanner.scanAnyWord(strings) {
				return (day,s.rect,Float(s.string.count))
			}
		}
		return nil
	}

	fileprivate static func rangeForSet( _ set: Set<Day> ) -> [DayRange] {
		var dayList = [DayRange]()
		var dayRange: DayRange? = nil
		for d in Day.allCases {
			if set.contains(d) {
				if let range = dayRange {
					dayRange = DayRange(start: range.start, end: d)
				} else {
					dayRange = DayRange(start: d, end: d)
				}
			} else {
				if let range = dayRange {
					dayList.append( range )
				}
				dayRange = nil
			}
		}
		if let range = dayRange {
			dayList.append( range )
		}
		return dayList
	}
}

@available(iOS 13.0, *)
fileprivate struct Time: Comparable, Hashable {

	let minutes: Int

	var text: String { return String(format: "%02d:%02d", minutes/60, minutes%60) }

	init(hour: Int, minute:Int) {
		self.minutes = hour*60 + minute
	}

	static func < (lhs: Time, rhs: Time) -> Bool {
		return lhs.minutes < rhs.minutes
	}

	static func scan(scanner: MultiScanner, language:HoursRecognizer.Language) -> (time:Self, rect:CGRect, confidence:Float)? {
		let seperators: [String] = { () -> [String] in
		switch language {
		case .fr:
			return [":", ".", " ", "h"]
		case .de, .en, .it:
			return [":", ".", " "]
		}}()

		let index = scanner.currentIndex
		guard let hour = scanner.scanInt() else { return nil }
		if let iHour = Int(hour.string),
		   iHour >= 0 && iHour <= 24
		{
			let index2 = scanner.currentIndex
			if seperators.first(where: {scanner.scanString($0) != nil}) != nil,
			   let minute = scanner.scanInt(),
			   minute.string.count == 2,
			   minute.string >= "00" && minute.string < "60"
			{
				_ = scanner.scanWhitespace()
				if let am = scanner.scanString("AM") {
					return (Time(hour: iHour%12, minute: Int(minute.string)!),
							hour.rect.union(am.rect),
							8.0)
				}
				if let pm = scanner.scanString("PM") {
					return (Time(hour: (iHour%12)+12, minute: Int(minute.string)!),
							hour.rect.union(pm.rect),
							8.0)
				}
				return (Time(hour: iHour, minute: Int(minute.string)!),
						hour.rect.union(minute.rect),
						6.0)
			}
			scanner.currentIndex = index2

			_ = scanner.scanWhitespace()
			if let am = scanner.scanString("AM") {
				return (Time(hour: iHour%12, minute: 0),
						hour.rect.union(am.rect),
						4.0)
			}
			if let pm = scanner.scanString("PM") {
				return (Time(hour: (iHour%12)+12, minute: 0),
						hour.rect.union(pm.rect),
						4.0)
			}
			return (Time(hour: iHour, minute: 0),
					hour.rect,
					1.0)
		}
		scanner.currentIndex = index
		return nil
	}
}

@available(iOS 13.0, *)
fileprivate struct Dash {
	static func scan(scanner: MultiScanner, language: HoursRecognizer.Language) -> (Self,CGRect,Float)? {
		let through = { () -> String in
			switch language {
			case .en: return "to"
			case .de: return "bis"
			case .fr: return "à"
			case .it: return "alle"
			}}()

		if let s = scanner.scanString("-") ?? scanner.scanWord(through) {
			return (Dash(), s.rect, Float(s.string.count))
		}
		return nil
	}
}

@available(iOS 13.0, *)
fileprivate struct DayRange : Hashable { let start:Day; let end:Day }
@available(iOS 13.0, *)
fileprivate struct TimeRange : Hashable { let start:Time; let end:Time }

fileprivate typealias SubstringRectConfidence = (substring:Substring, rect:CGRect, rectf:(Range<String.Index>)->CGRect, confidence:Float)
@available(iOS 13.0, *)
fileprivate typealias TokenRectConfidence = (token:Token, rect:CGRect, confidence:Float)

@available(iOS 13.0, *)
fileprivate enum Token : Equatable {
	case time(Time)
	case day(Day)
	case dash(Dash)
	case endOfText

	static func == (lhs: Token, rhs: Token) -> Bool {
		return "\(lhs)" == "\(rhs)"
	}

	func day() -> Day? {
		switch self {
		case let .day(day):		return day
		default:				return nil
		}
	}
	func time() -> Time? {
		switch self {
		case let .time(time):	return time
		default:				return nil
		}
	}
	func dash() -> Dash? {
		switch self {
		case let .dash(dash):	return dash
		default:				return nil
		}
	}
	func isDay() -> Bool {	return day() != nil	}
	func isTime() -> Bool {	return time() != nil }
	func isDash() -> Bool {	return dash() != nil }

	static func scan(scanner: MultiScanner, language: HoursRecognizer.Language) -> TokenRectConfidence? {
		if let (day,rect,confidence) = Day.scan(scanner: scanner, language: language) {
			return (.day(day),rect,confidence)
		}
		if let (time,rect,confidence) = Time.scan(scanner: scanner, language: language) {
			return (.time(time),rect,confidence)
		}
		if let (dash,rect,confidence) = Dash.scan(scanner: scanner, language: language) {
			return (.dash(dash),rect,confidence)
		}
		return nil
	}
}

@available(iOS 13.0, *)
public class HoursRecognizer: ObservableObject {

	private var resultHistory = [String:Int]()
	@Published private(set) var finished = false {
		willSet {
			objectWillChange.send()
		}
	}

	static var lastLanguageSelected = { () -> Language in
		if let raw = UserDefaults().value(forKey: "HoursRecognizerLanguage") as? Language.RawValue,
		   let lang = Language(rawValue: raw) {
			return lang
		}
		return Language.en
	}()
	@Published public var language: Language = lastLanguageSelected {
		willSet {
			HoursRecognizer.lastLanguageSelected = newValue
			UserDefaults().setValue(newValue.rawValue, forKey: "HoursRecognizerLanguage")
		}
	}

	@Published var text = "" {
		willSet {
			objectWillChange.send()
		}
	}

	init() {
	}

	public enum Language: String, CaseIterable, Identifiable {
		// these must be ISO codes
		case en = "en"
		case de = "de"
		case fr = "fr"
		case it = "it"

		public var id: String { self.rawValue }
		public var isoCode: String { "\(self)" }
		public var name: String { Locale(identifier: self.rawValue).localizedString(forIdentifier:self.rawValue) ?? "<??>" }
	}

	public func restart() {
		self.text = ""
		self.resultHistory.removeAll()
		self.finished = false
	}

	private class func tokensForString(_ strings: [SubstringRectConfidence], language: Language) -> [TokenRectConfidence] {
		var list = [TokenRectConfidence]()

		let scanner = MultiScanner(strings: strings.map { return ($0.substring, $0.rectf)} )
		_ = scanner.scanWhitespace()
		while !scanner.isAtEnd {
			if let token = Token.scan(scanner: scanner, language: language) {
				list.append( token )
			} else {
				// skip to next token
				_ = scanner.scanUpToWhitespace()
			}
			_ = scanner.scanWhitespace()
		}
		return list
	}

	// takes an array of image observations and returns blocks of text along with their locations
	private class func stringsForImage(observations: [VNRecognizedTextObservation], transform:CGAffineTransform) -> [SubstringRectConfidence] {
		var wordList = [SubstringRectConfidence]()
		for observation in observations {
			guard let candidate = observation.topCandidates(1).first else { continue }
			// Each observation can contain text in disconnected parts of the screen,
			// so we tokenize the string and extract the screen location of each token
			let rectf:(Range<String.Index>)->CGRect = {
				let rect = try! candidate.boundingBox(for: $0)!.boundingBox
				let rect2 = rect.applying(transform)
				return rect2
			}
			let words = candidate.string.split(separator: " ")
			let words2 = words.map({ word -> SubstringRectConfidence in
				// Previous call returns tokens with substrings, which we can pass to candidate to get the rect
				let rect = rectf( word.startIndex ..< word.endIndex )
				return (word, rect, rectf, candidate.confidence)
			})
			wordList += words2
		}
		return wordList
	}

	// split observed text text blocks into lines of text, sorted left-to-right and top-to-bottom
	private class func getStringLines( _ allStrings: [SubstringRectConfidence] ) -> [[SubstringRectConfidence]] {
		var lines = [[SubstringRectConfidence]]()

		var list = allStrings

		while !list.isEmpty {

			// get highest confidence string
			let bestIndex = list.indices.max(by: {list[$0].confidence < list[$1].confidence})!
			let best = list[ bestIndex ]
			list.remove(at: bestIndex)
			var lineStrings = [best]

			// find tokens to left
			var prev = best
			while true {
				let strings = list.indices.filter({ list[$0].rect.maxX <= prev.rect.minX && (prev.rect.minY...prev.rect.maxY).contains( list[$0].rect.midY )})
				if strings.isEmpty { break }
				let closest = strings.min(by: {prev.rect.minX - list[$0].rect.maxX < prev.rect.minX - list[$1].rect.maxX})!
				prev = list[closest]
				lineStrings.insert( prev, at: 0)
				list.remove(at: closest)
			}

			// find tokens to right
			prev = best
			while true {
				let strings = list.indices.filter({ list[$0].rect.minX >= prev.rect.maxX && (prev.rect.minY...prev.rect.maxY).contains( list[$0].rect.midY )})
				if strings.isEmpty { break }
				let closest = strings.min(by: {list[$0].rect.minX - prev.rect.maxX < list[$1].rect.minX - prev.rect.maxX})!
				prev = list[closest]
				lineStrings.append( prev )
				list.remove(at: closest)
			}

			// save the line of strings
			lines.append( lineStrings )
		}

		// sort lines top-to-bottom
		lines.sort(by: {$0.first!.rect.minY < $1.first!.rect.minY} )

		return lines
	}

	// convert lines of strings to lines of tokens
	private class func tokenLinesForStringLines( _ stringLines: [[SubstringRectConfidence]], language: Language) -> [[TokenRectConfidence]] {
		let tokenLines = stringLines.compactMap { line -> [TokenRectConfidence]? in
			let tokens = HoursRecognizer.tokensForString( line, language: language )
			return tokens.isEmpty ? nil : tokens
		}
		return tokenLines
	}

	// split the lines so each sequence of days or times is in its own group
	private class func homogeneousSequencesForTokenLines( _ tokenLines: [[TokenRectConfidence]]) -> [[TokenRectConfidence]] {
		var tokenSets = [[TokenRectConfidence]]()
		for line in tokenLines {
			guard let first = line.indices.first(where: {!line[$0].token.isDash()}) else { continue }
			tokenSets.append([line[first]] )
			var prevDash: TokenRectConfidence? = nil

			for token in line[(first+1)...] {
				if token.token.isDash() {
					prevDash = token
				} else if token.token.isDay() == tokenSets.last?.first?.token.isDay() ||
						  token.token.isTime() == tokenSets.last?.first?.token.isTime()
				{
					if let dash = prevDash {
						tokenSets[tokenSets.count-1].append(dash)
						prevDash = nil
					}
					tokenSets[tokenSets.count-1].append(token)
				} else {
					prevDash = nil
					tokenSets.append([token])
				}
			}
			tokenSets.append([])
		}
		tokenSets.removeAll(where: { $0.isEmpty })

		return tokenSets
	}


	// if a sequence has multiple days then take only the best 2
	private class func GoodDaysForTokenSequences( _ tokenSet: [TokenRectConfidence]) -> [TokenRectConfidence]? {
		// return tokenSets.map( { return $0.first!.token.isDay() ? $0.bestTwo( {$0.confidence < $1.confidence} ) : $0 })
		return tokenSet
	}

	// if a sequence has multiple times then take only the best even number
	private class func GoodTimesForTokenSequences( _ tokenSet: [TokenRectConfidence]) -> [TokenRectConfidence]? {
		var list = tokenSet
		var pairs = [(TokenRectConfidence,TokenRectConfidence)]()

		// pull out dash-seperated pairs
		while let dash = list.indices.first(where: {list[$0].token.isDash()}) {
			if dash > 1 && dash+1 < list.count {
				var priors = Array(list[0..<dash-1])
				if priors.count % 2 == 1 {
					let worst = priors.indices.min(by: {priors[$0].confidence < priors[$1].confidence})!
					priors.remove(at: worst)
				}
				while !priors.isEmpty {
					pairs.append( (priors[0], priors[1] ) )
					priors.removeSubrange(0...1)
				}
				pairs.append( (list[dash-1], list[dash+1]) )
				list.removeSubrange( 0...dash+1 )
			} else {
				list.remove(at: dash)
			}
		}
		if list.count % 2 == 1 {
			let worst = list.indices.min(by: {list[$0].confidence < list[$1].confidence})!
			list.remove(at: worst)
		}
		while !list.isEmpty {
			pairs.append( (list[0], list[1] ) )
			list.removeSubrange(0...1)
		}

		// look for suspicious pairs
		pairs.removeAll(where: {"\($0.0.token)" == "00:00" && "\($0.1.token)" == "00:00"})

		return pairs.count > 0 ? pairs.flatMap({ [$0.0,$0.1] }) : nil
	}

	// convert lists of tokens to a list of day/time ranges
	private class func hoursForTokens(_ tokenLines: [[TokenRectConfidence]]) -> [([DayRange],[TimeRange])] {
		var days = [Day]()
		var times = [Time]()
		var result = [([DayRange],[TimeRange])]()

		for line in tokenLines + [[(.endOfText,CGRect(),0.0)]] {
			// each line should be 1 or more days, then 2 or more hours
			for token in line  {
				switch token.token {
				case .day, .endOfText:
					if times.count >= 2 {
						// output preceding days/times
						var dayRange = [DayRange]()
						if days.count > 0 {
							if days.count == 2 {
								// treat as a range of days
								dayRange = [DayRange(start: days[0], end: days[1])]
							} else {
								// treat as a list of days
								dayRange = days.map({DayRange(start: $0, end: $0)})
							}
						}

						let timeRange = stride(from: 0, to: times.count, by: 2).map({ TimeRange(start: times[$0], end: times[$0+1]) })

						result.append( (dayRange, timeRange) )
					}
					if times.count > 0 {
						times = []
						days = []
					}
					if let day = token.token.day() {
						days.append( day )
					}

				case .time:
					times.append(token.token.time()!)
					break
				case .dash:
					break
				}
			}
		}
		return result
	}

	private class func coalesceDays(_ dayTimeRanges: [([DayRange],[TimeRange])] ) -> [([DayRange],[TimeRange])] {
		var dict = [[TimeRange] : Set<Day>]()
		for dayTime in dayTimeRanges {
			var daySet = Set( dayTime.0.flatMap({ stride(from: $0.start, through: $0.end, by: 1) }))
			if let set = dict[ dayTime.1 ] {
				daySet = daySet.union(set)
			}
			dict[ dayTime.1 ] = daySet
		}

		var list = dict.map({ (times,days) -> ([DayRange],[TimeRange]) in
			let dayList = Day.rangeForSet(days)
			return (dayList,times)
		})
		list.sort(by: {($0.0.first?.start.rawValue ?? -1) < ($1.0.first?.start.rawValue ?? -1)})
		return list
	}

	// convert lists of tokens to the final string
	private class func hoursStringForHours(_ dayTimeRanges: [([DayRange],[TimeRange])] ) -> String {
		return dayTimeRanges.map { (days,times) in
			var result = ""
			if !days.isEmpty {
				result += days.map({ $0.start == $0.end ? "\($0.start)" : "\($0.start)-\($0.end)"})
					.joined(separator: ",")
				result += " "
			}
			result += times.map({"\($0.start)-\($0.end)"})
				.joined(separator: ",")
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
		let stringLines = HoursRecognizer.getStringLines( strings )

		#if true
		print("")
		print("string lines:")
		for line in stringLines {
			let s1 = line.map({$0.substring}).joined(separator: " ")
			let s2 = line.map({"\($0.confidence)"}).joined(separator: " ")
			print("\(s1): \(s2)")
		}
		#endif

		// convert strings to tokens
		var tokenSets = HoursRecognizer.tokenLinesForStringLines( stringLines, language: self.language )

		#if true
		print("")
		print("token lines:")
		for s in tokenSets {
			let s1 = s.map({ "\($0.token)"}).joined(separator: " ")
			let s2 = s.map({ "\($0.confidence)"}).joined(separator: " ")
			print("\(s1): \(s2)")
		}
		#endif

		tokenSets = HoursRecognizer.homogeneousSequencesForTokenLines( tokenSets )

		// get homogeneous day/time sets
		tokenSets = tokenSets.compactMap {
			if $0.first!.token.isDay() {
				return HoursRecognizer.GoodDaysForTokenSequences( $0 )
			} else {
				return HoursRecognizer.GoodTimesForTokenSequences( $0 )
			}
		}

		#if false
		print("")
		for line in tokenSets {
			let s1 = line.map( { "\($0.token)" }).joined(separator: " ")
			let s2 = line.map( { "\(Float(Int(100.0*$0.confidence))/100.0)" }).joined(separator: " ")
			print("\(s1): \(s2)")
		}
		#endif

		// convert the final sets of tokens to a single stream
		var resultArray = HoursRecognizer.hoursForTokens( tokenSets )
		resultArray = HoursRecognizer.coalesceDays( resultArray )

		let resultString = HoursRecognizer.hoursStringForHours( resultArray )

		// show the selected tokens in the video feed
		let invertedTransform = transform.inverted()
		let tokenBoxes = tokenSets.joined().map({$0.rect.applying(invertedTransform)})
		camera?.addBoxes(boxes: tokenBoxes, color: UIColor.green)

		#if false
		print("\(text)")
		#endif

		if resultString != "" {
			let count = (resultHistory[resultString] ?? 0) + 1
			resultHistory[resultString] = count

			let best = resultHistory.max { $0.value < $1.value }!

			if Thread.isMainThread {
				self.text = best.key
				self.finished = best.value >= 5
			} else {
				DispatchQueue.main.async {
					self.text = best.key
					self.finished = best.value >= 5
				}
			}
		}
	}

	func updateWithLiveObservations(observations: [VNRecognizedTextObservation], camera: CameraView?) {
		self.updateWithObservations(observations: observations,
									transform: CGAffineTransform(scaleX: 1, y: -1).translatedBy(x: 0, y: 1),
									   camera: camera)
	}

	func setImage(image: CGImage, isRotated: Bool) {
		self.restart()

//		let rotationTransform = CGAffineTransform(translationX: 0, y: 1).rotated(by: -CGFloat.pi / 2)

		let transform = isRotated ? CGAffineTransform(scaleX: 1.0, y: -1.0).rotated(by: -CGFloat.pi / 2)
									: CGAffineTransform.identity

		let request = VNRecognizeTextRequest(completionHandler: { (request, error) in
			guard error == nil,
				  let observations = request.results as? [VNRecognizedTextObservation] else { return }
			self.updateWithObservations(observations: observations, transform: transform, camera:nil)
		})
		request.recognitionLevel = .accurate
//		request.customWords = ["AM","PM"]
//		request.usesLanguageCorrection = true
		let requestHandler = VNImageRequestHandler(cgImage: image, options: [:])
		try? requestHandler.perform([request])
	}
}

#if targetEnvironment(macCatalyst)
class BulkProcess {
	init() {
	}

	func processFile(path:String) {
		do {
			let userDirectory = try FileManager.default.url(for: FileManager.SearchPathDirectory.downloadsDirectory, in: .userDomainMask, appropriateFor: nil, create: false)
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

	func processFolder(path:String) {
		do {
			let userDirectory = try FileManager.default.url(for: FileManager.SearchPathDirectory.downloadsDirectory, in: .userDomainMask, appropriateFor: nil, create: false)
			let imageDirectory = userDirectory.appendingPathComponent(path)
			let fileList = try FileManager.default.contentsOfDirectory(at: imageDirectory, includingPropertiesForKeys: nil, options: [])
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

