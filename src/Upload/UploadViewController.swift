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

/// Section header for a ConnectedObjects group — shows a checkmark toggle and a summary label.
private final class GroupSectionHeader: UITableViewHeaderFooterView {
	static let reuseIdentifier = "GroupSectionHeader"

	private let checkImageView = UIImageView()
	private let titleLabel = UILabel()
	var onTap: (() -> Void)?

	var isChecked: Bool = false {
		didSet {
			let name = isChecked ? "checkmark.circle.fill" : "circle"
			checkImageView.image = UIImage(systemName: name)
			checkImageView.tintColor = isChecked ? .systemBlue : .secondaryLabel
		}
	}

	func configure(title: String, isChecked checked: Bool, onTap: @escaping () -> Void) {
		titleLabel.text = title
		isChecked = checked
		self.onTap = onTap
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

		let stack = UIStackView(arrangedSubviews: [checkImageView, titleLabel])
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

		addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(tapped)))
	}

	@objc private func tapped() { onTap?() }
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
	var mapData: OsmMapData!
	@IBOutlet var commentContainerView: UIView!
	@IBOutlet var groupsTableView: UITableView!
	@IBOutlet var commentTextView: UITextView!
	@IBOutlet var sourceTextField: UITextField!
	@IBOutlet var commitButton: UIBarButtonItem!
	@IBOutlet var cancelButton: UIBarButtonItem!
	@IBOutlet var progressView: UIActivityIndicatorView!
	@IBOutlet var exportOscButton: UIButton!
	@IBOutlet var editXmlButton: UIButton!
	@IBOutlet var clearCommentButton: UIButton!
	@IBOutlet var commentHistoryButton: UIButton!
	@IBOutlet var sourceHistoryButton: UIButton!
	@IBOutlet var changesetCommentPlaceholder: UILabel!

	private var connectedGroups: [ConnectedObjects] = []
	private var selectedGroupIndices: Set<Int> = []
	private var distanceBannerView: UIView?

	private var selectedGroups: [ConnectedObjects] {
		connectedGroups.indices.filter { selectedGroupIndices.contains($0) }.map { connectedGroups[$0] }
	}

	var recentCommentList = MostRecentlyUsed<String>(maxCount: 5,
	                                                 userPrefsKey: UserPrefs.shared.recentCommitComments)
	var recentSourceList = MostRecentlyUsed<String>(maxCount: 5,
	                                                userPrefsKey: UserPrefs.shared.recentSourceComments)

	override func viewDidLoad() {
		super.viewDidLoad()

		let color = UIColor.gray.withAlphaComponent(0.5)
		commentContainerView.layer.borderColor = color.cgColor
		commentContainerView.layer.borderWidth = 2.0
		commentContainerView.layer.cornerRadius = 10.0
		commentTextView.returnKeyType = .done

		sourceTextField.layer.borderColor = color.cgColor
		sourceTextField.layer.borderWidth = 2.0
		sourceTextField.layer.cornerRadius = 10.0
		sourceTextField.leftView = UIView(frame: CGRect(x: 0, y: 0, width: 7.5, height: 0))
		sourceTextField.leftViewMode = .always
		sourceTextField.returnKeyType = .done
		sourceTextField.addTarget(self, action: #selector(dismissKeyboard(_:)), for: .editingDidEndOnExit)

		// create button for source history
		sourceHistoryButton = UIButton(type: .custom)
		sourceHistoryButton.frame = CGRect(x: 0, y: 0, width: 22, height: 22)
		sourceHistoryButton.setTitle("🔽", for: .normal)
		sourceHistoryButton.addTarget(self, action: #selector(showSourceHistory), for: .touchUpInside)
		sourceTextField.rightView = sourceHistoryButton
		sourceTextField.rightViewMode = .always

		groupsTableView.register(ChangeGroupCell.self, forCellReuseIdentifier: ChangeGroupCell.reuseIdentifier)
		groupsTableView.register(GroupSectionHeader.self,
		                         forHeaderFooterViewReuseIdentifier: GroupSectionHeader.reuseIdentifier)
		groupsTableView.rowHeight = UITableView.automaticDimension
		groupsTableView.estimatedRowHeight = 100
		groupsTableView.dataSource = self
		groupsTableView.delegate = self

		if #available(iOS 13.0, *) {
			progressView.style = .large
		} else {
			progressView.style = .whiteLarge
		}
	}

	override func viewWillAppear(_ animated: Bool) {
		super.viewWillAppear(animated)

		let mapView = AppDelegate.shared.mapView
		mapData = mapView?.mapData

		commentTextView.text = UserPrefs.shared.uploadComment.value
		sourceTextField.text = UserPrefs.shared.uploadSource.value
		sourceTextField.placeholder = "survey, Bing, knowledge" // overrules translations: see #557
		changesetCommentPlaceholder.isHidden = commentTextView.text.count > 0

		connectedGroups = mapData?.undoManager.connectedObjects() ?? []
		selectedGroupIndices = nearbyGroupIndices()

		let hasGroups = !connectedGroups.isEmpty
		commitButton.isEnabled = hasGroups
		exportOscButton.isEnabled = hasGroups
		editXmlButton.isEnabled = hasGroups

		if !hasGroups {
			let label = UILabel()
			label.text = NSLocalizedString("Nothing to upload, no changes have been made.", comment: "")
			label.textAlignment = .center
			label.numberOfLines = 0
			label.font = UIFont.preferredFont(forTextStyle: .body)
			label.textColor = .secondaryLabel
			groupsTableView.backgroundView = label
		} else {
			groupsTableView.backgroundView = nil
		}

		groupsTableView.reloadData()
		updateDistanceBanner()

		clearCommentButton.isHidden = true
		commentHistoryButton.isHidden = recentCommentList.count == 0
		sourceTextField.rightViewMode = recentSourceList.count > 0 ? .always : .never
	}

	override func viewWillDisappear(_ animated: Bool) {
		super.viewWillDisappear(animated)
		UserPrefs.shared.uploadComment.value = commentTextView.text
		UserPrefs.shared.uploadSource.value = sourceTextField.text
	}

	override func viewDidLayoutSubviews() {
		super.viewDidLayoutSubviews()
		// Keep the tableHeaderView properly sized to fit its Auto Layout content.
		if let banner = distanceBannerView {
			let width = groupsTableView.bounds.width
			let height = banner.systemLayoutSizeFitting(
				CGSize(width: width, height: 0),
				withHorizontalFittingPriority: .required,
				verticalFittingPriority: .fittingSizeLevel
			).height
			if abs(banner.frame.height - height) > 0.5 {
				banner.frame = CGRect(x: 0, y: 0, width: width, height: height)
				groupsTableView.tableHeaderView = banner
			}
		}
	}

	// MARK: - Distance Banner

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
			while parent[x] != x { x = parent[x] }
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

	private func createDistanceBannerView() -> UIView {
		let icon = UIImageView(image: UIImage(systemName: "exclamationmark.triangle.fill"))
		icon.tintColor = .systemOrange
		icon.contentMode = .scaleAspectFit
		icon.setContentHuggingPriority(.required, for: .horizontal)
		icon.setContentCompressionResistancePriority(.required, for: .horizontal)
		icon.translatesAutoresizingMaskIntoConstraints = false
		NSLayoutConstraint.activate([
			icon.widthAnchor.constraint(equalToConstant: 22),
			icon.heightAnchor.constraint(equalToConstant: 22)
		])

		let label = UILabel()
		label.text = NSLocalizedString(
			"Some changes are in a different location and have been deselected. Upload them as a separate changeset.",
			comment: "Warning shown on upload screen when distant edit groups are automatically deselected")
		label.numberOfLines = 0
		label.font = UIFont.preferredFont(forTextStyle: .footnote)
		label.translatesAutoresizingMaskIntoConstraints = false

		let stack = UIStackView(arrangedSubviews: [icon, label])
		stack.axis = .horizontal
		stack.spacing = 8
		stack.alignment = .center
		stack.translatesAutoresizingMaskIntoConstraints = false

		let container = UIView()
		container.backgroundColor = UIColor.systemOrange.withAlphaComponent(0.15)
		container.addSubview(stack)
		NSLayoutConstraint.activate([
			stack.topAnchor.constraint(equalTo: container.topAnchor, constant: 10),
			stack.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -10),
			stack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16),
			stack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -16)
		])
		return container
	}

	private func updateDistanceBanner() {
		if selectedGroupIndices.count < connectedGroups.count {
			if distanceBannerView == nil {
				distanceBannerView = createDistanceBannerView()
			}
			groupsTableView.tableHeaderView = distanceBannerView
		} else {
			distanceBannerView = nil
			groupsTableView.tableHeaderView = nil
		}
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

	private func toggleGroup(at section: Int) {
		if selectedGroupIndices.contains(section) {
			selectedGroupIndices.remove(section)
		} else {
			selectedGroupIndices.insert(section)
		}
		if let header = groupsTableView.headerView(forSection: section) as? GroupSectionHeader {
			header.isChecked = selectedGroupIndices.contains(section)
		}
		let hasSelection = !selectedGroupIndices.isEmpty
		commitButton.isEnabled = hasSelection
		exportOscButton.isEnabled = hasSelection
		editXmlButton.isEnabled = hasSelection
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

	@objc func dismissKeyboard(_ sender: UITextField) {
		sender.resignFirstResponder()
	}

	@IBAction func clearCommentText(_ sender: Any) {
		commentTextView.text = ""
		clearCommentButton.isHidden = true
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
				self.changesetCommentPlaceholder.isHidden = self.commentTextView.text.count > 0
			}))
		}
		actionSheet.addAction(UIAlertAction(title: NSLocalizedString("Cancel", comment: ""),
		                                    style: .cancel,
		                                    handler: nil))
		actionSheet.popoverPresentationController?.sourceView = button
		actionSheet.popoverPresentationController?.sourceRect = button.bounds
		present(actionSheet, animated: true)
	}

	@IBAction func showCommitMessageHistory(_ sender: Any) {
		showHistorySheet(recentCommentList.items, button: commentHistoryButton, textView: commentTextView)
	}

	@IBAction func showSourceHistory(_ sender: Any) {
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
			commitButton.isEnabled = true
			cancelButton.isEnabled = true
			let hasSelection = !selectedGroupIndices.isEmpty
			exportOscButton.isEnabled = hasSelection
			editXmlButton.isEnabled = hasSelection
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

	@IBAction func editXml(_ sender: Any) {
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

	@IBAction func exportOscFile(_ sender: Any) {
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
		activityVC.popoverPresentationController?.sourceView = sender as? UIView
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
			changesetCommentPlaceholder.isHidden = commentTextView.text.count > 0
		}
	}

	func textViewDidBeginEditing(_ textView: UITextView) {
		if textView == commentTextView {
			clearCommentButton.isHidden = commentTextView.text.count == 0
			changesetCommentPlaceholder.isHidden = true
		}
	}

	func textViewDidEndEditing(_ textView: UITextView) {
		if textView == commentTextView {
			clearCommentButton.isHidden = true
			changesetCommentPlaceholder.isHidden = commentTextView.text.count > 0
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
		connectedGroups.count
	}

	func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
		1
	}

	func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
		let cell = tableView.dequeueReusableCell(
			withIdentifier: ChangeGroupCell.reuseIdentifier,
			for: indexPath) as! ChangeGroupCell
		let group = connectedGroups[indexPath.section]
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
		let header = tableView.dequeueReusableHeaderFooterView(
			withIdentifier: GroupSectionHeader.reuseIdentifier) as! GroupSectionHeader
		let group = connectedGroups[section]
		header.configure(title: summaryLabel(for: group),
		                 isChecked: selectedGroupIndices.contains(section),
		                 onTap: { [weak self] in self?.toggleGroup(at: section) })
		return header
	}

	func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
		UITableView.automaticDimension
	}

	func tableView(_ tableView: UITableView, estimatedHeightForHeaderInSection section: Int) -> CGFloat {
		44
	}
}
