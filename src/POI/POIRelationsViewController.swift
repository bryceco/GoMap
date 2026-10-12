//
//  POIRelationsViewController.swift
//  Go Map!!
//
//  Created by Bryce Cogswell on 10/12/26.
//  Copyright © 2026 Bryce Cogswell. All rights reserved.
//

import SwiftUI
import UIKit

extension PresetsDatabase {
	/// The feature describing the member roles of a relation with the given tags, if there is one.
	func relationFeature(forTags tags: [String: String],
	                     geometry: GEOMETRY,
	                     location: RegionInfoForLocation) -> PresetFeature?
	{
		if let feature = presetFeatureMatching(tags: tags, geometry: geometry, location: location, includeNSI: false),
		   feature.relation != nil
		{
			return feature
		}
		// A multipolygon tagged as a forest matches the forest feature,
		// which doesn't know about roles, so fall back to the relation type.
		if let type = tags["type"],
		   let feature = presetFeatureForFeatureID("type/\(type)"),
		   feature.relation != nil
		{
			return feature
		}
		return nil
	}
}

extension PresetRelationMemberRole {
	/// Whether an object has the geometry and tags expected for this role
	func accepts(_ object: OsmBaseObject) -> Bool {
		if !geometry.isEmpty, !geometry.contains(object.geometry()) {
			return false
		}
		guard let matchTags else {
			return true
		}
		return matchTags.contains(where: { dict in
			dict.allSatisfy { key, value in
				guard let v = object.tags[key] else { return false }
				return value == "*" || value == v
			}
		})
	}
}

private func localizedRoleLabel(_ role: String, feature: PresetFeature?) -> String {
	if let label = feature?.localizedRelationRoleLabel(for: role) {
		return label
	}
	return role.isEmpty
		? NSLocalizedString("No role", comment: "A relation member that doesn't have a role assigned")
		: role
}

/// The members of a relation that share a role
struct RelationRoleGroup: Identifiable {
	struct Member: Identifiable {
		let id: Int // index of the member in the relation
		let object: OsmBaseObject
		let isExpected: Bool // geometry and tags are appropriate for the role
	}

	let role: String // the OSM role, which may be empty
	let label: String // localized name of the role
	let members: [Member] // downloaded members only
	let missingCount: Int // members that aren't downloaded
	let warning: String?

	var id: String { role }

	/// Roles defined by the feature are listed first, in the order the feature defines them, and
	/// are present even when the relation has no members with that role. Any other roles follow.
	static func groups(for relation: OsmRelation, feature: PresetFeature?) -> [RelationRoleGroup] {
		let presetRoles = feature?.relation?.memberRoles ?? []
		var roles = presetRoles.map { $0.role }
		var members: [String: [Member]] = [:]
		var missing: [String: Int] = [:]

		for (index, member) in relation.members.enumerated() {
			let role = member.role ?? ""
			if !roles.contains(role) {
				roles.append(role)
			}
			if let object = member.obj {
				let presetRole = presetRoles.first(where: { $0.role == role })
				members[role, default: []].append(Member(id: index,
				                                         object: object,
				                                         isExpected: presetRole?.accepts(object) ?? true))
			} else {
				missing[role, default: 0] += 1
			}
		}

		return roles.map { role in
			let presetRole = presetRoles.first(where: { $0.role == role })
			let count = (members[role]?.count ?? 0) + (missing[role] ?? 0)
			var warning: String?
			if let min = presetRole?.minCount, count < min {
				warning = NSLocalizedString("Required",
				                            comment: "A relation doesn't have a member with a required role")
			} else if let max = presetRole?.maxCount, count > max {
				warning = String.localizedStringWithFormat(
					NSLocalizedString("At most %d",
					                  comment: "A relation has more members with a role than are allowed"),
					max)
			}
			return RelationRoleGroup(role: role,
			                         label: localizedRoleLabel(role, feature: feature),
			                         members: members[role] ?? [],
			                         missingCount: missing[role] ?? 0,
			                         warning: warning)
		}
	}
}

/// A relation that an object belongs to, along with its role in that relation
struct RelationMembership: Identifiable {
	let id: Int
	let relation: OsmRelation
	let roleLabel: String

	static func memberships(of object: OsmBaseObject,
	                        in relations: [OsmRelation],
	                        location: RegionInfoForLocation) -> [RelationMembership]
	{
		var list: [RelationMembership] = []
		for relation in relations {
			let feature = PresetsDatabase.shared.relationFeature(forTags: relation.tags,
			                                                     geometry: relation.geometry(),
			                                                     location: location)
			// an object can be in the same relation more than once
			for member in relation.members where member.obj === object {
				list.append(RelationMembership(id: list.count,
				                               relation: relation,
				                               roleLabel: localizedRoleLabel(member.role ?? "", feature: feature)))
			}
		}
		return list
	}
}

