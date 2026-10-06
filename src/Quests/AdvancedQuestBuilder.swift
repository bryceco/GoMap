//
//  AdvancedQuestBuilder.swift
//  Go Map!!
//
//  Created by Bryce Cogswell on 2/19/23.
//  Copyright © 2023 Bryce Cogswell. All rights reserved.
//

import SwiftUI

@available(iOS 15.0.0, *)
extension Button {
	@ViewBuilder
	func toggleButtonStyle(enabled: Bool) -> some View {
		if enabled {
			buttonStyle(BorderedProminentButtonStyle())
		} else {
			buttonStyle(BorderedButtonStyle())
		}
	}
}

@available(iOS 15.0.0, *)
struct AdvancedQuestBuilder: View {
	@Environment(\.presentationMode) var presentationMode: Binding<PresentationMode>
	var onSave: ((QuestDefinitionWithFilters) -> Bool)?
	@State var quest: QuestDefinitionWithFilters
	@FocusState private var focusedField: AdvancedQuestFilterFocus?
	@FocusState private var focusedKeyIndex: Int?

	init(quest: QuestDefinitionWithFilters) {
		_quest = State(initialValue: quest)
	}

	var body: some View {
		List {
			Section(
				header: sectionHeader(
					Text("Name"),
					Text(String(localized:
						"What is the name of this quest? This is best written in the form of an action like 'Add Cuisine':",
						comment: "'Add Cuisine' should match the use this sample text elsewhere in the app"))),
				content: {
					TextField("Add Cuisine", text: $quest.title)
						.textInputAutocapitalization(.words)
				})

			Section(
				header: sectionHeader(
					Text("Icon"),
					Text("Provide a single-character symbol (emoji or unicode character) to identify this quest:")),
				content: {
					TextField("", text: $quest.label)
						.background(
							// An emoji placeholder can't be grayed like normal placeholder text, so fade it instead
							Text(verbatim: "🍽️")
								.opacity(quest.label.isEmpty ? 0.3 : 0.0)
								.accessibilityHidden(true),
							alignment: .leading)
				})

			Section(
				header: sectionHeader(
					Text("Keys", comment: "The tag keys section of a quest definition"),
					Text("What tag key is modified by this quest?")),
				content: {
					ForEach(quest.editKeys.indices, id: \.self) { index in
						HStack {
							TextField("", text: $quest.editKeys[index], prompt: Text(verbatim: "cuisine"))
								.autocapitalization(.none)
								.autocorrectionDisabled()
								.keyboardType(.asciiCapable)
								.focused($focusedKeyIndex, equals: index)
							if index == quest.editKeys.count - 1 {
								// Most quests have a single key, so adding another is a small button on the last row
								Button(action: addKey) {
									Image(systemName: "plus")
								}
								.buttonStyle(.borderless)
								.disabled(isBlank(quest.editKeys[index]))
							}
						}
						.deleteDisabled(quest.editKeys.count <= 1)
					}
					.onDelete { indexSet in
						quest.editKeys.remove(atOffsets: indexSet)
					}
					.onMove { indexSet, index in
						quest.editKeys.move(fromOffsets: indexSet, toOffset: index)
					}
				})

			Section(
				header: sectionHeader(
					HStack {
						Text("Filter", comment: "Header for quest filter section")
						Spacer()
						Button("Clear All") {
							clearAll()
						}
						.font(.subheadline)
						.textCase(nil)
					},
					Text(
						"Add a row for each condition an object must match. Tap AND/OR to change how a group's rows combine, and + to add a condition or nested group of conditions.")),
				content: {
					ForEach(quest.filterTree.displayRows()) { row in
						switch row.kind {
						case let .groupHeader(groupID, op, problem):
							AdvancedQuestFilterGroupHeaderView(
								depth: row.depth,
								op: op,
								problem: problem,
								onSetOperator: { quest.filterTree.setOperator($0, forGroupWithID: groupID) },
								onAddCondition: { addCondition($0, toGroupWithID: groupID) },
								onAddGroup: { addGroup(toGroupWithID: groupID) })
								.deleteDisabled(row.deletableNodeID == nil)
						case let .condition(condition):
							AdvancedQuestFilterRowView(data: binding(for: condition), depth: row.depth,
							                           focusedField: $focusedField)
						}
					}
					.onDelete { indexSet in
						// Deleting a group header deletes the whole group
						let rows = quest.filterTree.displayRows()
						for nodeID in indexSet.compactMap({ rows[$0].deletableNodeID }) {
							quest.filterTree.removeNode(withID: nodeID)
						}
					}
					.listRowSeparator(.hidden)

					// The boolean expression the tree above resolves to
					if !quest.filterTree.children.isEmpty {
						Text(quest.filterTree.expressionText)
							.font(.footnote)
							.foregroundColor(.secondary)
							.textSelection(.enabled)
							.listRowSeparator(.hidden)
							.listRowInsets(EdgeInsets(top: 10, leading: 20, bottom: 8, trailing: 20))
					}
				})

			Section(
				header: sectionHeader(
					Text("Geometry"),
					Text("What types of objects does this quest apply to?")),
				content: {
					HStack {
						Button(action: { quest.geometry.point.toggle() }) {
							Text("Point", comment: "Object geometry: a node")
						}
						.toggleButtonStyle(enabled: quest.geometry.point)

						Button(action: { quest.geometry.line.toggle() }) {
							Text("Line", comment: "Object geometry: a way (but not an area)")
						}
						.toggleButtonStyle(enabled: quest.geometry.line)

						Button(action: {
							quest.geometry.area.toggle()
						}) {
							Text("Area", comment: "Object geometry: a closed way or multipolygon)")
						}
						.toggleButtonStyle(enabled: quest.geometry.area)

						Button(action: {
							quest.geometry.vertex.toggle()
						}) {
							Text("Vertex", comment: "Object geometry: a node that is part of a way")
						}
						.toggleButtonStyle(enabled: quest.geometry.vertex)
					}
					.listRowSeparator(.hidden)
				})
		}
		// Let the small AND/OR rows in the filter tree be shorter than a standard row
		.environment(\.defaultMinListRowHeight, 30)
		.navigationBarTitleDisplayMode(.inline)
		.toolbar {
			ToolbarItem(placement: .principal) {
				// Shrink rather than truncate between the Cancel and Save buttons
				Text("Advanced Quest Builder")
					.font(.headline)
					.lineLimit(1)
					.minimumScaleFactor(0.6)
			}
		}
		.navigationBarBackButtonHidden()
		.navigationBarItems(
			leading: Button(action: {
				presentationMode.wrappedValue.dismiss()
			}) {
				Text("Cancel").font(.body)
			},
			trailing: Button(action: {
				// Dismiss keyboard before saving
				UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder),
				                                to: nil, from: nil, for: nil)
				// Do some cleanup before saving
				quest.filterTree.trimWhitespace()
				quest.title = quest.title.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
				quest.label = quest.label.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
				quest.editKeys = quest.editKeys.compactMap {
					let s = $0.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
					return s.isEmpty ? nil : s
				}

				if let onSave = onSave,
				   onSave(quest)
				{
					presentationMode.wrappedValue.dismiss()
				}
			}) {
				Text("Save").font(.body).bold()
			}
			.disabled(!isComplete))
	}

	/// A section title with its explanatory text underneath, so the explanation precedes the fields it describes.
	private func sectionHeader<Title: View>(_ title: Title, _ help: Text) -> some View {
		VStack(alignment: .leading, spacing: 4) {
			title
			help
				.font(.footnote)
				.fontWeight(.regular)
				.textCase(nil)
		}
	}

	/// A binding to a condition inside the tree, looked up by id so edits land in the right node.
	private func binding(for condition: QuestFilterCondition) -> Binding<QuestFilterCondition> {
		return Binding(
			get: { quest.filterTree.condition(withID: condition.id) ?? condition },
			set: { quest.filterTree.replaceCondition($0) })
	}

	func addCondition(_ op: QuestFilterCondition.Operator, toGroupWithID groupID: UUID) {
		let condition = QuestFilterCondition(key: "", op: op)
		quest.filterTree.append(.condition(condition), toGroupWithID: groupID)
		focusedField = .key(condition.id)
	}

	func addGroup(toGroupWithID groupID: UUID) {
		// A nested group defaults to the opposite operator of its parent, since that's the only useful choice.
		let parentOp = quest.filterTree.group(withID: groupID)?.op ?? .and
		let childCondition = QuestFilterCondition(key: "", op: .equals)
		let group = QuestFilterGroup(op: parentOp.toggled, children: [.condition(childCondition)])
		quest.filterTree.append(.group(group), toGroupWithID: groupID)
		focusedField = .key(childCondition.id)
	}

	func clearAll() {
		let condition = QuestFilterCondition(key: "", op: .equals)
		quest.filterTree = QuestFilterGroup(op: .and, children: [.condition(condition)])
		focusedField = .key(condition.id)
	}

	func addKey() {
		quest.editKeys.append("")
		focusedKeyIndex = quest.editKeys.count - 1
	}

	private func isBlank(_ text: String) -> Bool {
		return text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
	}

	/// True when every field has been filled in, so the quest can be saved.
	private var isComplete: Bool {
		return !isBlank(quest.title)
			&& !isBlank(quest.label)
			&& !quest.editKeys.isEmpty
			&& !quest.editKeys.contains(where: isBlank)
			&& !quest.filterTree.allConditions.isEmpty
			&& !quest.filterTree.allConditions.contains {
				isBlank($0.key) || ($0.op.takesValue && isBlank($0.value))
			}
	}
}

@available(iOS 15.0.0, *)
struct AdvancedQuestBuilder_Previews: PreviewProvider {
	// lit missing AND (highway=residential OR (highway=path AND foot=designated))
	static let quest = QuestDefinitionWithFilters(
		title: "Add Lit",
		label: "💡",
		editKeys: ["lit"],
		filterTree: QuestFilterGroup(op: .and, children: [
			.condition(QuestFilterCondition(key: "lit", op: .missing)),
			.group(QuestFilterGroup(op: .or, children: [
				.condition(QuestFilterCondition(key: "highway", op: .equals, value: "residential")),
				.group(QuestFilterGroup(op: .and, children: [
					.condition(QuestFilterCondition(key: "highway", op: .equals, value: "path")),
					.condition(QuestFilterCondition(key: "foot", op: .equals, value: "designated"))
				]))
			]))
		]),
		geometry: QuestDefinitionWithFilters.Geometries())

	static var previews: some View {
		NavigationView {
			AdvancedQuestBuilder(quest: quest)
		}
	}
}
