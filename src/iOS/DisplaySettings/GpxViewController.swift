//
//  GpxViewController.swift
//  Go Map!!
//
//  Created by Bryce Cogswell on 2/26/13.
//  Copyright (c) 2013 Bryce Cogswell. All rights reserved.
//

import UIKit

class GpxTrackTableCell: UITableViewCell, UIActionSheetDelegate {
	@IBOutlet var startDate: UILabel!
	@IBOutlet var duration: UILabel!
	@IBOutlet var details: UILabel!
	@IBOutlet var uploadButton: UIButton!
	var gpxTrack = GpxTrack()
	var tableView: GpxViewController?

	@IBAction func doAction(_ sender: Any) {
		let alert = UIAlertController(
			title: NSLocalizedString("Share", comment: "Title for sharing options"),
			message: nil,
			preferredStyle: .actionSheet)
		alert.addAction(UIAlertAction(title: NSLocalizedString("Cancel", comment: ""), style: .cancel, handler: nil))
		alert.addAction(UIAlertAction(title: NSLocalizedString("Upload to OSM", comment: ""),
		                              style: .default,
		                              handler: { _ in
		                              	self.tableView?.share(self.gpxTrack)
		                              }))
		alert.addAction(UIAlertAction(
			title: NSLocalizedString("Share", comment: "Open iOS sharing sheet"),
			style: .default, handler: { _ in
				let creationDate = self.gpxTrack.creationDate
				let appName = AppDelegate.shared.appName()
				let fileName = "\(appName) \(creationDate).gpx"

				// get a copy of GPX as a string
				guard let gpx = self.gpxTrack.gpxXmlString() else { return }

				// create a temporary file and write the gpx to it
				let fileUrl = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
				try? FileManager.default.removeItem(at: fileUrl)
				guard (try? gpx.write(to: fileUrl, atomically: true, encoding: .utf8)) != nil else {
					return
				}

				// Create the share activity
				let controller = UIActivityViewController(activityItems: [fileName, fileUrl] as [Any],
				                                          applicationActivities: nil)
				controller.completionWithItemsHandler = { _, completed, _, _ in
					if completed {
						let gpxLayer = AppDelegate.shared.mapView.gpxLayer
						gpxLayer.markTrackUploaded(self.gpxTrack)
						self.tableView?.tableView.reloadData()
					}
				}

				// Preset the share sheet to the user
				self.tableView?.present(controller, animated: true)
			}))

		// set location of popup
		let button = sender as? UIButton
		alert.popoverPresentationController?.sourceView = button
		alert.popoverPresentationController?.sourceRect = button?.bounds ?? CGRect.zero

		tableView?.present(alert, animated: true)
	}
}

class GpxTrackBackgroundCollection: UITableViewCell {
	@IBOutlet var enableBackground: UISwitch!

	@IBAction func enableBackground(_ sender: Any) {
		let toggle = sender as? UISwitch
		let appDelegate = AppDelegate.shared
		appDelegate.mapView.gpsInBackground = toggle?.isOn ?? false
	}
}

class GpxTrackImportHealthKit: UITableViewCell {
	@IBOutlet var importButton: UIButton!
	@IBOutlet var activityIndicator: UIActivityIndicatorView!
	var vc: UIViewController!

	@IBAction func importHealthKitRoutes(_ sender: Any) {
		activityIndicator.isHidden = false
		activityIndicator.startAnimating()
		HealthKitRoutes.shared.getWorkoutRoutes { result in
			self.activityIndicator.stopAnimating()
			self.activityIndicator.isHidden = true
			switch result {
			case let .failure(error):
				let alert = UIAlertController(title: NSLocalizedString("HealthKit", comment: "iOS HealthKit framework"),
				                              message: error.localizedDescription,
				                              preferredStyle: .alert)
				alert.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: ""),
												style: .default,
												handler: nil))
				self.vc.present(alert, animated: true)
			case let .success(routes):
				let origCount = AppDelegate.shared.mapView.gpxLayer.previousTracks.count
				for route in routes {
					let gpx = GpxTrack()
					gpx.name = "HealthKit"
					for point in route {
						gpx.addPoint(point)
					}
					gpx.finish()
					AppDelegate.shared.mapView.gpxLayer.addGPX(track: gpx, center: false)
				}
				if let tableView = self.vc.view as? UITableView {
					tableView.reloadData()
				}
				let newCount = AppDelegate.shared.mapView.gpxLayer.previousTracks.count - origCount
				let message = NSLocalizedString(
					"\(newCount) new route(s) imported,\n\(routes.count - newCount) duplicate(s) skipped",
					comment: "")
				let alert = UIAlertController(title: NSLocalizedString("HealthKit", comment: "iOS HealthKit framework"),
				                              message: message,
				                              preferredStyle: .alert)
				alert.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: ""),
												style: .default,
												handler: nil))
				self.vc.present(alert, animated: true)
			}
		}
	}
}

