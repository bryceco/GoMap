//
//  UploadViewController.swift
//  Go Map!!
//
//  Created by Bryce Cogswell on 12/19/12.
//  Copyright (c) 2012 Bryce Cogswell. All rights reserved.
//

import KissXML
import MessageUI
import UIKit

// Section header titles and the comment placeholder. Kept as named constants (rather than
// inline at each use site) so translators and reviewers can find every user-facing string here.
private enum UploadStrings {
	static let commentHeader = NSLocalizedString("Changeset comment",
	                                             comment: "Header for the changeset comment section on the upload screen")
	static let sourceHeader = NSLocalizedString("Source",
	                                            comment: "Header for the data source section on the upload screen")
	static let commentPlaceholder = NSLocalizedString("Describe your changes...",
	                                                  comment: "Placeholder text shown in the empty changeset comment field")
}

private func sanitizedURL(_ urlString: String) -> String {
	let sensitiveKeys = ["token", "auth", "api_key", "access_token", "connectid", "signature"]

	guard var components = URLComponents(string: urlString) else { return urlString }
	components.queryItems = components.queryItems?.map { item in
		if sensitiveKeys.contains(item.name.lowercased()) {
			return URLQueryItem(name: item.name, value: "{\(item.name)}")
		} else {
			return item
		}
	}
	return components.url?.absoluteString ?? urlString
}

// MARK: - Private Table Support Types

/// Full-width cell hosting the changeset comment editor. The text view doesn't scroll;
/// instead the cell grows with its content (down to a minimum height).
private final class CommentCell: UITableViewCell {
	static let minimumTextHeight: CGFloat = 72

	let textView = UITextView()
	let clearButton = UIButton(type: .system)
	let historyButton = UIButton(type: .system)
	private let placeholderLabel = UILabel()

	override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
		super.init(style: style, reuseIdentifier: reuseIdentifier)
		selectionStyle = .none

		textView.font = UIFont.preferredFont(forTextStyle: .body)
		textView.adjustsFontForContentSizeCategory = true
		textView.backgroundColor = .clear
		textView.isScrollEnabled = false
		textView.textContainerInset = .zero
		textView.textContainer.lineFragmentPadding = 0
		textView.returnKeyType = .done
		textView.translatesAutoresizingMaskIntoConstraints = false
		contentView.addSubview(textView)

		historyButton.setImage(UIImage(systemName: "clock.arrow.circlepath") ?? UIImage(systemName: "clock"),
		                       for: .normal)
		clearButton.setImage(UIImage(systemName: "xmark.circle.fill"), for: .normal)
		clearButton.tintColor = .tertiaryLabel

		// History comes first so it doesn't jump around when the clear button shows/hides.
		let buttons = UIStackView(arrangedSubviews: [historyButton, clearButton])
		buttons.axis = .vertical
		buttons.spacing = 4
		buttons.translatesAutoresizingMaskIntoConstraints = false
		contentView.addSubview(buttons)

		let margins = contentView.layoutMarginsGuide
		// Not quite required, to avoid a transient conflict with the cell's estimated height.
		let bottom = textView.bottomAnchor.constraint(equalTo: margins.bottomAnchor)
		bottom.priority = .required - 1

		NSLayoutConstraint.activate([
			textView.leadingAnchor.constraint(equalTo: margins.leadingAnchor),
			textView.topAnchor.constraint(equalTo: margins.topAnchor),
			bottom,
			textView.heightAnchor.constraint(greaterThanOrEqualToConstant: Self.minimumTextHeight),

			buttons.leadingAnchor.constraint(equalTo: textView.trailingAnchor, constant: 8),
			buttons.trailingAnchor.constraint(equalTo: margins.trailingAnchor),
			buttons.topAnchor.constraint(equalTo: margins.topAnchor),
			buttons.bottomAnchor.constraint(lessThanOrEqualTo: margins.bottomAnchor),
			buttons.widthAnchor.constraint(equalToConstant: 28),
			historyButton.heightAnchor.constraint(equalToConstant: 28),
			clearButton.heightAnchor.constraint(equalToConstant: 28)
		])

		placeholderLabel.text = UploadStrings.commentPlaceholder
		placeholderLabel.font = textView.font
		placeholderLabel.adjustsFontForContentSizeCategory = true
		placeholderLabel.textColor = .placeholderText
		placeholderLabel.translatesAutoresizingMaskIntoConstraints = false
		contentView.addSubview(placeholderLabel)
		NSLayoutConstraint.activate([
			placeholderLabel.leadingAnchor.constraint(equalTo: textView.leadingAnchor),
			placeholderLabel.topAnchor.constraint(equalTo: textView.topAnchor),
			placeholderLabel.trailingAnchor.constraint(lessThanOrEqualTo: textView.trailingAnchor)
		])
	}

	@available(*, unavailable)
	required init?(coder: NSCoder) { fatalError() }

	/// Placeholder visibility follows the text view's content; callers just call this after
	/// any edit rather than touching the label directly.
	func updatePlaceholderVisibility() {
		placeholderLabel.isHidden = textView.text.count > 0
	}

	/// Hides the placeholder outright, e.g. while the text view has focus.
	func hidePlaceholder() {
		placeholderLabel.isHidden = true
	}
}

