//
//  OsmType.swift
//  Go Map!!
//
//  Created by Bryce Cogswell on 3/4/23.
//  Copyright © 2023 Bryce Cogswell. All rights reserved.
//

import Foundation

enum OsmObjectError: Error {
	case invalidRelationMemberType
	case invalidObjectType

	public var errorDescription: String? {
		switch self {
		case .invalidRelationMemberType: return "invalidRelationMemberType"
		case .invalidObjectType: return "invalidObjectType"
		}
	}
}

enum OSM_TYPE: Int {
	case NODE = 1
	case WAY = 2
	case RELATION = 3

	var string: String {
		switch self {
		case .NODE: return "node"
		case .WAY: return "way"
		case .RELATION: return "relation"
		}
	}

	init(string: String) throws {
		switch string {
		case "node": self = .NODE
		case "way": self = .WAY
		case "relation": self = .RELATION
		default: throw OsmObjectError.invalidObjectType
		}
	}
}
