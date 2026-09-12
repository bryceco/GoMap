//
//  XmlEditorViewController.swift
//  Go Map!!
//
//  Created by Bryce Cogswell on 9/11/26.
//  Copyright © 2026 Bryce Cogswell. All rights reserved.
//

import KissXML
import UIKit

/// Pushed from UploadViewController when the user taps "Edit XML".
/// Presents the raw osmChange XML for the selected groups in an editable text view
/// and uploads it via openChangesetAndUpload on commit.
final class XmlEditorViewController: UIViewController {
	var mapData: OsmMapData!
	var xmlText: String = ""
	var comment: String = ""
	var source: String = ""
	var imagery: String = ""
	var generator: String = ""
	var locale: String = ""
	var undoGroups: Set<Int> = []

	private let textView = UITextView()
	private var commitBarButton: UIBarButtonItem!
	private let progressView = UIActivityIndicatorView(style: .medium)
	private var alertShown = false

	override func viewDidLoad() {
		super.viewDidLoad()
		title = NSLocalizedString("Edit XML", comment: "")
		view.backgroundColor = .systemBackground

		progressView.hidesWhenStopped = true
		commitBarButton = UIBarButtonItem(
			title: NSLocalizedString("Commit", comment: ""),
			style: .done,
			target: self,
			action: #selector(commitTapped))
		navigationItem.rightBarButtonItems = [
			commitBarButton,
			UIBarButtonItem(customView: progressView)
		]

		textView.font = UIFont.monospacedSystemFont(ofSize: 12, weight: .regular)
		textView.autocorrectionType = .no
		textView.spellCheckingType = .no
		textView.translatesAutoresizingMaskIntoConstraints = false
		view.addSubview(textView)
		NSLayoutConstraint.activate([
			textView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
			textView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
			textView.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
			textView.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor)
		])
		textView.text = xmlText
	}

	override func viewDidAppear(_ animated: Bool) {
		super.viewDidAppear(animated)
		guard !alertShown else { return }
		alertShown = true
		let alert = UIAlertController(
			title: NSLocalizedString("Edit XML", comment: ""),
			message: NSLocalizedString(
				"Modifying the raw XML data allows you to correct errors that prevent uploading.\n\nIt is an advanced operation that should only be undertaken if you have a thorough understanding of the OSM changeset format.",
				comment: ""),
			preferredStyle: .alert)
		alert.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: ""), style: .cancel))
		present(alert, animated: true)
	}

	@objc private func commitTapped() {
		Task { @MainActor in await performCommit() }
	}

	@MainActor
	private func performCommit() async {
		progressView.startAnimating()
		commitBarButton.isEnabled = false

		do {
			let xmlDoc = try DDXMLDocument(xmlString: textView.text ?? "", options: 0)
			try await mapData.uploadChangeset(.xml(xmlDoc),
			                                  comment: comment,
			                                  source: source,
			                                  imagery: imagery,
			                                  generator: generator,
			                                  locale: locale,
			                                  groupIds: undoGroups)
			navigationController?.dismiss(animated: true)
			let appDelegate = AppDelegate.shared
			MainActor.runAfter(nanoseconds: 300_000000) {
				appDelegate.mapView.setNeedsLayout()
				MessageDisplay.shared.flashMessage(
					title: nil,
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
			commitBarButton.isEnabled = true
			navigationController?.popToRootViewController(animated: true)
		} catch {
			progressView.stopAnimating()
			commitBarButton.isEnabled = true
			let alert = UIAlertController(
				title: NSLocalizedString("Unable to upload changes", comment: ""),
				message: error.localizedDescription,
				preferredStyle: .alert)
			alert.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: ""), style: .cancel))
			present(alert, animated: true)
		}
	}
}
