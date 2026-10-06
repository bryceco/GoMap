//
//  AdvancedQuestBuilderFilterRow.swift
//  Go Map!!
//
//  Created by Bryce Cogswell on 2/19/23.
//  Copyright © 2023 Bryce Cogswell. All rights reserved.
//

import SwiftUI

/// A display-ready row produced by flattening a `QuestFilterGroup` tree for a List.
struct AdvancedQuestFilterRow: Identifiable {
	enum Kind {
		/// The AND/OR header that starts each group. It also hosts the "+" menu for adding to the group
		/// and shows a warning if the group's conditions are contradictory or vacuous.
		case groupHeader(groupID: UUID, op: QuestFilterOperator, problem: QuestFilterGroup.Problem?)
		case condition(QuestFilterCondition)
	}

	let kind: Kind
	/// Indentation level. The root header is at depth 0 and its children at depth 1.
	let depth: Int

	var id: String {
		switch kind {
		case let .groupHeader(groupID, _, _): return "group-\(groupID)"
		case let .condition(condition): return "condition-\(condition.id)"
		}
	}

	/// The tree node removed when the user swipes to delete this row, or nil if the row can't be deleted.
	var deletableNodeID: UUID? {
		switch kind {
		case let .groupHeader(groupID, _, _):
			// Deleting a group's header deletes the whole group, but the root group is permanent.
			return depth == 0 ? nil : groupID
		case let .condition(condition):
			return condition.id
		}
	}
}

extension QuestFilterGroup {
	/// Flattens the tree into rows: each group contributes an AND/OR header row followed by
	/// its children indented one level deeper.
	func displayRows() -> [AdvancedQuestFilterRow] {
		var rows: [AdvancedQuestFilterRow] = []
		appendDisplayRows(to: &rows, depth: 0)
		return rows
	}

	private func appendDisplayRows(to rows: inout [AdvancedQuestFilterRow], depth: Int) {
		rows.append(AdvancedQuestFilterRow(kind: .groupHeader(groupID: id, op: op, problem: problem),
		                                   depth: depth))
		for child in children {
			switch child {
			case let .condition(condition):
				rows.append(AdvancedQuestFilterRow(kind: .condition(condition), depth: depth + 1))
			case let .group(group):
				group.appendDisplayRows(to: &rows, depth: depth + 1)
			}
		}
	}
}

/// Which field in a condition row should have keyboard focus.
enum AdvancedQuestFilterFocus: Hashable {
	case key(UUID)
	case value(UUID)
}

/// Width of one indentation level.
private let indentWidth: CGFloat = 28

/// Horizontal list row inset, matching the List default so only the vertical spacing is tightened.
private let rowHorizontalInset: CGFloat = 20

private func compactRowInsets(top: CGFloat, bottom: CGFloat) -> EdgeInsets {
	return EdgeInsets(top: top, leading: rowHorizontalInset, bottom: bottom, trailing: rowHorizontalInset)
}

/// Horizontal position of a group's guide line within its indentation gutter, under the AND/OR chip.
private let guideLineOffset: CGFloat = 12

/// Leading indentation for a row.
private struct AdvancedQuestFilterIndent: View {
	let depth: Int

	var body: some View {
		Spacer(minLength: 0)
			.frame(width: CGFloat(depth) * indentWidth)
	}
}

/// Row background that draws a thin vertical line for each group enclosing the row, so the
/// extent of every group is visible down its left edge. Drawn as the row background so the lines
/// span the full row height and join up between rows.
private struct AdvancedQuestFilterGuideLines: View {
	let depth: Int

	var body: some View {
		ZStack(alignment: .topLeading) {
			Color(UIColor.secondarySystemGroupedBackground)
			ForEach(0..<depth, id: \.self) { level in
				Rectangle()
					.fill(Color(UIColor.separator))
					.frame(width: 1)
					.padding(.leading, rowHorizontalInset + CGFloat(level) * indentWidth + guideLineOffset)
			}
		}
	}
}

/// The row that starts a group: an AND/OR chip that opens a menu to choose the group's operator,
/// followed by a "+" menu for adding a condition or a nested group to it.
@available(iOS 15.0.0, *)
struct AdvancedQuestFilterGroupHeaderView: View {
	let depth: Int
	let op: QuestFilterOperator
	var problem: QuestFilterGroup.Problem? = nil
	let onSetOperator: (QuestFilterOperator) -> Void
	let onAddCondition: (QuestFilterCondition.Operator) -> Void
	let onAddGroup: () -> Void

