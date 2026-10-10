//
//  TagMergeView.swift
//  Go Map!!
//
//  A sheet that lets the user resolve differences between two sets of tags,
//  either tag-by-tag or with Merge All / Replace All.
//

import SwiftUI
import UIKit

/// How the user arrived at the sheet.
enum TagMergeSource {
	case paste
	case nodeDrag

	/// A node drag has already happened, so it can't be cancelled from here.
	var allowsCancel: Bool { self == .paste }

	var subtitleFormat: String {
		switch self {
		case .paste:
			return NSLocalizedString("Pasting onto %@", comment: "Merge Tags subtitle, %@ is an object name")
		case .nodeDrag:
			return NSLocalizedString("Dragged node joining %@", comment: "Merge Tags subtitle, %@ is an object name")
		}
	}

	var currentHeader: String {
		switch self {
		case .paste: return NSLocalizedString("On object", comment: "Column header: tags currently on the object")
		case .nodeDrag: return NSLocalizedString("Target node", comment: "Column header: tags on the node dragged onto")
		}
	}

	var incomingHeader: String {
		switch self {
		case .paste: return NSLocalizedString("Clipboard", comment: "Column header: tags being pasted")
		case .nodeDrag: return NSLocalizedString("Dragged node", comment: "Column header: tags on the node being dragged")
		}
	}
}

final class TagMergeModel: ObservableObject {
	enum Side {
		case current
		case incoming
	}

	enum Status {
		case kept
		case changed
		case added
		case notAdded
		case removed

		var isChange: Bool { self == .changed || self == .added || self == .removed }
	}

	/// A key whose value differs between the two tag sets.
	struct Row: Identifiable {
		let key: String
		let current: String?
		let incoming: String?
		var id: String { key }
	}

	let current: [String: String]
	let incoming: [String: String]
	/// Differing keys: conflicts first, then incoming-only, then current-only.
	let rows: [Row]
	/// Keys with the same value on both sides. These are never touched.
	let identicalKeys: [String]

	@Published var choice: [String: Side]

	init(current: [String: String], incoming: [String: String]) {
		var conflicts: [Row] = []
		var incomingOnly: [Row] = []
		var currentOnly: [Row] = []
		var identical: [String] = []
		for key in Set(current.keys).union(incoming.keys).sorted() {
			let row = Row(key: key, current: current[key], incoming: incoming[key])
			if row.current == row.incoming {
				identical.append(key)
			} else if row.current == nil {
				incomingOnly.append(row)
			} else if row.incoming == nil {
				currentOnly.append(row)
			} else {
				conflicts.append(row)
			}
		}
		let rows = conflicts + incomingOnly + currentOnly
		self.current = current
		self.incoming = incoming
		self.rows = rows
		self.identicalKeys = identical
		self.choice = TagMergeModel.mergeChoice(for: rows)
	}

	/// Merge takes the incoming value wherever there is one.
	private static func mergeChoice(for rows: [Row]) -> [String: Side] {
		var choice: [String: Side] = [:]
		for row in rows {
			choice[row.key] = row.incoming != nil ? .incoming : .current
		}
		return choice
	}

	// MARK: Results

	/// Incoming tags win, tags only on the current object are retained.
	var mergedTags: [String: String] {
		current.merging(incoming) { _, new in new }
	}

	/// All current tags are discarded.
	var replacedTags: [String: String] {
		incoming
	}

	/// The result of the user's per-tag choices.
	var selectedTags: [String: String] {
		var result = current
		for row in rows {
			let value = choice[row.key] == .incoming ? row.incoming : row.current
			result[row.key] = value // nil removes the key
		}
		return result
	}

	// MARK: State

	/// Nothing differs, so the caller should show a "no change" toast instead of the sheet.
	var isNoOp: Bool { rows.isEmpty }

	/// At least one key is present on both sides with different values.
	var hasConflicts: Bool {
		rows.contains { $0.current != nil && $0.incoming != nil }
	}

	var isCustomized: Bool {
		choice != TagMergeModel.mergeChoice(for: rows)
	}

	func reset() {
		choice = TagMergeModel.mergeChoice(for: rows)
	}

