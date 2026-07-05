//
//  PanoramaxServer.swift
//  Go Map!!
//
//  Created by Bryce Cogswell on 7/4/26.
//  Copyright © 2026 Bryce Cogswell. All rights reserved.
//

import UIKit

class PanoramaxServer {
	static let redirect_uri = "gomaposm://panoramax/callback"
	private var authVC: PanoramaxWebViewController?
	let serverURL: URL

	// MARK: - Pending upload queue

	struct PendingUpload: Codable {
		let uploadSetID: String
		let photoID: String
		let tags: [String: String]
	}

	private actor PendingUploadQueue {
		private var uploads: [PendingUpload] = []
		private let defaultsKey = "panoramax.pendingUploads"

		init() {
			if let data = UserDefaults.standard.data(forKey: defaultsKey),
			   let saved = try? JSONDecoder().decode([PendingUpload].self, from: data)
			{
				uploads = saved
			}
		}

		func enqueue(_ upload: PendingUpload) {
			uploads.append(upload)
			save()
		}

		func remove(uploadSetID: String) {
			uploads.removeAll { $0.uploadSetID == uploadSetID }
			save()
		}

		func getAll() -> [PendingUpload] { uploads }

		private func save() {
			if let data = try? JSONEncoder().encode(uploads) {
				UserDefaults.standard.set(data, forKey: defaultsKey)
			}
		}
	}

	private let pendingQueue = PendingUploadQueue()
	private var processingTask: Task<Void, Never>?

	init(serverURL: URL) {
		self.serverURL = serverURL
		// Resume background processing only if there are pending uploads from a previous session
		Task { [weak self] in
			guard let self else { return }
			let uploads = await self.pendingQueue.getAll()
			if !uploads.isEmpty {
				self.startProcessingQueue()
			}
		}
	}

	deinit {
		processingTask?.cancel()
	}

	private func url(withPath path: String, with dict: [String: String]) -> URL {
		let url = serverURL.appendingPathComponent(path)
		var components = URLComponents(url: url,
		                               resolvingAgainstBaseURL: true)!
		components.queryItems = dict.map({ k, v in URLQueryItem(name: k, value: v) })
		return components.url!
	}

	private var authContinuation: CheckedContinuation<Void, Error>?

	// This pops up the Safari page asking the user for login info
	@MainActor
	func authorizeUser(withVC vc: UIViewController) async throws {
		let url = url(withPath: "api/auth/login", with: [
			"client_id": "mzRn5Z-X0nSptHgA3o5g30HeaaljTXfv0GMOLhmwqeo",
			"redirect_uri": Self.redirect_uri,
			"response_type": "code",
			"scope": "read_prefs",
			"state": UUID().uuidString,
			"next_url": Self.redirect_uri
		])

		authVC = PanoramaxWebViewController.create()
		authVC?.modalTransitionStyle = .coverVertical
		authVC?.panoramax = self
		authVC?.url = url
		vc.present(authVC!, animated: true)

		return try await withCheckedThrowingContinuation { cont in
			self.authContinuation = cont
		}
	}

	// Once the user responds to the Safari popup the application is invoked and
	// the app delegate calls this function
	func authRedirectHandler(url: URL, options: [UIApplication.OpenURLOptionsKey: Any]) {
		authVC?.dismiss(animated: true)
		authVC = nil
		authContinuation?.resume(returning: ())
		authContinuation = nil
	}

