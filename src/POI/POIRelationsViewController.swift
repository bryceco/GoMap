//
//  POIRelationsViewController.swift
//  Go Map!!
//
//  Created by Bryce Cogswell on 10/12/26.
//  Copyright © 2026 Bryce Cogswell. All rights reserved.
//

import SwiftUI
import UIKit

func localizedRoleLabel(_ role: String, feature: PresetFeature?) -> String {
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
		let member: OsmMember
		let isExpected: Bool // geometry and tags are appropriate for the role

		var object: OsmBaseObject? { member.obj } // nil if not downloaded
		var identifier: String { "\(member.type.string) \(member.ref)" } // "way 123"
		var name: String? { member.obj?.friendlyDescription() }
	}

	let role: String // the OSM role, which may be empty
	let label: String // localized name of the role
	let members: [Member] // in the order they appear in the relation
	let warning: String?

	var id: String { role }

	/// Roles defined by the feature are listed first, in the order the feature defines them, and
	/// are present even when the relation has no members with that role. Any other roles follow.
	static func groups(for relation: OsmRelation, feature: PresetFeature?) -> [RelationRoleGroup] {
		let presetRoles = feature?.relation?.memberRoles ?? []
		var roles = presetRoles.map { $0.role }
		var members: [String: [Member]] = [:]

		for (index, member) in relation.members.enumerated() {
			let role = member.role ?? ""
			if !roles.contains(role) {
				roles.append(role)
			}
			// we can only check members that are downloaded
			var isExpected = true
			if let object = member.obj,
			   let presetRole = presetRoles.first(where: { $0.role == role })
			{
				isExpected = presetRole.accepts(object)
			}
			members[role, default: []].append(Member(id: index, member: member, isExpected: isExpected))
		}

		return roles.map { role in
			let presetRole = presetRoles.first(where: { $0.role == role })
			let count = members[role]?.count ?? 0
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
			let feature = PresetsDatabase.shared.presetFeatureMatching(tags: relation.tags,
			                                                           geometry: .RELATION,
			                                                           location: location,
			                                                           includeNSI: false)
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
	var featureType: String? // localized name of the selected object's feature
	var name: String? // name of the selected object
	var groups: [RelationRoleGroup] = []
	var memberships: [RelationMembership] = []
	var onSelect: (OsmBaseObject) -> Void = { _ in }
	var onDownload: (() async -> Void)? // nil if all members are downloaded
	@State private var isDownloading = false
	@State private var collapsedGroups: Set<String>?

	var body: some View {
		List {
			// identify the selected object the same way Common Tags does
			if featureType != nil || name != nil {
				Section {
					if let featureType {
						infoRow(NSLocalizedString("Type", comment: "The 'Type' header in Common Tags"), featureType)
					}
					if let name {
						infoRow(PresetsDatabase.shared.presetFields["name"]?.localizedLabel ?? "Name", name)
					}
				}
			}
			ForEach(groups) { group in
				Section {
					if !(collapsedGroups ?? []).contains(group.id) {
						ForEach(group.members) { member in
							row(title: memberTitle(member),
							    object: member.object,
							    detail: member.isExpected
							    	? nil
							    	: String(localized: "Unexpected for this role",
							    	         comment: "A relation member has the wrong geometry or tags for its role"),
							    isWarning: !member.isExpected)
						}
						if group.members.isEmpty {
							Text("None", comment: "A relation has no members with a role")
								.foregroundColor(.secondary)
						}
					}
				} header: {
					header(for: group)
				} footer: {
					if !(collapsedGroups ?? []).contains(group.id),
					   group.id == groups.last?.id, onDownload != nil
					{
						// same text as All Tags
						Text(NSLocalizedString(
							"You can navigate to a relation member only if it is already downloaded.\nThese members are marked with '>'.",
							comment: ""))
					}
				}
			}
			if let onDownload {
				Section {
					Button(action: {
						isDownloading = true
						Task {
							await onDownload()
							isDownloading = false
						}
					}, label: {
						HStack {
							Text("Download all members", comment: "Button to download the members of a relation")
							Spacer()
							if isDownloading {
								ProgressView()
							}
						}
					})
					.disabled(isDownloading)
				}
			}
			if !memberships.isEmpty {
				Section(header: Text("Member of", comment: "Header for the relations an object belongs to")) {
					ForEach(memberships) { membership in
						row(title: Text(verbatim: membership.relation.friendlyDescriptionWithDetails()),
						    object: membership.relation,
						    detail: membership.roleLabel,
						    isWarning: false)
					}
				}
			}
		}
		.listStyle(.grouped)
		.onAppear {
			if collapsedGroups == nil {
				collapsedGroups = Set(groups.filter { $0.members.count >= 5 }.map(\.id))
			}
		}
	}

	private func infoRow(_ label: String, _ value: String) -> some View {
		HStack {
			Text(verbatim: label)
				.foregroundColor(.secondary)
			Spacer()
			Text(verbatim: value)
				.multilineTextAlignment(.trailing)
		}
	}

	private func header(for group: RelationRoleGroup) -> some View {
		Button(action: {
			withAnimation {
				if collapsedGroups?.contains(group.id) == true {
					collapsedGroups?.remove(group.id)
				} else {
					collapsedGroups = (collapsedGroups ?? []).union([group.id])
				}
			}
		}) {
			HStack {
				Image(systemName: collapsedGroups?.contains(group.id) == true ? "chevron.right" : "chevron.down")
					.font(.footnote.weight(.semibold))
					.foregroundColor(.secondary)
				Text(verbatim: group.label)
				Text(verbatim: "(\(group.members.count))")
					.fontWeight(.regular)
				Spacer()
				if let warning = group.warning {
					Label(warning, systemImage: "exclamationmark.triangle.fill")
						.foregroundColor(.orange)
				}
			}
			.textCase(nil)
		}
	}

	/// A member's identifier, such as "way 123", followed by its name if it's downloaded
	private func memberTitle(_ member: RelationRoleGroup.Member) -> Text {
		let identifier = Text(verbatim: member.identifier)
		guard let name = member.name else {
			return identifier
		}
		return identifier + Text(verbatim: "  " + name).foregroundColor(.secondary)
	}

	/// A row for an object we can navigate to, or one that isn't downloaded if object is nil
	private func row(title: Text, object: OsmBaseObject?, detail: String?, isWarning: Bool) -> some View {
		Button(action: { if let object { onSelect(object) } }, label: {
			HStack {
				VStack(alignment: .leading, spacing: 2) {
					title
						.foregroundColor(object == nil ? .secondary : .primary)
						.multilineTextAlignment(.leading)
					if let detail {
						Text(verbatim: detail)
							.font(.footnote)
							.foregroundColor(isWarning ? .orange : .secondary)
					}
				}
				Spacer()
				if object != nil {
					Image(systemName: "chevron.right")
						.font(.footnote.weight(.semibold))
						.foregroundColor(Color(uiColor: .tertiaryLabel))
				}
			}
		})
		.disabled(object == nil)
	}
}

/// Shows the members of a relation grouped by role, and the relations the selected object belongs to.
@available(iOS 15.0, *)
class POIRelationsViewController: UIHostingController<POIRelationsView> {
	convenience init() {
		self.init(rootView: POIRelationsView())
		navigationItem.leftBarButtonItem = UIBarButtonItem(barButtonSystemItem: .cancel,
		                                                   target: self,
		                                                   action: #selector(cancel(_:)))
		navigationItem.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .done,
		                                                    target: self,
		                                                    action: #selector(done(_:)))
	}

	override func viewWillAppear(_ animated: Bool) {
		super.viewWillAppear(animated)
		refresh()
	}

	private func refresh() {
		guard let tabController = tabBarController as? POITabBarController,
		      let object = tabController.selection
		else {
			return
		}
		navigationItem.rightBarButtonItem?.isEnabled = tabController.isTagDictChanged()

		// The tags may have been edited in another tab, which can change the feature and its roles
		let tags = tabController.keyValueDict
		let location = AppDelegate.shared.mainView.currentRegion
		// For a relation we want the relation type, such as Multipolygon, which also defines the roles.
		// A multipolygon has area geometry and would otherwise match a feature like Forest.
		let relation = object.isRelation()
		let feature = PresetsDatabase.shared.presetFeatureMatching(
			tags: tags,
			geometry: relation != nil ? .RELATION : object.geometry(),
			location: location,
			includeNSI: false)
		// Only relations have members. Other objects just list the relations they belong to.
		var groups: [RelationRoleGroup] = []
		var onDownload: (() async -> Void)?
		if let relation {
			groups = RelationRoleGroup.groups(for: relation, feature: feature)
			if relation.members.contains(where: { $0.obj == nil }) {
				onDownload = { [weak self] in await self?.downloadMembers(of: relation) }
			}
			navigationItem.title = NSLocalizedString("Relation Members",
			                                         comment: "Title of the page listing the members of a relation")
		} else {
			navigationItem.title = NSLocalizedString(
				"Relation Member",
				comment: "Title of the page listing the relations an object is a member of")
		}
		rootView = POIRelationsView(
			featureType: feature?.localizedName,
			name: tags["name"],
			groups: groups,
			memberships: RelationMembership.memberships(of: object,
			                                            in: tabController.relationList,
			                                            location: location),
			onSelect: { [weak tabController] object in
				guard let tabController else { return }
				tabController.switchSelection(to: object, currentTags: tabController.keyValueDict)
			},
			onDownload: onDownload)
	}

	private func downloadMembers(of relation: OsmRelation) async {
		let mapView = AppDelegate.shared.mapView!
		do {
			try await mapView.mapData.downloadMembers(of: relation)
		} catch {
			let alert = UIAlertController(title: NSLocalizedString("Error", comment: ""),
			                              message: error.localizedDescription,
			                              preferredStyle: .alert)
			alert.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: ""), style: .cancel, handler: nil))
			present(alert, animated: true)
		}
		mapView.setNeedsLayout() // draw the new objects
		refresh()
	}

	@objc func cancel(_ sender: Any?) {
		dismiss(animated: true)
	}

	@objc func done(_ sender: Any?) {
		dismiss(animated: true)
		(tabBarController as? POITabBarController)?.commitChanges()
	}
}
