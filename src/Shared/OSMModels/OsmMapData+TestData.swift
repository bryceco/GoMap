import Foundation

extension OsmMapData {
	/// Load OSM data from a dictionary. Intended for setting up test fixtures.
	///
	/// Expected format:
	/// ```
	/// [
	///   "nodes": [["id": 1, "lat": 47.0, "lon": -122.0, "tags": ["key": "value"]]],
	///   "ways": [["id": 100, "nodes": [1, 2, 3], "tags": ["highway": "residential"]]],
	///   "relations": [["id": 1000, "members": [["type": "way", "ref": 100, "role": "forward"]], "tags": ["type": "route"]]]
	/// ]
	/// ```
	/// All IDs must be positive. Nodes must appear before ways or relations that reference them.
	func initWith(dict: [String: Any]) throws {
		purgeHard()

		var serverData = OsmServerData()

		if let nodes = dict["nodes"] as? [[String: Any]] {
			serverData.nodes = nodes.map { d in
				OsmServerNode(ident: Self.asInt64(d["id"]!),
				              version: 1, changeset: 0, user: "", uid: 0, timestamp: "",
				              tags: d["tags"] as? [String: String] ?? [:],
				              body: LatLon(lon: Self.asDouble(d["lon"]!),
				                           lat: Self.asDouble(d["lat"]!)))
			}
		}

		if let ways = dict["ways"] as? [[String: Any]] {
			serverData.ways = ways.map { d in
				OsmServerWay(ident: Self.asInt64(d["id"]!),
				             version: 1, changeset: 0, user: "", uid: 0, timestamp: "",
				             tags: d["tags"] as? [String: String] ?? [:],
				             body: Self.asInt64Array(d["nodes"]!))
			}
		}

		if let relations = dict["relations"] as? [[String: Any]] {
			serverData.relations = try relations.map { d in
				let members = try (d["members"] as? [[String: Any]] ?? []).map { m in
					try OsmServerMember(type: OSM_TYPE(string: m["type"] as! String),
					                    ref: Self.asInt64(m["ref"]!),
					                    role: m["role"] as? String)
				}
				return OsmServerRelation(ident: Self.asInt64(d["id"]!),
				                         version: 1, changeset: 0, user: "", uid: 0, timestamp: "",
				                         tags: d["tags"] as? [String: String] ?? [:],
				                         body: members)
			}
		}

		try merge(serverData)
	}

	// All Swift numeric types bridge to NSNumber, so these safely
	// handle Int, Int64, Double, etc. from untyped dictionaries.
	private static func asInt64(_ value: Any) -> Int64 { (value as! NSNumber).int64Value }
	private static func asDouble(_ value: Any) -> Double { (value as! NSNumber).doubleValue }
	private static func asInt64Array(_ value: Any) -> [Int64] { (value as! [Any]).map(asInt64) }
}
