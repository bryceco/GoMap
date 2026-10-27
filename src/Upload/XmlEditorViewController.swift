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
			let changesetID = try await mapData.uploadChangeset(.xml(xmlDoc),
			                                                    comment: comment,
			                                                    source: source,
			                                                    imagery: imagery,
			                                                    generator: generator,
			                                                    locale: locale,
			                                                    groupIds: undoGroups)
			navigationController?.dismiss(animated: true, completion: {
				AppDelegate.shared.mapView.setNeedsLayout()
				MessageDisplay.shared.flashMessage(
					title: nil,
					message: String.localizedStringWithFormat(NSLocalizedString("Changes saved in changeset %@", comment: ""),
					                                          String(changesetID)),
					duration: 4.0,
					link: OSM_SERVER.serverURL.appendingPathComponent("changeset/\(changesetID)"))
			})
		} catch let OsmMapData.Error.versionMismatch(
			extId,
			changesetID: changesetID,
			localVersion: localVersion,
			serverVersion: serverVersion)
		{
			// No automatic recovery here: the user is editing the XML by hand
			try? await mapData.closeChangeset(changesetID)
			progressView.stopAnimating()
			commitBarButton.isEnabled = true
			UploadViewController.presentUploadError(vc: self,
			                                        String.localizedStringWithFormat(
			                                        	NSLocalizedString(
			                                        		"Version mismatch for %1$@ %2$@: local version: %3$d, server version: %4$d.",
			                                        		comment: "%1$@ is node/way/relation, %2$@ its ID, %3$d local version, %4$d server version"),
			                                        	extId.type.string, String(extId.ident), localVersion, serverVersion))
		} catch OsmMapData.Error.serverSkippedDelete,
			OsmMapData.Error.serverReturnedUnknownObjectId
		{
			progressView.stopAnimating()
			commitBarButton.isEnabled = true
			UploadViewController.presentUploadError(vc: self,
			                                        NSLocalizedString(
			                                        	"Upload succeeded but the server returned mismatched data.\n\nYou should use Clear Cache > OSM Data before continuing to map.",
			                                        	comment: "'Clear Cache' and 'OSM Data' should match what your language uses for the same terms in Display settings"))
		} catch UrlSessionError.badStatusCode(401, _) {
			OSM_SERVER.oAuth2?.removeAuthorization()
			progressView.stopAnimating()
			commitBarButton.isEnabled = true
			navigationController?.popToRootViewController(animated: true)
		} catch {
			progressView.stopAnimating()
			commitBarButton.isEnabled = true
			UploadViewController.presentUploadError(vc: self,
			                                        error.localizedDescription)
		}
	}
}