	func createUploadSet(title: String) async throws -> String {
		let url = serverURL.appendingPathComponent("api/upload_sets")

		// Define the payload
		let payload: [String: Any] = [
			"title": title,
			"estimated_nb_files": 1
		]

		// Convert the payload to JSON data
		let jsonData = try JSONSerialization.data(withJSONObject: payload, options: [])

		// Create the URLRequest
		var request = URLRequest(url: url)
		request.httpMethod = "POST"
		request.setValue("application/json", forHTTPHeaderField: "Content-Type")
		request.httpBody = jsonData
		request.setUserAgent()
		let immutableRequest = request

		let data = try await URLSession.shared.data(with: immutableRequest)
		guard
			let json = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any],
			let uploadSetID = json["id"] as? String
		else {
			throw NSError(domain: "JSON error", code: 0, userInfo: nil)
		}
		return uploadSetID
	}

	/// Creates an upload set, uploads the photo, marks the set complete, and if tags
	/// are provided enqueues the upload for background semantic-tag processing.
	/// Returns the photoID so the caller can update the UI immediately.
	func uploadAndEnqueue(imageData: Data,
	                      name: String,
	                      date: Date,
	                      tags: [String: String]) async throws -> String
	{
		DLog("panoramax: creating upload set")
		let uploadSetID = try await createUploadSet(title: "Go Map!! photo")
		DLog("panoramax: uploading photo")
		let photoID = try await uploadPhoto(set: uploadSetID, data: imageData, name: name, date: date)
		DLog("panoramax: completing upload set")
		try await completeUploadSet(uploadSetID)
		if !tags.isEmpty {
			DLog("panoramax: enqueuing for background tag upload")
			await pendingQueue.enqueue(PendingUpload(uploadSetID: uploadSetID, photoID: photoID, tags: tags))
			startProcessingQueue()
		}
		return photoID
	}

	private func completeUploadSet(_ uploadSetID: String) async throws {
		let url = serverURL.appendingPathComponent("api/upload_sets/\(uploadSetID)/complete")
		var request = URLRequest(url: url)
		request.httpMethod = "POST"
		request.setUserAgent()
		_ = try await URLSession.shared.data(with: request)
	}

	func uploadPhoto(set: String,
	                 data: Data,
	                 name: String,
	                 date: Date) async throws -> String
	{
		let url = serverURL.appendingPathComponent("api/upload_sets/\(set)/files")
		var request = URLRequest(url: url)
		request.setUserAgent()
		request.httpMethod = "POST"

		// Create multipart/form-data boundary
		let boundary = "Boundary-\(UUID().uuidString)"
		request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

		// Create HTTP body
		var body = Data()
		let boundaryPrefix = "--\(boundary)\r\n"

		// Add photo
		body.append(boundaryPrefix.data(using: .utf8)!)
		body.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(name)\"\r\n".data(using: .utf8)!)
		body.append("Content-Type: application/octet-stream\r\n\r\n".data(using: .utf8)!)
		body.append(data)
		body.append("\r\n".data(using: .utf8)!)

		// Add capture time
		body.append("--\(boundary)\r\n".data(using: .utf8)!)
		body.append("Content-Disposition: form-data; name=\"override_capture_time\"\r\n\r\n".data(using: .utf8)!)
		body.append("\(date)\r\n".data(using: .utf8)!)

		body.append("--\(boundary)--\r\n".data(using: .utf8)!)
		request.httpBody = body

		let data = try await URLSession.shared.data(with: request)
		guard let json = try? JSONSerialization.jsonObject(with: data, options: []),
		      let json = json as? [String: Any],
		      let ident = json["picture_id"] as? String
		else {
			throw NSError(domain: "Bad JSON", code: 1)
		}
		return ident
	}

	/// Uploads semantic tags to a collection or a specific photo within it.
	/// If `photoID` is nil, tags are applied to the collection (sequence); otherwise they are applied to the individual photo.
	func uploadSemanticTags(collectionID: String,
	                        photoID: String?,
	                        tags: [String: String]) async throws
	{
		let path = if let photoID {
			"api/collections/\(collectionID)/items/\(photoID)"
		} else {
			"api/collections/\(collectionID)"
		}
		let url = serverURL.appendingPathComponent(path)

		let payload: [String: Any] = [
			"semantics": tags.map { ["key": $0.key, "value": $0.value] }
		]
		let jsonData = try JSONSerialization.data(withJSONObject: payload, options: [])

		var request = URLRequest(url: url)
		request.httpMethod = "PATCH"
		request.setValue("application/json", forHTTPHeaderField: "Content-Type")
		request.httpBody = jsonData
		request.setUserAgent()

		_ = try await URLSession.shared.data(with: request)
	}

	// MARK: - Background queue processing

	private func startProcessingQueue() {
		guard processingTask == nil else { return }
		processingTask = Task.detached(priority: .background) { [weak self] in
			defer {
				if let self { self.processingTask = nil }
			}
			while !Task.isCancelled {
				guard let self else { return }
				let queueEmpty = await self.processPendingUploads()
				if queueEmpty { break }
				do {
					try await Task.sleep(nanoseconds: 10000_000000) // 10 seconds
				} catch {
					break // Task was cancelled during sleep
				}
			}
		}
	}

	// Returns true if the queue is empty after this pass (task can stop).
	private func processPendingUploads() async -> Bool {
		let uploads = await pendingQueue.getAll()
		guard !uploads.isEmpty else { return true }
		DLog("panoramax: checking \(uploads.count) pending upload(s)")
		for upload in uploads {
			do {
				guard let collectionID = try await fetchCollectionID(forUploadSet: upload.uploadSetID) else {
					continue // not ready yet; will retry next poll
				}
				DLog("panoramax: uploading semantic tags for upload set \(upload.uploadSetID)")
				try await uploadSemanticTags(collectionID: collectionID,
				                             photoID: upload.photoID,
				                             tags: upload.tags)
				await pendingQueue.remove(uploadSetID: upload.uploadSetID)
				DLog("panoramax: finished processing upload set \(upload.uploadSetID)")
			} catch {
				DLog("panoramax: error processing pending upload \(upload.uploadSetID): \(error)")
			}
		}
		return await pendingQueue.getAll().isEmpty
	}

	private func fetchCollectionID(forUploadSet uploadSetID: String) async throws -> String? {
		let url = serverURL.appendingPathComponent("api/upload_sets/\(uploadSetID)")
		var request = URLRequest(url: url)
		request.setUserAgent()
		let data = try await URLSession.shared.data(with: request)
		guard let json = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any],
		      let collections = json["associated_collections"] as? [[String: Any]],
		      let collectionID = collections.first?["id"] as? String
		else {
			return nil
		}
		return collectionID
	}
}