	func status(of row: Row) -> Status {
		let useIncoming = choice[row.key] == .incoming
		if row.current == nil {
			return useIncoming ? .added : .notAdded
		}
		if row.incoming == nil {
			return useIncoming ? .removed : .kept
		}
		return useIncoming ? .changed : .kept
	}

	func count(of status: Status) -> Int {
		rows.filter { self.status(of: $0) == status }.count
	}

	var changeCount: Int {
		rows.filter { status(of: $0).isChange }.count
	}
}

struct TagMergeView: View {
	@ObservedObject var model: TagMergeModel
	let source: TagMergeSource
	let objectName: String
	/// Called exactly once with the resulting tags, or nil if the user cancelled.
	let completion: ([String: String]?) -> Void

	var body: some View {
		VStack(spacing: 0) {
			header
			columnHeaders
			ScrollView {
				VStack(spacing: 10) {
					ForEach(model.rows) { row in
						self.rowView(row)
					}
					identicalNote
				}
				.padding(.horizontal, 16)
				.padding(.bottom, 8)
			}
			Divider()
			footer
		}
		.background(Color(UIColor.systemGroupedBackground).edgesIgnoringSafeArea(.all))
	}

	// MARK: Header

	private var header: some View {
		VStack(spacing: 2) {
			ZStack {
				Text(NSLocalizedString("Merge Tags", comment: "Title of the tag merge sheet"))
					.font(.headline)
				HStack {
					if source.allowsCancel {
						Button(action: { self.completion(nil) }) {
							Text(NSLocalizedString("Cancel", comment: ""))
								.frame(minHeight: 44)
						}
					}
					Spacer()
				}
			}
			.frame(minHeight: 44)
			Text(String(format: source.subtitleFormat, objectName))
				.font(.footnote)
				.foregroundColor(.secondary)
		}
		.padding(.horizontal, 16)
		.padding(.top, 8)
		.padding(.bottom, 10)
	}

	private var columnHeaders: some View {
		HStack(spacing: 8) {
			columnHeader(source.currentHeader)
			columnHeader(source.incomingHeader)
		}
		.padding(.horizontal, 16)
		.padding(.bottom, 6)
	}

	private func columnHeader(_ text: String) -> some View {
		Text(text.uppercased())
			.font(.caption)
			.fontWeight(.semibold)
			.foregroundColor(.secondary)
			.frame(maxWidth: .infinity, alignment: .leading)
	}

	// MARK: Rows

	private func rowView(_ row: TagMergeModel.Row) -> some View {
		let status = model.status(of: row)
		return VStack(spacing: 4) {
			HStack(alignment: .firstTextBaseline) {
				Text(row.key)
					.font(.subheadline)
					.fontWeight(.semibold)
				Spacer()
				Text(Self.label(for: status))
					.font(.caption)
					.fontWeight(.semibold)
					.foregroundColor(Self.color(for: status))
			}
			HStack(spacing: 8) {
				valueButton(row, side: .current)
				valueButton(row, side: .incoming)
			}
		}
	}

	private func valueButton(_ row: TagMergeModel.Row, side: TagMergeModel.Side) -> some View {
		let value = side == .current ? row.current : row.incoming
		let placeholder = side == .current
			? NSLocalizedString("Not set", comment: "Tag is not present on the object; choosing this skips the tag")
			: NSLocalizedString("Remove tag", comment: "Tag is not in the incoming tags; choosing this removes it")
		let selected = model.choice[row.key] == side
		let textColor: Color = selected ? .white : (value == nil ? .secondary : .primary)
		let fill = selected ? Color.accentColor : Color(UIColor.secondarySystemGroupedBackground)
		return Button(action: { self.model.choice[row.key] = side }) {
			Text(value ?? placeholder)
				.font(.callout)
				.foregroundColor(textColor)
				.multilineTextAlignment(.leading)
				.padding(.horizontal, 10)
				.padding(.vertical, 6)
				.frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
				.background(RoundedRectangle(cornerRadius: 10).fill(fill))
		}
		.buttonStyle(PlainButtonStyle())
		.accessibility(addTraits: selected ? .isSelected : [])
	}

