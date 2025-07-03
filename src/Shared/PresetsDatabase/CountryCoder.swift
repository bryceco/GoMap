import UIKit

public struct CountryCoderRegion {
	let country: String? // Country code
	let iso1A2: String? // ISO 3166-1 alpha-2 code
	let iso1A3: String? // ISO 3166-1 alpha-3 code
	let iso1N3: String? // ISO 3166-1 numeric-3 code
	let m49: String? // UN M49 code
	let wikidata: String?
	let aliases: [String]
	let callingCodes: [String]
	let groups: [String]

	let bezierPath: UIBezierPath?
	let boundingBox: CGRect

	init(country: String?,
	     iso1A2: String?, iso1A3: String?, iso1N3: String?, m49: String?, wikidata: String?,
	     aliases: [String],
	     callingCodes: [String],
	     groups: [String],
	     bezierPath: UIBezierPath?)
	{
		self.country = country?.lowercased()
		self.iso1A2 = iso1A2?.lowercased()
		self.iso1A3 = iso1A3?.lowercased()
		self.iso1N3 = iso1N3 // numeric code
		self.m49 = m49 // numeric code
		self.wikidata = wikidata?.lowercased()
		self.aliases = aliases.map({ $0.lowercased() })
		self.callingCodes = callingCodes
		self.groups = groups.map({ $0.lowercased() })
		self.bezierPath = bezierPath
		boundingBox = bezierPath == nil ? CGRect() : bezierPath!.bounds
	}

	fileprivate func addSynonyms(to list: inout [String]) {
		if let s = iso1A2 { list.append(s) }
		if let s = iso1A3 { list.append(s) }
		if let s = m49 { list.append(s) }
		if let s = iso1N3 { list.append(s) }
		if let s = wikidata { list.append(s) }
		list.append(contentsOf: aliases)
	}
}

public final class CountryCoder {
	public static let shared = CountryCoder()

	let regionList: [CountryCoderRegion]
	let regionDict: [String: CountryCoderRegion]

	private init() {
		struct Welcome: Decodable {
			let type: String
			let features: [Feature]
		}
		struct Feature: Decodable {
			let type: String
			let properties: Properties
			let geometry: GeoJSONGeometry?
		}
		struct Properties: Decodable {
			let wikidata, nameEn: String
			let aliases: [String]?
			let country: String?
			let groups: [String]?
			let driveSide, roadSpeedUnit, roadHeightUnit: String?
			let callingCodes: [String]?
			let level, m49, iso1A2, iso1A3: String?
			let isoStatus, iso1N3, ccTLD: String?
		}

		guard
			let path = Bundle.main.resourcePath,
			let data = try? Data(contentsOf: URL(fileURLWithPath: path + "/presets/borders.json"),
			                     options: .mappedIfSafe),
			let jsonResult = try? JSONDecoder().decode(Welcome.self, from: data),
			jsonResult.type == "FeatureCollection"
		else {
			fatalError()
		}

		var regions: [CountryCoderRegion] = []

		for feature in jsonResult.features {
			let bezierPath = feature.geometry?.latLonBezierPath
			let properties = feature.properties
			regions.append(CountryCoderRegion(country: properties.country,
			                                  iso1A2: properties.iso1A2,
			                                  iso1A3: properties.iso1A3,
			                                  iso1N3: properties.iso1N3,
			                                  m49: properties.m49,
			                                  wikidata: properties.wikidata,
			                                  aliases: properties.aliases ?? [],
			                                  callingCodes: properties.callingCodes ?? [],
			                                  groups: properties.groups ?? [],
			                                  bezierPath: bezierPath))
		}
		regionList = regions

		var dict = [String: CountryCoderRegion]()
		for r in regions {
			if let s = r.iso1A2 { dict[s] = r }
			if let s = r.iso1A3 { dict[s] = r }
			if let s = r.iso1N3 { dict[s] = r }
			if let s = r.m49 { dict[s] = r }
			if let s = r.wikidata { dict[s] = r }
		}
		regionDict = dict
	}

	func regionsAt(_ loc: LatLon) -> [CountryCoderRegion] {
		var list: [CountryCoderRegion] = []
		let cgPoint = CGPoint(OSMPoint(loc))
		for region in regionList {
			if region.boundingBox.contains(cgPoint),
			   region.bezierPath?.contains(cgPoint) ?? false
			{
				list.append(region)
			}
		}
		if let countryCode = list.first(where: { $0.country != nil })?.country,
		   let country = regionDict[countryCode]
		{
			list.append(country)
		}
		for region in list {
			for group in region.groups {
				if let r = regionDict[group] {
					list.append(r)
				}
			}
		}
		return list
	}

	static func regionsStringsForRegions(_ list: [CountryCoderRegion]) -> [String] {
		var result: [String] = []
		for region in list {
			region.addSynonyms(to: &result)
		}
		return result
	}

	static func countryforRegions(_ list: [CountryCoderRegion]) -> String {
		if let country = list.first(where: { $0.country != nil })?.country {
			return country
		}
		if let country = list.first(where: { $0.iso1A2 != nil })?.iso1A2 {
			return country
		}
		return ""
	}
}
