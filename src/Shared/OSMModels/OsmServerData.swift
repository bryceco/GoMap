import Foundation

/// An OSM object exactly as the server describes it: a plain value with no links to other
/// objects and nothing the user can edit. This is what the parser and the SQL database
/// produce, what the database writes, and what OsmNode/OsmWay/OsmRelation are built from.
/// Being a value type it can be handed to the database queue without copying and without
/// any risk that the main thread edits it while it's being written.
struct OsmObjectData<Body> {
	let ident: OsmIdentifier
	let version: Int
	let changeset: Int64
	let user: String
	let uid: Int
	let timestamp: String
	let tags: [String: String]
	let body: Body

	init(ident: OsmIdentifier, version: Int, changeset: Int64, user: String, uid: Int,
	     timestamp: String, tags: [String: String], body: Body)
	{
		self.ident = ident
		self.version = version
		self.changeset = changeset
		self.user = user
		self.uid = uid
		self.timestamp = timestamp
		self.tags = tags
		self.body = body
	}

	/// Copy the server-visible fields of a live object. Only for objects that were
	/// received from the server (ident > 0); new objects never go in the database.
	private init(_ obj: OsmBaseObject, body: Body) {
		ident = obj.ident
		version = obj.version
		changeset = obj.changeset
		user = obj.user
		uid = obj.uid
		timestamp = obj.timestamp
		tags = obj.tags
		self.body = body
	}
}

extension OsmObjectData: Sendable where Body: Sendable {}
extension OsmObjectData: Codable where Body: Codable {}

extension OsmObjectData where Body: Codable {
	/// Serialize to binary plist for archiving
	func serializedData() -> Data {
		let encoder = PropertyListEncoder()
		encoder.outputFormat = .binary
		return try! encoder.encode(self)
	}

	/// Deserialize from binary plist
	init?(serializedData data: Data) {
		guard let value = try? PropertyListDecoder().decode(Self.self, from: data) else {
			return nil
		}
		self = value
	}
}

typealias OsmNodeData = OsmObjectData<LatLon>
typealias OsmWayData = OsmObjectData<[OsmIdentifier]>
typealias OsmRelationData = OsmObjectData<[OsmMember]>

extension OsmObjectData where Body == LatLon {
	var latLon: LatLon { body }
	init(_ node: OsmNode) { self.init(node, body: node.latLon) }
}

extension OsmObjectData where Body == [OsmIdentifier] {
	var nodeRefs: [OsmIdentifier] { body }
	init(_ way: OsmWay) { self.init(way, body: way.nodes.map(\.ident)) }
}

extension OsmObjectData where Body == [OsmMember] {
	var members: [OsmMember] { body }
	init(_ relation: OsmRelation) { self.init(relation, body: relation.members) }
}

struct OsmServerData {
	var nodes: [OsmNodeData] = []
	var ways: [OsmWayData] = []
	var relations: [OsmRelationData] = []

	init(nodes: [OsmNodeData] = [], ways: [OsmWayData] = [], relations: [OsmRelationData] = []) {
		self.nodes = nodes
		self.ways = ways
		self.relations = relations
	}
}