@available(iOS 15.0, *)
struct POIRelationsView: View {
	var groups: [RelationRoleGroup] = []
	var memberships: [RelationMembership] = []
	var onSelect: (OsmBaseObject) -> Void = { _ in }

	var body: some View {
		List {
			ForEach(groups) { group in
				Section(header: header(for: group)) {
					ForEach(group.members) { member in
						row(for: member.object,
						    detail: member.isExpected
						    	? nil
						    	: String(localized: "Unexpected for this role",
						    	         comment: "A relation member has the wrong geometry or tags for its role"),
						    isWarning: !member.isExpected)
					}
					if group.missingCount > 0 {
						Text("\(group.missingCount) not downloaded",
						     comment: "The number of relation members that aren't downloaded")
							.foregroundColor(.secondary)
					} else if group.members.isEmpty {
						Text("None", comment: "A relation has no members with a role")
							.foregroundColor(.secondary)
					}
				}
			}
			if !memberships.isEmpty {
				Section(header: Text("Member of", comment: "Header for the relations an object belongs to")) {
					ForEach(memberships) { membership in
						row(for: membership.relation, detail: membership.roleLabel, isWarning: false)
					}
				}
			}
		}
		.listStyle(.grouped)
	}

	private func header(for group: RelationRoleGroup) -> some View {
		HStack {
			Text(verbatim: group.label)
			if group.label != group.role, !group.role.isEmpty {
				// experienced mappers know roles by their OSM name
				Text(verbatim: group.role)
					.fontWeight(.regular)
			}
			Spacer()
			if let warning = group.warning {
				Label(warning, systemImage: "exclamationmark.triangle.fill")
					.foregroundColor(.orange)
			}
		}
		.textCase(nil)
	}

	private func row(for object: OsmBaseObject, detail: String?, isWarning: Bool) -> some View {
		Button(action: { onSelect(object) }, label: {
			HStack {
				VStack(alignment: .leading, spacing: 2) {
					Text(verbatim: object.friendlyDescriptionWithDetails())
						.foregroundColor(.primary)
					if let detail {
						Text(verbatim: detail)
							.font(.footnote)
							.foregroundColor(isWarning ? .orange : .secondary)
					}
				}
				Spacer()
				Image(systemName: "chevron.right")
					.font(.footnote.weight(.semibold))
					.foregroundColor(Color(uiColor: .tertiaryLabel))
			}
		})
	}
}

/// Shows the members of a relation grouped by role, and the relations the selected object belongs to.
@available(iOS 15.0, *)
class POIRelationsViewController: UIHostingController<POIRelationsView> {
	convenience init() {
		self.init(rootView: POIRelationsView())
		navigationItem.title = NSLocalizedString("Relations",
		                                         comment: "Title of the page listing relation members")
		navigationItem.leftBarButtonItem = UIBarButtonItem(barButtonSystemItem: .cancel,
		                                                   target: self,
		                                                   action: #selector(cancel(_:)))
		navigationItem.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .done,
		                                                    target: self,
		                                                    action: #selector(done(_:)))
	}

	override func viewWillAppear(_ animated: Bool) {
		super.viewWillAppear(animated)

		guard let tabController = tabBarController as? POITabBarController,
		      let object = tabController.selection
		else {
			return
		}
		navigationItem.rightBarButtonItem?.isEnabled = tabController.isTagDictChanged()

		// The tags may have been edited in another tab, which can change the roles we show
		let location = AppDelegate.shared.mainView.currentRegion
		var groups: [RelationRoleGroup] = []
		if let relation = object.isRelation() {
			let feature = PresetsDatabase.shared.relationFeature(forTags: tabController.keyValueDict,
			                                                     geometry: relation.geometry(),
			                                                     location: location)
			groups = RelationRoleGroup.groups(for: relation, feature: feature)
		}
		rootView = POIRelationsView(
			groups: groups,
			memberships: RelationMembership.memberships(of: object,
			                                            in: tabController.relationList,
			                                            location: location),
			onSelect: { [weak tabController] object in
				guard let tabController else { return }
				tabController.switchSelection(to: object, currentTags: tabController.keyValueDict)
			})
	}

	@objc func cancel(_ sender: Any?) {
		dismiss(animated: true)
	}

	@objc func done(_ sender: Any?) {
		dismiss(animated: true)
		(tabBarController as? POITabBarController)?.commitChanges()
	}
}
