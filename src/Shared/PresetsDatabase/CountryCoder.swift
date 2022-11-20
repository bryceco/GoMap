import UIKit

struct Region {
	let country: String? // Country code
	let iso1A2: String? // ISO 3166-1 alpha-2 code
	let iso1A3: String? // ISO 3166-1 alpha-3 code
	let iso1N3: String? // ISO 3166-1 numeric-3 code
	let m49: String? // UN M49 code

	let bezierPath: UIBezierPath
	let boundingBox: CGRect

	init(country: String?, iso1A2: String?, iso1A3: String?, iso1N3: String?, m49: String?, bezierPath: UIBezierPath) {
		self.country = country
		self.iso1A2 = iso1A2
		self.iso1A3 = iso1A3
		self.iso1N3 = iso1N3
		self.m49 = m49
		self.bezierPath = bezierPath
		boundingBox = bezierPath.bounds
	}

	func matchesCode(_ code: String) -> Bool {
		return code == country ||
			code == iso1A2 ||
			code == iso1A3 ||
			code == iso1N3 ||
			code == m49
	}

	private static func addPoints(_ points: [[Double]], to path: UIBezierPath) {
		var first = true
		for pt in points {
			if pt.count != 2 {
				continue
			}
			let lon = pt[0]
			let lat = pt[1]
			let cgPoint = CGPoint(x: lon, y: lat)
			if first {
				path.move(to: cgPoint)
				first = false
			} else {
				path.addLine(to: cgPoint)
			}
		}
		path.close()
	}

	static func geometryAsBezier(_ geometry: [[[[Double]]]]) -> UIBezierPath {
		let path = UIBezierPath()
		for outer in geometry {
			for loop in outer {
				addPoints(loop, to: path)
			}
		}
		return path
	}
}

public class CountryCoder {
	public static let shared = CountryCoder()

	let regionList: [Region]
	let regionDict: [String: Region]

	private init() {
		guard let path = Bundle.main.resourcePath,
		      let data = try? Data(
		      	contentsOf: URL(fileURLWithPath: path + "/presets/borders.json"),
		      	options: .mappedIfSafe),
		      let jsonResult = try? JSONSerialization.jsonObject(with: data, options: []),
		      let jsonResult = jsonResult as? [String: Any],
		      (jsonResult["type"] as? String) == "FeatureCollection",
		      let features = jsonResult["features"] as? [Any]
		else {
			fatalError()
		}

		var regions: [Region] = []

		for featureAny in features {
			guard let feature = featureAny as? [String: Any],
			      let properties = feature["properties"] as? [String: Any]
			else {
				fatalError()
			}
			guard let geometry = feature["geometry"] as? [String: Any] else {
				let name = properties["nameEn"] as! String
				print("Skipping \(name)")
				continue
			}

			let country = properties["country"] as? String
			let iso1A2 = properties["iso1A2"] as? String
			let iso1A3 = properties["iso1A3"] as? String
			let iso1N3 = properties["iso1N3"] as? String
			let m49 = properties["m49"] as? String

			switch geometry["type"] as? String {
			case "MultiPolygon":
				guard let mp = geometry["coordinates"] as? [[[[Double]]]] else {
					fatalError()
				}
				regions.append(Region(country: country,
				                      iso1A2: iso1A2,
				                      iso1A3: iso1A3,
				                      iso1N3: iso1N3,
				                      m49: m49,
				                      bezierPath: Region.geometryAsBezier(mp)))
			default:
				fatalError()
			}
		}
		regionList = regions

		var dict = [String: Region]()
		for r in regions {
			if let s = r.country { dict[s] = r }
			if let s = r.iso1A2 { dict[s] = r }
			if let s = r.iso1A3 { dict[s] = r }
			if let s = r.iso1N3 { dict[s] = r }
			if let s = r.m49 { dict[s] = r }
		}
		regionDict = dict
	}

	public func region(_ code: String, contains latLon: CGPoint) -> Bool {
		let upper = code.uppercased()
		if let region = regionDict[upper],
		   region.boundingBox.contains(latLon),
		   region.bezierPath.contains(latLon)
		{
			return true
		}
		return false
	}
}