class GpxTrackExpirationCell: UITableViewCell {
	@IBOutlet var expirationButton: UIButton!
}

class GpxViewController: UITableViewController {
	private var timer: Timer?
	@IBOutlet var navigationBar: UINavigationBar!

	@IBAction func cancel(_ sender: Any) {
		dismiss(animated: true)
	}

	func share(_ track: GpxTrack) {
		let progress = UIAlertController(
			title: NSLocalizedString("Uploading GPX...", comment: ""),
			message: NSLocalizedString("Please wait", comment: ""),
			preferredStyle: .alert)
		present(progress, animated: true)

		// let progress window display before we submit work
		DispatchQueue.main.async(execute: {
			let url = OSM_API_URL + "api/0.6/gpx/create"

			guard var request = AppDelegate.shared.oAuth2.urlRequest(string: url) else { return }
			let boundary = "----------------------------d10f7aa230e8"
			request.httpMethod = "POST"
			let contentType = "multipart/form-data; boundary=\(boundary)"
			request.setValue(contentType, forHTTPHeaderField: "Content-Type")
			request.setValue("close", forHTTPHeaderField: "Connection")

			let dateFormatter = DateFormatter()
			dateFormatter.dateFormat = "yyyy_MM_dd__HH_mm_ss"
			let startDateFile = dateFormatter.string(from: track.creationDate)
			let startDateFriendly = DateFormatter.localizedString(
				from: track.creationDate,
				dateStyle: .short,
				timeStyle: .short)

			var body = ""
			body += "--\(boundary)\r\n"
			body += "Content-Disposition: form-data; name=\"file\"; filename=\"GoMap__\(startDateFile).gpx\"\r\n"
			body += "Content-Type: application/octet-stream\r\n\r\n"
			body += track.gpxXmlString()!
			body += "\r\n--\(boundary)\r\n"
			body += "Content-Disposition: form-data; name=\"description\"\r\n\r\n"
			body += "Go Map!! \(startDateFriendly)"
			body += "\r\n--\(boundary)\r\n"
			body += "Content-Disposition: form-data; name=\"tags\"\r\n\r\n"
			body += "GoMap"
			body += "\r\n--\(boundary)\r\n"
			body += "Content-Disposition: form-data; name=\"public\"\r\n\r\n"
			body += "1"
			body += "\r\n--\(boundary)\r\n"
			body += "Content-Disposition: form-data; name=\"visibility\"\r\n\r\n"
			body += "public"
			body += "\r\n--\(boundary)--\r\n"
			request.httpBody = body.data(using: .utf8)
			request.setValue(String(format: "%ld", body.count), forHTTPHeaderField: "Content-Length")

			URLSession.shared.data(with: request, completionHandler: { result in
				DispatchQueue.main.async(execute: {
					progress.dismiss(animated: true)

					switch result {
					case .success:
						let success = UIAlertController(
							title: NSLocalizedString("GPX Upload Complete", comment: ""),
							message: nil,
							preferredStyle: .alert)
						success.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: ""),
						                                style: .cancel,
						                                handler: nil))
						self.present(success, animated: true)

						// mark track as uploaded in UI
						let gpxLayer = AppDelegate.shared.mapView.gpxLayer
						gpxLayer.markTrackUploaded(track)
						self.tableView?.reloadData()
					case let .failure(error):
						let failure = UIAlertController(
							title: NSLocalizedString("GPX Upload Failed", comment: ""),
							message: "\(error.localizedDescription)",
							preferredStyle: .alert)
						failure.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: ""),
						                                style: .cancel,
						                                handler: nil))
						self.present(failure, animated: true)
					}
				})
			})
		})
	}

	override func viewDidLoad() {
		super.viewDidLoad()

		tableView?.estimatedRowHeight = 44
		tableView?.rowHeight = UITableView.automaticDimension

		navigationItem.rightBarButtonItem = editButtonItem

		AppDelegate.shared.mapView.gpxLayer.loadTracksInBackground(withProgress: {
			self.tableView?.reloadData()
		})
	}

	override func viewDidAppear(_ animated: Bool) {
		super.viewDidAppear(animated)

		if let track = AppDelegate.shared.mapView.gpxLayer.activeTrack {
			startTimer(forStart: track.creationDate)
		}
	}

	override func viewWillDisappear(_ animated: Bool) {
		super.viewWillDisappear(animated)
		timer?.invalidate()
		timer = nil
	}

	func startTimer(forStart date: Date) {
		let now = Date()
		var delta = now.timeIntervalSince(date)
		delta = 1 - fmod(delta, 1.0)
		let date = now.addingTimeInterval(delta)
		timer = Timer(fire: date, interval: 1.0, repeats: true, block: { [weak self] timer in
			guard let self = self else { return }
			if AppDelegate.shared.mapView.gpxLayer.activeTrack != nil {
				let index = IndexPath(row: 0, section: SECTION_ACTIVE_TRACK)
				self.tableView?.reloadRows(at: [index], with: .none)
			} else {
				timer.invalidate()
				self.timer = nil
			}
		})
		RunLoop.current.add(timer!, forMode: .default)
	}

	// MARK: - Table view data source

	override func numberOfSections(in tableView: UITableView) -> Int {
		return 3
	}

	override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
		if section == SECTION_ACTIVE_TRACK {
			// active track
			return 1
		} else if section == SECTION_PREVIOUS_TRACKS {
			// previous tracks
			return AppDelegate.shared.mapView.gpxLayer.previousTracks.count
		} else if section == SECTION_CONFIGURE {
			// configuration
			return 3
		} else {
			return 0
		}
	}

	override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
		switch section {
		case SECTION_ACTIVE_TRACK:
			return NSLocalizedString("Current Track", comment: "current GPX track")
		case SECTION_PREVIOUS_TRACKS:
			return NSLocalizedString("Previous Tracks", comment: "previous GPX track")
		case SECTION_CONFIGURE:
			return NSLocalizedString("Configure", comment: "")
		default:
			return nil
		}
	}

	override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
		if section == SECTION_ACTIVE_TRACK {
			return NSLocalizedString("A GPX Track records your path as you travel along a road or trail", comment: "")
		}
		return nil
	}

	override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
		let mapView = AppDelegate.shared.mapView!
		let gpxLayer = mapView.gpxLayer

		if indexPath.section == SECTION_ACTIVE_TRACK, gpxLayer.activeTrack == nil {
			// no active track
			let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
			cell.textLabel?.text = NSLocalizedString("No active track", comment: "GPX track")
			return cell
		}
		if indexPath.section == SECTION_CONFIGURE {
			// configuration section
			switch indexPath.row {
			case 0:
				// days before deleting
				let cell = tableView.dequeueReusableCell(
					withIdentifier: "GpxTrackExpirationCell",
					for: indexPath) as! GpxTrackExpirationCell
				let expirationDays = GpxLayer.expirationDays
				let expiration = expirationDays
				let title = expiration <= 0 ? NSLocalizedString("Never", comment: "Never delete old tracks") : String
					.localizedStringWithFormat(
						NSLocalizedString("%ld Days", comment: "One or more days"),
						expiration)
				cell.expirationButton.setTitle(title, for: .normal)
				cell.expirationButton.sizeToFit()
				return cell
			case 1:
				// enable background use
				let cell = tableView.dequeueReusableCell(
					withIdentifier: "GpxTrackBackgroundCollection",
					for: indexPath) as! GpxTrackBackgroundCollection
				cell.enableBackground.isOn = mapView.gpsInBackground
				return cell
			case 2:
				// HealthKit support
				let cell = tableView.dequeueReusableCell(
					withIdentifier: "GpxTrackImportHealthKit",
					for: indexPath) as! GpxTrackImportHealthKit
				cell.activityIndicator.isHidden = true
				cell.vc = self
				return cell
			default:
				assertionFailure()
			}
		}

		// active track or previous tracks
		let track = indexPath.section == SECTION_ACTIVE_TRACK ? gpxLayer.activeTrack!
			: gpxLayer.previousTracks[indexPath.row]
		let startDate = DateFormatter.localizedString(from: track.creationDate, dateStyle: .short, timeStyle: .short)
		let dur = Int(round(track.duration()))
		let duration = String(format: "%d:%02d:%02d", dur / 3600, dur / 60 % 60, dur % 60)
		let subtitle: String
		if track.wayPoints.count > 0 {
			subtitle = String.localizedStringWithFormat(
				NSLocalizedString("%ld meters, %ld points, %ld waypoints", comment: "length of a gpx track"),
				Int(track.lengthInMeters()),
				track.points.count,
				track.wayPoints.count)
		} else {
			subtitle = String.localizedStringWithFormat(
				NSLocalizedString("%ld meters, %ld points", comment: "length of a gpx track"),
				Int(track.lengthInMeters()),
				track.points.count)
		}
		let cell = tableView.dequeueReusableCell(
			withIdentifier: "GpxTrackTableCell",
			for: indexPath) as! GpxTrackTableCell
		cell.startDate.text = startDate
		cell.duration.text = duration
		cell.details.text = subtitle
		cell.gpxTrack = track
		cell.tableView = self
		let name = track.name
		if gpxLayer.uploadedTracks[name] != nil {
			cell.uploadButton.setImage(nil, for: .normal)
			cell.uploadButton.setTitle("\u{2714}", for: .normal)
		} else {
			let image = UIImage(named: "702-share")
			cell.uploadButton.setImage(image, for: .normal)
			cell.uploadButton.setTitle(nil, for: .normal)
		}
		return cell
	}

	// Override to support conditional editing of the table view.
	override func tableView(_ tableView: UITableView, canEditRowAt indexPath: IndexPath) -> Bool {
		return indexPath.section == SECTION_PREVIOUS_TRACKS
	}

	// Override to support editing the table view.
	override func tableView(
		_ tableView: UITableView,
		commit editingStyle: UITableViewCell.EditingStyle,
		forRowAt indexPath: IndexPath)
	{
		if editingStyle == .delete {
			// Delete the row from the data source
			let gpxLayer = AppDelegate.shared.mapView.gpxLayer
			let track = gpxLayer.previousTracks[indexPath.row]
			gpxLayer.delete(track)

			tableView.deleteRows(at: [indexPath], with: .fade)
		} else if editingStyle == .insert {
			// Create a new instance of the appropriate class, insert it into the array, and add a new row to the table view
		}
	}

	// MARK: - Table view delegate

	override func tableView(_ tableView: UITableView, willSelectRowAt indexPath: IndexPath) -> IndexPath? {
		if indexPath.section == SECTION_CONFIGURE {
			return nil
		}
		if indexPath.section == SECTION_ACTIVE_TRACK, AppDelegate.shared.mapView.gpxLayer.activeTrack == nil {
			// don't allow selecting the active track if there is none
			return nil
		}
		return indexPath
	}

	override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
		if indexPath.section == SECTION_ACTIVE_TRACK {
			// active track
			let gpxLayer = AppDelegate.shared.mapView.gpxLayer
			gpxLayer.selectedTrack = gpxLayer.activeTrack
			if let selectedTrack = gpxLayer.selectedTrack {
				gpxLayer.center(on: selectedTrack)
			}
			navigationController?.dismiss(animated: true)
		} else if indexPath.section == SECTION_CONFIGURE {
			// configuration
		} else if indexPath.section == SECTION_PREVIOUS_TRACKS {
			let gpxLayer = AppDelegate.shared.mapView.gpxLayer
			let track = gpxLayer.previousTracks[indexPath.row]
			gpxLayer.selectedTrack = track
			gpxLayer.center(on: track)
			AppDelegate.shared.mapView.displayGpxLogs = true
			navigationController?.dismiss(animated: true)
		}
	}

	// MARK: - Navigation

	// In a storyboard-based application, you will often want to do a little preparation before navigation
	override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
		if let dest = segue.destination as? GpxConfigureViewController {
			dest.expirationValue = GpxLayer.expirationDays
			dest.completion = { pick in
				GpxLayer.expirationDays = pick

				if pick > 0 {
					let cutoff = Date(timeIntervalSinceNow: TimeInterval(-pick * 24 * 60 * 60))
					AppDelegate.shared.mapView.gpxLayer.trimTracksOlderThan(cutoff)
				}
				self.tableView?.reloadData()
			}
		}
	}
}

let SECTION_CONFIGURE = 0
let SECTION_ACTIVE_TRACK = 1
let SECTION_PREVIOUS_TRACKS = 2