/// Cell hosting the single-line source field, plus a button for recently used sources.
private final class SourceCell: UITableViewCell {
	let textField = UITextField()
	let historyButton = UIButton(type: .system)

	override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
		super.init(style: style, reuseIdentifier: reuseIdentifier)
		selectionStyle = .none

		textField.font = UIFont.preferredFont(forTextStyle: .body)
		textField.adjustsFontForContentSizeCategory = true
		textField.borderStyle = .none
		textField.clearButtonMode = .whileEditing
		textField.returnKeyType = .done
		textField.setContentHuggingPriority(.defaultLow, for: .horizontal)
		textField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

		historyButton.setImage(UIImage(systemName: "clock.arrow.circlepath") ?? UIImage(systemName: "clock"),
		                       for: .normal)

		let stack = UIStackView(arrangedSubviews: [textField, historyButton])
		stack.axis = .horizontal
		stack.spacing = 8
		stack.alignment = .center
		stack.translatesAutoresizingMaskIntoConstraints = false
		contentView.addSubview(stack)

		let margins = contentView.layoutMarginsGuide
		NSLayoutConstraint.activate([
			stack.leadingAnchor.constraint(equalTo: margins.leadingAnchor),
			stack.trailingAnchor.constraint(equalTo: margins.trailingAnchor),
			stack.topAnchor.constraint(equalTo: margins.topAnchor),
			stack.bottomAnchor.constraint(equalTo: margins.bottomAnchor),
			textField.heightAnchor.constraint(greaterThanOrEqualToConstant: 28),
			historyButton.widthAnchor.constraint(equalToConstant: 28),
			historyButton.heightAnchor.constraint(equalToConstant: 28)
		])
	}

	@available(*, unavailable)
	required init?(coder: NSCoder) { fatalError() }
}

/// Informational cell: either the orange "distant changes were deselected" warning,
/// or the "nothing to upload" message.
private final class MessageCell: UITableViewCell {
	static let reuseIdentifier = "MessageCell"

	enum Style {
		case warning
		case empty
	}

	private let iconView = UIImageView()
	private let messageLabel = UILabel()

	override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
		super.init(style: style, reuseIdentifier: reuseIdentifier)
		selectionStyle = .none

		iconView.image = UIImage(systemName: "exclamationmark.triangle.fill")
		iconView.tintColor = .systemOrange
		iconView.contentMode = .scaleAspectFit
		iconView.setContentHuggingPriority(.required, for: .horizontal)
		iconView.setContentCompressionResistancePriority(.required, for: .horizontal)

		messageLabel.numberOfLines = 0
		messageLabel.adjustsFontForContentSizeCategory = true

		let stack = UIStackView(arrangedSubviews: [iconView, messageLabel])
		stack.axis = .horizontal
		stack.spacing = 10
		stack.alignment = .center
		stack.translatesAutoresizingMaskIntoConstraints = false
		contentView.addSubview(stack)

		let margins = contentView.layoutMarginsGuide
		NSLayoutConstraint.activate([
			iconView.widthAnchor.constraint(equalToConstant: 22),
			iconView.heightAnchor.constraint(equalToConstant: 22),
			stack.leadingAnchor.constraint(equalTo: margins.leadingAnchor),
			stack.trailingAnchor.constraint(equalTo: margins.trailingAnchor),
			stack.topAnchor.constraint(equalTo: margins.topAnchor),
			stack.bottomAnchor.constraint(equalTo: margins.bottomAnchor)
		])
	}

	@available(*, unavailable)
	required init?(coder: NSCoder) { fatalError() }

	func configure(text: String, style: Style) {
		messageLabel.text = text
		switch style {
		case .warning:
			iconView.isHidden = false
			messageLabel.font = UIFont.preferredFont(forTextStyle: .footnote)
			messageLabel.textColor = .label
			messageLabel.textAlignment = .natural
			backgroundColor = UIColor.systemOrange.withAlphaComponent(0.15)
		case .empty:
			iconView.isHidden = true
			messageLabel.font = UIFont.preferredFont(forTextStyle: .body)
			messageLabel.textColor = .secondaryLabel
			messageLabel.textAlignment = .center
			backgroundColor = .secondarySystemGroupedBackground
		}
	}
}

