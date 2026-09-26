import Foundation

/// An OSM object exactly as the server describes it: a plain value with no links to other
/// objects and nothing the user can edit. This is what the parser and the SQL database
/// produce, what the database writes, and what OsmNode/OsmWay/OsmRelation are built from.
/// Being a value type it can be handed to the database queue without copying and without
/// any risk that the main thread edits it while it's being written.
struct OsmServerObject<Body> {
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
		DbgAssert(ident > 0)
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
	/// received from the server (ident > 0); user-created objects never go in the database.
	private init(_ obj: OsmBaseObject, body: Body) {
		DbgAssert(obj.ident > 0)
		DbgAssert(!obj.isModified)
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

extension OsmServerObject: Sendable where Body: Sendable {}
extension OsmServerObject: Codable where Body: Codable {}

extension OsmServerObject where Body: Codable {
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

typealias OsmServerNode = OsmServerObject<LatLon>
typealias OsmServerWay = OsmServerObject<[OsmIdentifier]>
typealias OsmServerRelation = OsmServerObject<[OsmServerMember]>

/// A relation member exactly as the server describes it: type, ref, and role
/// with no resolved object reference. This is the value-type counterpart of OsmMember.
struct OsmServerMember: Codable {
	let type: OSM_TYPE
	let ref: OsmIdentifier
	let role: String?

	init(type: OSM_TYPE, ref: OsmIdentifier, role: String?) {
		self.type = type
		self.ref = ref
		self.role = role
	}

	init(_ member: OsmMember) {
		type = member.type
		ref = member.ref
		role = member.role
	}
}

extension OsmServerObject where Body == LatLon {
	var latLon: LatLon { body }
	init(_ node: OsmNode) { self.init(node, body: node.latLon) }
}

extension OsmServerObject where Body == [OsmIdentifier] {
	var nodeRefs: [OsmIdentifier] { body }
	init(_ way: OsmWay) { self.init(way, body: way.nodes.map(\.ident)) }
}

extension OsmServerObject where Body == [OsmServerMember] {
	var members: [OsmServerMember] { body }
	init(_ relation: OsmRelation) { self.init(relation, body: relation.members.map(OsmServerMember.init)) }
}

struct OsmServerData {
	var nodes: [OsmServerNode] = []
	var ways: [OsmServerWay] = []
	var relations: [OsmServerRelation] = []

	init(nodes: [OsmServerNode] = [], ways: [OsmServerWay] = [], relations: [OsmServerRelation] = []) {
		self.nodes = nodes
		self.ways = ways
		self.relations = relations
	}
}
