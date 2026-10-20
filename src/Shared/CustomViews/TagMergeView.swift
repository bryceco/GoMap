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

	var allowsCancel: Bool { true }

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

	enum Mode: Int, CaseIterable {
		case merge
		case replace
	}

	enum Status {
		case kept
		case changed
		case added
		case notAdded
		case removed

		var isChange: Bool { self == .changed || self == .added || self == .removed }
	}

	struct Row: Identifiable {
		let key: String
		let current: String?
		let incoming: String?
		let isIdentical: Bool
		var id: String { key }
	}

	let current: [String: String]
	let incoming: [String: String]
	/// All keys, sorted alphabetically. Includes both differing and identical rows.
	let allRows: [Row]
	/// Only the rows that differ (used for choices, counts, etc.).
	var rows: [Row] { allRows.filter { !$0.isIdentical } }

	@Published var choice: [String: Side]

	init(current: [String: String], incoming: [String: String]) {
		var allRows: [Row] = []
		for key in Set(current.keys).union(incoming.keys).sorted() {
			let isIdentical = current[key] == incoming[key]
			allRows.append(Row(key: key, current: current[key], incoming: incoming[key],
			                   isIdentical: isIdentical))
		}
		self.current = current
		self.incoming = incoming
		self.allRows = allRows
		self.choice = Self.defaultChoice(for: allRows.filter { !$0.isIdentical }, mode: .merge)
	}

	private static func defaultChoice(for rows: [Row], mode: Mode) -> [String: Side] {
		var choice: [String: Side] = [:]
		for row in rows {
			switch mode {
			case .merge:
				// Incoming wins where present; current-only tags are kept.
				choice[row.key] = row.incoming != nil ? .incoming : .current
			case .replace:
				// Incoming wins always; current-only tags are removed.
				choice[row.key] = .incoming
			}
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

	/// Which preset the current choices match, if any.
	var activeMode: Mode? {
		for mode in Mode.allCases {
			if choice == Self.defaultChoice(for: rows, mode: mode) {
				return mode
			}
		}
		return nil
	}

	func apply(_ mode: Mode) {
		choice = Self.defaultChoice(for: rows, mode: mode)
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
			VStack(spacing: 0) {
				header
				presetButtons
				columnHeaders
				Divider()
			}
			.background(Color(UIColor.systemGroupedBackground))
			ScrollView {
				VStack(spacing: 10) {
					ForEach(model.allRows) { row in
						if row.isIdentical {
							self.identicalRowView(row)
						} else {
							self.rowView(row)
						}
					}
				}
				.padding(.horizontal, 16)
				.padding(.bottom, 8)
			}
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
					Button(action: { self.completion(self.model.selectedTags) }) {
						Text(NSLocalizedString("Done", comment: ""))
							.fontWeight(.bold)
							.frame(minHeight: 44)
					}
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

	private var presetButtons: some View {
		HStack(spacing: 10) {
			presetButton(NSLocalizedString("Merge", comment: "Apply merge preset to all tags"),
			             active: model.activeMode == .merge) { model.apply(.merge) }
			presetButton(NSLocalizedString("Replace", comment: "Apply replace preset to all tags"),
			             active: model.activeMode == .replace) { model.apply(.replace) }
		}
		.padding(.horizontal, 16)
		.padding(.bottom, 6)
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
		let placeholder = NSLocalizedString("(none)", comment: "Tag is not present")
		let selected = model.choice[row.key] == side
		let shape = RoundedRectangle(cornerRadius: 10)
		let text = Text(value ?? placeholder)
		let isSingleToken = value?.rangeOfCharacter(from: .whitespacesAndNewlines) == nil
		return Button(action: { self.model.choice[row.key] = side }) {
			HStack(alignment: .firstTextBaseline, spacing: 6) {
				Image(systemName: selected ? "checkmark.circle.fill" : "circle")
					.imageScale(.small)
					.foregroundColor(selected ? .accentColor : Color(UIColor.tertiaryLabel))
					.accessibility(hidden: true)
				(value == nil ? text.italic() : text)
					.font(.callout)
					.foregroundColor(value == nil ? .secondary : .primary)
					.multilineTextAlignment(.leading)
					.lineLimit(isSingleToken ? 1 : nil)
					.minimumScaleFactor(isSingleToken ? 0.6 : 1)
			}
			.padding(.horizontal, 10)
			.padding(.vertical, 11)
			.frame(minHeight: 44)
			.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
			.background(shape.fill(selected
					? Color.accentColor.opacity(0.15)
					: Color(UIColor.secondarySystemGroupedBackground)))
			.overlay(selected ? nil : shape.strokeBorder(Color(UIColor.separator), lineWidth: 1))
			.contentShape(shape)
		}
		.buttonStyle(PlainButtonStyle())
		.accessibility(addTraits: selected ? .isSelected : [])
	}

	private func identicalRowView(_ row: TagMergeModel.Row) -> some View {
		VStack(spacing: 4) {
			HStack(alignment: .firstTextBaseline) {
				Text(row.key)
					.font(.subheadline)
					.fontWeight(.semibold)
				Spacer()
				Text(NSLocalizedString("Keep", comment: "Keep the tag value"))
					.font(.caption)
					.fontWeight(.semibold)
					.foregroundColor(.secondary)
			}
			Text(row.current ?? "")
				.font(.callout)
				.foregroundColor(.secondary)
				.multilineTextAlignment(.leading)
				.padding(.horizontal, 10)
				.padding(.vertical, 6)
				.frame(maxWidth: .infinity, alignment: .leading)
				.background(RoundedRectangle(cornerRadius: 10)
					.fill(Color(UIColor.secondarySystemGroupedBackground)))
		}
	}

	private static func label(for status: TagMergeModel.Status) -> String {
		switch status {
		case .kept: return NSLocalizedString("Keep", comment: "Tag value will be kept")
		case .changed: return NSLocalizedString("Change", comment: "Tag value will change")
		case .added: return NSLocalizedString("Add", comment: "Tag will be added")
		case .notAdded: return NSLocalizedString("Skip", comment: "Tag will not be added")
		case .removed: return NSLocalizedString("Remove", comment: "Tag will be removed")
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

	// MARK: Preset buttons

	private func presetButton(_ title: String, active: Bool, action: @escaping () -> Void) -> some View {
		Button(action: action) {
			HStack(spacing: 6) {
				if active {
					Image(systemName: "checkmark")
						.font(.subheadline.weight(.semibold))
				}
				Text(title)
					.font(.subheadline)
					.fontWeight(active ? .semibold : .medium)
			}
			.foregroundColor(.accentColor)
			.frame(maxWidth: .infinity, minHeight: 36)
			.background(RoundedRectangle(cornerRadius: 8)
				.fill(active ? Color.accentColor.opacity(0.15) : Color.clear))
			.overlay(RoundedRectangle(cornerRadius: 8)
				.stroke(Color.accentColor, lineWidth: active ? 1.5 : 1))
		}
		.buttonStyle(PlainButtonStyle())
		.accessibility(addTraits: active ? .isSelected : [])
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