/// Section header for a ConnectedObjects group — shows a checkmark toggle and a summary label.
private final class GroupSectionHeader: UITableViewHeaderFooterView {
	static let reuseIdentifier = "GroupSectionHeader"

	private let checkImageView = UIImageView()
	private let titleLabel = UILabel()
	private let discardButton = UIButton(type: .system)
	var onSelect: (() -> Void)?
	var onDiscard: (() -> Void)?

	var isChecked: Bool = false {
		didSet {
			let name = isChecked ? "checkmark.circle.fill" : "circle"
			checkImageView.image = UIImage(systemName: name)
			checkImageView.tintColor = isChecked ? .systemBlue : .secondaryLabel
		}
	}

	func configure(title: String, isChecked checked: Bool, onSelect: @escaping () -> Void, onDiscard: @escaping () -> Void) {
		titleLabel.text = title
		isChecked = checked
		self.onSelect = onSelect
		self.onDiscard = onDiscard
	}

	override init(reuseIdentifier: String?) {
		super.init(reuseIdentifier: reuseIdentifier)
		setup()
	}

	@available(*, unavailable)
	required init?(coder: NSCoder) { fatalError() }

	private func setup() {
		checkImageView.contentMode = .scaleAspectFit
		checkImageView.translatesAutoresizingMaskIntoConstraints = false
		checkImageView.image = UIImage(systemName: "circle")
		checkImageView.tintColor = .secondaryLabel

		titleLabel.font = UIFont.preferredFont(forTextStyle: .subheadline)
		titleLabel.numberOfLines = 0
		titleLabel.translatesAutoresizingMaskIntoConstraints = false
		titleLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)

		discardButton.setImage(UIImage(systemName: "arrow.uturn.backward.circle"), for: .normal)
		discardButton.tintColor = .systemRed
		discardButton.translatesAutoresizingMaskIntoConstraints = false
		discardButton.addTarget(self, action: #selector(discardTapped), for: .touchUpInside)
		NSLayoutConstraint.activate([
			discardButton.widthAnchor.constraint(equalToConstant: 22),
			discardButton.heightAnchor.constraint(equalToConstant: 22)
		])

		let stack = UIStackView(arrangedSubviews: [checkImageView, titleLabel, discardButton])
		stack.axis = .horizontal
		stack.spacing = 8
		stack.alignment = .center
		stack.translatesAutoresizingMaskIntoConstraints = false
		contentView.addSubview(stack)

		NSLayoutConstraint.activate([
			checkImageView.widthAnchor.constraint(equalToConstant: 22),
			checkImageView.heightAnchor.constraint(equalToConstant: 22),
			stack.leadingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.leadingAnchor),
			stack.trailingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.trailingAnchor),
			stack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 8),
			stack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -8)
		])

		addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(selectTapped)))
	}

	@objc private func selectTapped() { onSelect?() }
	@objc private func discardTapped() { onDiscard?() }
}

/// A cell that contains a non-scrolling UITextView sized to fit its content.
private final class ChangeGroupCell: UITableViewCell {
	static let reuseIdentifier = "ChangeGroupCell"

	let groupTextView = UITextView()

	override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
		super.init(style: style, reuseIdentifier: reuseIdentifier)

		groupTextView.isEditable = false
		groupTextView.isScrollEnabled = false
		groupTextView.dataDetectorTypes = []
		groupTextView.backgroundColor = .clear
		groupTextView.textContainerInset = UIEdgeInsets(top: 8, left: 4, bottom: 8, right: 4)
		groupTextView.translatesAutoresizingMaskIntoConstraints = false
		contentView.addSubview(groupTextView)

		NSLayoutConstraint.activate([
			groupTextView.topAnchor.constraint(equalTo: contentView.topAnchor),
			groupTextView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
			groupTextView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
			groupTextView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor)
		])
	}

	@available(*, unavailable)
	required init?(coder: NSCoder) { fatalError() }
}

// MARK: - UploadViewController

class UploadViewController: UIViewController {
	/// Table layout. Comment and source are always present; the rest depends on the pending edits.
	private enum Section {
		case comment
		case source
		case distanceWarning
		case noChanges
		case group(Int) // index into connectedGroups
	}

	var mapData: OsmMapData!
	@IBOutlet var tableView: UITableView!
	@IBOutlet var commitButton: UIBarButtonItem!
	@IBOutlet var cancelButton: UIBarButtonItem!
	@IBOutlet var progressView: UIActivityIndicatorView!