	private var identicalNote: some View {
		Group {
			if !model.identicalKeys.isEmpty {
				Text(String(format: NSLocalizedString("Identical tags not shown: %@",
				                                      comment: "%@ is a list of tag keys"),
				            model.identicalKeys.joined(separator: ", ")))
					.font(.footnote)
					.foregroundColor(.secondary)
					.frame(maxWidth: .infinity, alignment: .leading)
			}
		}
	}

	private static func label(for status: TagMergeModel.Status) -> String {
		switch status {
		case .kept: return NSLocalizedString("kept", comment: "Tag keeps its current value")
		case .changed: return NSLocalizedString("changed", comment: "Tag value will change")
		case .added: return NSLocalizedString("added", comment: "Tag will be added")
		case .notAdded: return NSLocalizedString("not added", comment: "Tag will not be added")
		case .removed: return NSLocalizedString("removed", comment: "Tag will be removed")
		}
	}

	private static func color(for status: TagMergeModel.Status) -> Color {
		switch status {
		case .kept, .notAdded: return .secondary
		case .changed: return .orange
		case .added: return .green
		case .removed: return .red
		}
	}

	// MARK: Footer

	private var footer: some View {
		VStack(spacing: 8) {
			Text(summary)
				.font(.footnote)
				.foregroundColor(.secondary)
			HStack(spacing: 10) {
				if model.isCustomized {
					actionButton(NSLocalizedString("Reset", comment: "Discard per-tag choices"),
					             color: .accentColor, filled: false)
					{
						self.model.reset()
					}
					actionButton(String(format: NSLocalizedString("Apply %d Changes",
					                                              comment: "Button, %d is a count of tag changes"),
					                    model.changeCount),
					             color: .accentColor, filled: true)
					{
						self.completion(self.model.selectedTags)
					}
				} else {
					actionButton(NSLocalizedString("Replace All", comment: "Discard all existing tags"),
					             color: .red, filled: false)
					{
						self.completion(self.model.replacedTags)
					}
					actionButton(NSLocalizedString("Merge All", comment: "Accept all incoming tags, keep the rest"),
					             color: .accentColor, filled: true)
					{
						self.completion(self.model.mergedTags)
					}
				}
			}
		}
		.padding(.horizontal, 16)
		.padding(.vertical, 10)
		.background(Color(UIColor.secondarySystemGroupedBackground).edgesIgnoringSafeArea(.bottom))
	}

	private var summary: String {
		String(format: NSLocalizedString("%d added · %d changed · %d removed",
		                                 comment: "Summary of tag changes"),
		       model.count(of: .added),
		       model.count(of: .changed),
		       model.count(of: .removed))
	}

	private func actionButton(_ title: String,
	                          color: Color,
	                          filled: Bool,
	                          action: @escaping () -> Void) -> some View
	{
		Button(action: action) {
			Text(title)
				.font(.headline)
				.foregroundColor(filled ? .white : color)
				.frame(maxWidth: .infinity, minHeight: 50)
				.background(RoundedRectangle(cornerRadius: 12).fill(filled ? color : Color.clear))
				.overlay(RoundedRectangle(cornerRadius: 12).stroke(color, lineWidth: 1.5))
		}
		.buttonStyle(PlainButtonStyle())
	}
}

// MARK: UIKit presentation

extension TagMergeView {
	/// Presents the sheet and calls `completion` once it has been dismissed,
	/// with the resulting tags or nil if the user cancelled.
	///
	/// Callers should check `model.isNoOp` first and show a toast instead.
	static func present(from parent: UIViewController,
	                    model: TagMergeModel,
	                    source: TagMergeSource,
	                    objectName: String,
	                    completion: @escaping ([String: String]?) -> Void)
	{
		weak var presented: UIViewController?
		let view = TagMergeView(model: model, source: source, objectName: objectName) { tags in
			presented?.dismiss(animated: true) {
				completion(tags)
			}
		}
		let host = UIHostingController(rootView: view)
		// Disable swipe-to-dismiss so completion is always called.
		host.isModalInPresentation = true
		presented = host
		parent.present(host, animated: true)
	}
}