	var body: some View {
		HStack {
			AdvancedQuestFilterIndent(depth: depth)
			Menu {
				// A Picker inside a Menu renders as a native selection list, with aligned titles
				// and the system checkmark on the selected item
				Picker("", selection: Binding(get: { op }, set: { onSetOperator($0) })) {
					ForEach(QuestFilterOperator.allCases, id: \.self) { choice in
						Text(choice.localizedTitle).tag(choice)
					}
				}
				.pickerStyle(.inline)
			} label: {
				Text(op.localizedTitle)
					.font(.caption.weight(.bold))
			}
			.buttonStyle(.bordered)
			.controlSize(.small)

			Menu {
				Button(action: { onAddCondition(.equals) }) {
					Text("Key = value", comment: "Menu item adding a quest filter condition")
				}
				Button(action: { onAddCondition(.notEquals) }) {
					Text("Key ≠ value", comment: "Menu item adding a quest filter condition")
				}
				Button(action: { onAddCondition(.exists) }) {
					Text("Key exists", comment: "Menu item adding a quest filter condition")
				}
				Button(action: { onAddCondition(.missing) }) {
					Text("Key missing", comment: "Menu item adding a quest filter condition")
				}
				Button(action: { onAddGroup() }) {
					Text("AND/OR group", comment: "Menu item adding a nested AND/OR group to a quest filter")
				}
			} label: {
				Label("", systemImage: "plus")
			}

			// Warn when the group's conditions can never (AND) or always (OR) be satisfied
			if let problem = problem {
				Label(problem.localizedDescription, systemImage: "exclamationmark.triangle.fill")
					.font(.caption)
					.foregroundColor(.orange)
					.padding(.leading, 4)
			}
			Spacer()
		}
		.listRowInsets(compactRowInsets(top: 4, bottom: 0))
		.listRowBackground(AdvancedQuestFilterGuideLines(depth: depth))
	}
}

/// A single condition: key, operator menu, and a value field when the operator needs one.
@available(iOS 15.0.0, *)
struct AdvancedQuestFilterRowView: View {
	@Binding var data: QuestFilterCondition
	var depth: Int = 1
	var focusedField: FocusState<AdvancedQuestFilterFocus?>.Binding

	var body: some View {
		HStack {
			AdvancedQuestFilterIndent(depth: depth)

			// Key textfield
			TextField("", text: $data.key)
				.focused(focusedField, equals: .key(data.id))
				.textFieldStyle(.roundedBorder)
				.autocapitalization(.none)
				.autocorrectionDisabled()
				.keyboardType(.asciiCapable)

			// Operator menu
			Menu {
				Picker("", selection: $data.op) {
					ForEach(QuestFilterCondition.Operator.allCases, id: \.self) { choice in
						Text(choice.localizedTitle).tag(choice)
					}
				}
				.pickerStyle(.inline)
			} label: {
				Text(data.op.localizedTitle)
			}

			if data.op.takesValue {
				// Value textfield
				TextField("", text: $data.value)
					.focused(focusedField, equals: .value(data.id))
					.textFieldStyle(RoundedBorderTextFieldStyle())
					.autocapitalization(.none)
					.autocorrectionDisabled()
					.keyboardType(.asciiCapable)
			} else {
				// Keep the key field the same width as in rows that have a value
				Spacer()
			}
		}
		.listRowInsets(compactRowInsets(top: 3, bottom: 3))
		.listRowBackground(AdvancedQuestFilterGuideLines(depth: depth))
		.onChange(of: data.op) { newOp in
			if newOp.takesValue {
				focusedField.wrappedValue = .value(data.id)
			}
		}
	}
}

@available(iOS 15.0, *)
struct AdvancedQuestBuilderFilterRow_Previews: PreviewProvider {
	struct Preview: View {
		@State var equals = QuestFilterCondition(key: "highway", op: .equals, value: "path")
		@State var missing = QuestFilterCondition(key: "lit", op: .missing)
		@FocusState var focusedField: AdvancedQuestFilterFocus?
		var body: some View {
			List {
				AdvancedQuestFilterGroupHeaderView(depth: 0, op: .and,
				                                   onSetOperator: { _ in }, onAddCondition: { _ in }, onAddGroup: {})
				AdvancedQuestFilterRowView(data: $missing, depth: 1, focusedField: $focusedField)
				AdvancedQuestFilterGroupHeaderView(depth: 1, op: .or, problem: .alwaysMatches,
				                                   onSetOperator: { _ in }, onAddCondition: { _ in }, onAddGroup: {})
				AdvancedQuestFilterRowView(data: $equals, depth: 2, focusedField: $focusedField)
			}
		}
	}

	static var previews: some View {
		Preview()
	}
}