	// The comment and source cells are created once and never reused, so they
	// retain their text and first-responder state regardless of scrolling.
	private lazy var commentCell = CommentCell(style: .default, reuseIdentifier: nil)
	private lazy var sourceCell = SourceCell(style: .default, reuseIdentifier: nil)

	var commentTextView: UITextView { commentCell.textView }
	var clearCommentButton: UIButton { commentCell.clearButton }
	var commentHistoryButton: UIButton { commentCell.historyButton }
	var sourceTextField: UITextField { sourceCell.textField }
	var sourceHistoryButton: UIButton { sourceCell.historyButton }

	// Edit/Export act on the selected groups and live in the bottom toolbar.
	private lazy var editXmlButton = UIBarButtonItem(barButtonSystemItem: .edit,
	                                                 target: self,
	                                                 action: #selector(editXml(_:)))
	private lazy var exportOscButton = UIBarButtonItem(barButtonSystemItem: .action,
	                                                   target: self,
	                                                   action: #selector(exportOscFile(_:)))

	private var sections: [Section] = [.comment, .source]
	private var connectedGroups: [ConnectedObjects] = []
	private var selectedGroupIndices: Set<Int> = []

	private var selectedGroups: [ConnectedObjects] {
		connectedGroups.indices.filter { selectedGroupIndices.contains($0) }.map { connectedGroups[$0] }
	}

	var recentCommentList = MostRecentlyUsed<String>(maxCount: 5,
	                                                 userPrefsKey: UserPrefs.shared.recentCommitComments)
	var recentSourceList = MostRecentlyUsed<String>(maxCount: 5,
	                                                userPrefsKey: UserPrefs.shared.recentSourceComments)

	override func viewDidLoad() {
		super.viewDidLoad()

		// Comment cell
		commentTextView.delegate = self
		clearCommentButton.addTarget(self, action: #selector(clearCommentText(_:)), for: .touchUpInside)
		commentHistoryButton.addTarget(self, action: #selector(showCommitMessageHistory(_:)), for: .touchUpInside)

		// Source cell
		sourceTextField.placeholder = "survey, Bing, knowledge" // intentionally not localized: see #557
		sourceTextField.addTarget(self, action: #selector(dismissKeyboard(_:)), for: .editingDidEndOnExit)
		sourceHistoryButton.addTarget(self, action: #selector(showSourceHistory(_:)), for: .touchUpInside)

		// Table
		tableView.register(ChangeGroupCell.self, forCellReuseIdentifier: ChangeGroupCell.reuseIdentifier)
		tableView.register(MessageCell.self, forCellReuseIdentifier: MessageCell.reuseIdentifier)
		tableView.register(GroupSectionHeader.self,
		                   forHeaderFooterViewReuseIdentifier: GroupSectionHeader.reuseIdentifier)
		tableView.rowHeight = UITableView.automaticDimension
		tableView.estimatedRowHeight = 100
		tableView.keyboardDismissMode = .interactive
		tableView.dataSource = self
		tableView.delegate = self

		toolbarItems = [
			editXmlButton,
			UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil),
			exportOscButton
		]

		progressView.style = .large
	}

	override func viewWillAppear(_ animated: Bool) {
		super.viewWillAppear(animated)
		navigationController?.setToolbarHidden(false, animated: animated)

		let mapView = AppDelegate.shared.mapView
		mapData = mapView?.mapData

		commentTextView.text = UserPrefs.shared.uploadComment.value
		sourceTextField.text = UserPrefs.shared.uploadSource.value
		commentCell.updatePlaceholderVisibility()

		clearCommentButton.isHidden = true
		commentHistoryButton.isHidden = recentCommentList.count == 0
		sourceHistoryButton.isHidden = recentSourceList.count == 0

		reloadGroups()
	}

	override func viewWillDisappear(_ animated: Bool) {
		super.viewWillDisappear(animated)
		// Don't let the toolbar follow us into the XML editor or login screens.
		navigationController?.setToolbarHidden(true, animated: animated)
		UserPrefs.shared.uploadComment.value = commentTextView.text
		UserPrefs.shared.uploadSource.value = sourceTextField.text
	}

	// MARK: - Sections

	/// Recomputes the change groups, their default selection, and the table layout.
	private func reloadGroups() {
		connectedGroups = mapData?.undoManager.connectedObjects() ?? []
		selectedGroupIndices = nearbyGroupIndices()

		sections = [.comment, .source]
		if connectedGroups.isEmpty {
			sections.append(.noChanges)
		} else {
			if selectedGroupIndices.count < connectedGroups.count {
				// Some distant groups were automatically deselected
				sections.append(.distanceWarning)
			}
			sections += connectedGroups.indices.map { Section.group($0) }
		}

		updateActionButtons()
		tableView.reloadData()
	}

	private func sectionIndex(forGroup groupIndex: Int) -> Int? {
		sections.firstIndex {
			if case let .group(index) = $0 { return index == groupIndex }
			return false
		}
	}

	private func updateActionButtons() {
		let hasSelection = !selectedGroupIndices.isEmpty
		commitButton.isEnabled = hasSelection
		exportOscButton.isEnabled = hasSelection
		editXmlButton.isEnabled = hasSelection
	}

	/// Asks the table to re-measure self-sizing rows (i.e. the comment cell) without reloading them.
	private func updateRowHeights() {
		UIView.performWithoutAnimation {
			tableView.beginUpdates()
			tableView.endUpdates()
		}
	}

	private func updateCommentHeightIfNeeded() {
		let textView = commentTextView
		guard textView.bounds.width > 0 else { return }
		let fitting = textView.sizeThatFits(CGSize(width: textView.bounds.width,
		                                           height: .greatestFiniteMagnitude)).height
		let target = max(fitting, CommentCell.minimumTextHeight)
		if abs(target - textView.bounds.height) > 0.5 {
			updateRowHeights()
		}
	}

	// MARK: - Change Groups

	/// Returns the indices of groups that are geographically close to the most recently edited group.
	/// Each group's bounding box is expanded by ~500 m; groups whose expanded boxes overlap are
	/// considered part of the same cluster. The cluster containing the most recently edited group
	/// is returned, leaving distant groups deselected by default.
	private func nearbyGroupIndices() -> Set<Int> {
		let count = connectedGroups.count
		guard count > 1 else { return Set(connectedGroups.indices) }

		// ~500 m expressed in degrees (1° lat ≈ 111 km)
		let expandDeg = 0.005

		let expandedBoxes: [OSMRect?] = connectedGroups.map { group in
			guard let first = group.objects.first else { return nil }
			let bbox = group.objects.reduce(first.boundingBox) { $0.union($1.boundingBox) }
			return OSMRect(x: bbox.origin.x - expandDeg,
			               y: bbox.origin.y - expandDeg,
			               width: bbox.size.width + 2 * expandDeg,
			               height: bbox.size.height + 2 * expandDeg)
		}

		// Union-Find to identify connected components
		var parent = Array(0..<count)
		func find(_ x: Int) -> Int {
			var x = x
			while parent[x] != x {
				x = parent[x]
			}
			return x
		}
		for i in 0..<count {
			for j in (i + 1)..<count {
				guard let bi = expandedBoxes[i], let bj = expandedBoxes[j] else { continue }
				if bi.intersectsRect(bj) {
					parent[find(i)] = find(j)
				}
			}
		}

		// Select the component containing the most recently edited group
		let mostRecentIndex = connectedGroups.indices.max {
			(connectedGroups[$0].undoGroups.max() ?? 0) < (connectedGroups[$1].undoGroups.max() ?? 0)
		} ?? 0
		let targetRoot = find(mostRecentIndex)
		return Set(connectedGroups.indices.filter { find($0) == targetRoot })
	}

	private func summaryLabel(for group: ConnectedObjects) -> String {
		guard let doc = OsmXmlGenerator.createXmlFor(objects: group.objects,
		                                             generator: AppDelegate.shared.generator)
		else { return "" }
		let (nodeCount, wayCount, relationCount) = OsmXmlGenerator.objectCounts(in: doc)
		var parts: [String] = []
		if nodeCount > 0 { parts.append(nodeCount == 1 ? "1 node" : "\(nodeCount) nodes") }
		if wayCount > 0 { parts.append(wayCount == 1 ? "1 way" : "\(wayCount) ways") }
		if relationCount > 0 { parts.append(relationCount == 1 ? "1 relation" : "\(relationCount) relations") }
		return parts.joined(separator: ", ")
	}

	private func toggleGroup(at groupIndex: Int) {
		if selectedGroupIndices.contains(groupIndex) {
			selectedGroupIndices.remove(groupIndex)
		} else {
			selectedGroupIndices.insert(groupIndex)
		}
		if let section = sectionIndex(forGroup: groupIndex),
		   let header = tableView.headerView(forSection: section) as? GroupSectionHeader
		{
			header.isChecked = selectedGroupIndices.contains(groupIndex)
		}
		updateActionButtons()
	}

	private func confirmDiscard(at groupIndex: Int) {
		let group = connectedGroups[groupIndex]
		let alert = UIAlertController(
			title: NSLocalizedString("Discard Changes", comment: "Title for discard-group confirmation alert"),
			message: NSLocalizedString(
				"These edits will be permanently discarded and cannot be recovered.",
				comment: "Body of discard-group confirmation alert"),
			preferredStyle: .alert)
		alert.addAction(UIAlertAction(title: NSLocalizedString("Cancel", comment: ""), style: .cancel))
		alert.addAction(UIAlertAction(
			title: NSLocalizedString("Discard", comment: "Destructive button that discards a group of edits"),
			style: .destructive)
		{ [weak self] _ in self?.discardGroup(group) })
		present(alert, animated: true)
	}

	private func discardGroup(_ group: ConnectedObjects) {
		mapData.undoManager.discardGroups(group.undoGroups)
		reloadGroups()
	}

	private func currentImagery() -> String {
		guard
			let mainView = AppDelegate.shared.mainView,
			mainView.viewState.state == .EDITORAERIAL || mainView.viewState.state == .AERIAL
		else {
			return ""
		}
		let server = mainView.mapLayersView.aerialLayer.tileServer
		if server.identifier.hasPrefix("http:") || server.identifier.hasPrefix("https:") {
			var imagery = sanitizedURL(server.identifier)
			if imagery.count > 255 {
				imagery = String(imagery.prefix(255))
			}
			return imagery
		} else {
			return server.name
		}
	}

	// MARK: - Actions

	@objc func dismissKeyboard(_ sender: UITextField) {
		sender.resignFirstResponder()
	}

	@objc func clearCommentText(_ sender: Any) {
		commentTextView.text = ""
		clearCommentButton.isHidden = true
		updateCommentHeightIfNeeded()
	}

	private func showHistorySheet(_ list: [String], button: UIButton, textView: UIView) {
		let actionSheet = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)
		for message in list {
			actionSheet.addAction(UIAlertAction(title: message, style: .default, handler: { _ in
				if let view = textView as? UITextView {
					view.text = message
					view.resignFirstResponder()
				} else if let view = textView as? UITextField {
					view.text = message
					view.resignFirstResponder()
				}
				self.commentCell.updatePlaceholderVisibility()
				self.updateCommentHeightIfNeeded()
			}))
		}
		actionSheet.addAction(UIAlertAction(title: NSLocalizedString("Cancel", comment: ""),
		                                    style: .cancel,
		                                    handler: nil))
		actionSheet.popoverPresentationController?.sourceView = button
		actionSheet.popoverPresentationController?.sourceRect = button.bounds
		present(actionSheet, animated: true)
	}

	@objc func showCommitMessageHistory(_ sender: Any) {
		showHistorySheet(recentCommentList.items, button: commentHistoryButton, textView: commentTextView)
	}

	@objc func showSourceHistory(_ sender: Any) {
		showHistorySheet(recentSourceList.items, button: sourceHistoryButton, textView: sourceTextField)
	}

	@IBAction func commit(_ sender: Any?) {
		guard
			let oAuth = OSM_SERVER.oAuth2,
			oAuth.isAuthorized()
		else {
			performSegue(withIdentifier: "loginSegue", sender: self)
			return
		}

		guard
			let didPrev = UserPrefs.shared.userDidPreviousUpload.value,
			didPrev
		else {
			let alert = UIAlertController(
				title: NSLocalizedString("Attention", comment: ""),
				message: NSLocalizedString(
					"You are about to make changes to the live OpenStreetMap database. Your changes will be visible to everyone in the world.\n\nTo continue press Commit once again, otherwise press Cancel.",
					comment: ""),
				preferredStyle: .alert)
			alert.addAction(UIAlertAction(title: NSLocalizedString("Cancel", comment: ""),
			                              style: .cancel,
			                              handler: nil))
			alert.addAction(UIAlertAction(title: NSLocalizedString("Commit", comment: ""),
			                              style: .default,
			                              handler: { [self] _ in
			                              	UserPrefs.shared.userDidPreviousUpload.value = true
			                              	commit(nil)
			                              }))
			present(alert, animated: true)
			return
		}

		Task { @MainActor in
			await performCommit()
		}
	}

	@MainActor
	func performCommit() async {
		let appDelegate = AppDelegate.shared

		progressView.startAnimating()
		commitButton.isEnabled = false
		cancelButton.isEnabled = false
		exportOscButton.isEnabled = false
		editXmlButton.isEnabled = false
		let generator = appDelegate.generator

		view.endEditing(true)

		var comment = commentTextView.text ?? ""
		comment = comment.trimmingCharacters(in: .whitespacesAndNewlines)
		if !comment.isEmpty { recentCommentList.updateWith(comment) }

		var source = sourceTextField.text ?? ""
		source = source.trimmingCharacters(in: .whitespacesAndNewlines)
		if !source.isEmpty { recentSourceList.updateWith(source) }

		let locale = PresetLanguages.preferredLanguageCode()
		let imagery = currentImagery()

		do {
			try await mapData.uploadChangeset(for: selectedGroups,
			                                  comment: comment,
			                                  source: source,
			                                  imagery: imagery,
			                                  generator: generator,
			                                  locale: locale)
			dismiss(animated: true)
			MainActor.runAfter(nanoseconds: 300_000000) {
				appDelegate.mapView.setNeedsLayout()
				MessageDisplay.shared.flashMessage(title: nil,
				                                   message: NSLocalizedString("Upload complete!", comment: ""),
				                                   duration: 1.5)
				var editCount = UserPrefs.shared.uploadCountPerVersion.value ?? 0
				editCount += 1
				UserPrefs.shared.uploadCountPerVersion.value = editCount
				appDelegate.mainView.askToRate(uploadCount: editCount)
			}
		} catch UrlSessionError.badStatusCode(401, _) {
			OSM_SERVER.oAuth2?.removeAuthorization()
			progressView.stopAnimating()
			commitButton.isEnabled = true
			cancelButton.isEnabled = true
			performSegue(withIdentifier: "loginSegue", sender: self)
		} catch {
			progressView.stopAnimating()
			cancelButton.isEnabled = true
			updateActionButtons()
			let alert = UIAlertController(
				title: NSLocalizedString("Unable to upload changes", comment: ""),
				message: error.localizedDescription,
				preferredStyle: .alert)
			alert.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: ""),
			                              style: .cancel,
			                              handler: nil))
			present(alert, animated: true)
		}
	}

	@objc func editXml(_ sender: Any) {
		let groups = selectedGroups
		guard !groups.isEmpty else { return }
		let appDelegate = AppDelegate.shared
		let objects = groups.reduce(into: Set<OsmBaseObject>()) { $0.formUnion($1.objects) }
		let doc = OsmXmlGenerator.createXmlFor(objects: objects, generator: appDelegate.generator)
		let xml = doc?.xmlString(withOptions: UInt(XMLNodePrettyPrint)) ?? ""
		var comment = commentTextView.text ?? ""
		comment = comment.trimmingCharacters(in: .whitespacesAndNewlines)
		var source = sourceTextField.text ?? ""
		source = source.trimmingCharacters(in: .whitespacesAndNewlines)

		let vc = XmlEditorViewController()
		vc.mapData = mapData
		vc.xmlText = xml + "\n\n\n\n\n\n\n\n\n\n\n\n"
		vc.comment = comment
		vc.source = source
		vc.imagery = currentImagery()
		vc.generator = appDelegate.generator
		vc.locale = PresetLanguages.preferredLanguageCode()
		vc.undoGroups = groups.reduce(into: Set<Int>()) { $0.formUnion($1.undoGroups) }
		navigationController?.pushViewController(vc, animated: true)
	}

	@objc func exportOscFile(_ sender: Any) {
		let objects = selectedGroups.reduce(into: Set<OsmBaseObject>()) { $0.formUnion($1.objects) }
		let doc = OsmXmlGenerator.createXmlFor(objects: objects, generator: AppDelegate.shared.generator)
		guard !selectedGroupIndices.isEmpty,
		      let text = doc?.xmlString(withOptions: UInt(XMLNodePrettyPrint)).data(using: .utf8),
		      let path = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
		      .appendingPathComponent("osmChange.osc"),
		      (try? text.write(to: path, options: .atomicWrite)) != nil
		else { return }

		let activityVC = UIActivityViewController(activityItems: [path] as [Any], applicationActivities: nil)
		activityVC.excludedActivityTypes = [UIActivity.ActivityType.addToReadingList]
		if let item = sender as? UIBarButtonItem {
			activityVC.popoverPresentationController?.barButtonItem = item
		} else {
			activityVC.popoverPresentationController?.sourceView = sender as? UIView
		}
		present(activityVC, animated: true, completion: nil)
	}

	@IBAction func cancel(_ sender: Any?) {
		dismiss(animated: true)
	}
}

// MARK: - UITextViewDelegate

extension UploadViewController: UITextViewDelegate {
	func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
		if textView == commentTextView, text == "\n" {
			textView.resignFirstResponder()
			return false
		}
		return true
	}

	func textViewDidChange(_ textView: UITextView) {
		if textView == commentTextView {
			clearCommentButton.isHidden = commentTextView.text.count == 0
			commentCell.updatePlaceholderVisibility()
			updateCommentHeightIfNeeded()
		}
	}

	func textViewDidBeginEditing(_ textView: UITextView) {
		if textView == commentTextView {
			clearCommentButton.isHidden = commentTextView.text.count == 0
			commentCell.hidePlaceholder()
		}
	}

	func textViewDidEndEditing(_ textView: UITextView) {
		if textView == commentTextView {
			clearCommentButton.isHidden = true
			commentCell.updatePlaceholderVisibility()
		}
	}

	// Navigate from the changeset back to the location of the modified object on the map.
	func textView(_ textView: UITextView,
	              shouldInteractWith url: URL,
	              in characterRange: NSRange,
	              interaction: UITextItemInteraction) -> Bool
	{
		let name = url.absoluteString
		guard !name.isEmpty else { return false }
		let ident = Int64(name.dropFirst()) ?? 0
		let extendedId: OsmExtendedIdentifier
		switch name.prefix(1) {
		case "n": extendedId = OsmExtendedIdentifier(.NODE, ident)
		case "w": extendedId = OsmExtendedIdentifier(.WAY, ident)
		case "r": extendedId = OsmExtendedIdentifier(.RELATION, ident)
		default: return false
		}
		let appDelegate = AppDelegate.shared
		guard let object = appDelegate.mapView.mapData.object(withExtendedIdentifier: extendedId)
		else { return false }
		appDelegate.mapView.selectObject(object)
		cancel(nil)
		return false
	}
}

// MARK: - UITableViewDataSource

extension UploadViewController: UITableViewDataSource {
	func numberOfSections(in tableView: UITableView) -> Int {
		sections.count
	}

	func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
		1
	}

	func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
		switch sections[section] {
		case .comment: return UploadStrings.commentHeader
		case .source: return UploadStrings.sourceHeader
		case .distanceWarning, .noChanges, .group: return nil
		}
	}

	func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
		switch sections[indexPath.section] {
		case .comment:
			return commentCell
		case .source:
			return sourceCell
		case .distanceWarning:
			let cell = tableView.dequeueReusableCell(
				withIdentifier: MessageCell.reuseIdentifier,
				for: indexPath) as! MessageCell
			cell.configure(
				text: NSLocalizedString(
					"Some changes are in a different location and have been deselected. Upload them as a separate changeset.",
					comment: "Warning shown on upload screen when distant edit groups are automatically deselected"),
				style: .warning)
			return cell
		case .noChanges:
			let cell = tableView.dequeueReusableCell(
				withIdentifier: MessageCell.reuseIdentifier,
				for: indexPath) as! MessageCell
			cell.configure(
				text: NSLocalizedString("Nothing to upload, no changes have been made.", comment: ""),
				style: .empty)
			return cell
		case let .group(groupIndex):
			return groupCell(for: connectedGroups[groupIndex], at: indexPath)
		}
	}

	private func groupCell(for group: ConnectedObjects, at indexPath: IndexPath) -> UITableViewCell {
		let cell = tableView.dequeueReusableCell(
			withIdentifier: ChangeGroupCell.reuseIdentifier,
			for: indexPath) as! ChangeGroupCell
		if let doc = OsmXmlGenerator.createXmlFor(objects: group.objects, generator: AppDelegate.shared.generator) {
			var primaryDescriptions: [Int64: String] = [:]
			var parentWayNames: [Int64: String] = [:]
			for obj in group.objects {
				if !obj.tags.isEmpty {
					let (name, feature) = obj.friendlyDescriptionWithFeature()
					primaryDescriptions[obj.ident] = name.map { "\($0) (\(feature))" } ?? feature
				} else if let node = obj as? OsmNode, node.wayCount > 0,
				          let parentWay = mapData.waysContaining(node).first
				{
					let (name, feature) = parentWay.friendlyDescriptionWithFeature()
					parentWayNames[node.ident] = name.map { "\($0) (\(feature))" } ?? feature
				}
			}
			cell.groupTextView.attributedText = OsmXmlGenerator.attributedStringForXML(
				doc,
				primaryDescriptions: primaryDescriptions,
				parentWayNames: parentWayNames)
		}
		cell.groupTextView.delegate = self
		return cell
	}
}

// MARK: - UITableViewDelegate

extension UploadViewController: UITableViewDelegate {
	func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
		// Comment and source use plain titles (see titleForHeaderInSection)
		guard case let .group(groupIndex) = sections[section] else { return nil }
		let header = tableView.dequeueReusableHeaderFooterView(
			withIdentifier: GroupSectionHeader.reuseIdentifier) as! GroupSectionHeader
		let group = connectedGroups[groupIndex]
		header.configure(title: summaryLabel(for: group),
		                 isChecked: selectedGroupIndices.contains(groupIndex),
		                 onSelect: { [weak self] in self?.toggleGroup(at: groupIndex) },
		                 onDiscard: { [weak self] in self?.confirmDiscard(at: groupIndex) })
		return header
	}

	func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
		UITableView.automaticDimension
	}

	func tableView(_ tableView: UITableView, estimatedHeightForHeaderInSection section: Int) -> CGFloat {
		44
	}
}
