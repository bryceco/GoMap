//
//  DownloadThreads.m
//  OpenStreetMap
//
//  Created by Bryce Cogswell on 11/7/12.
//  Copyright (c) 2012 Bryce Cogswell. All rights reserved.
//

import Foundation

final class DownloadThreadPool: NSObject, URLSessionDataDelegate, URLSessionTaskDelegate {
	var urlSession: URLSession!
	var inProgress: AtomicInt

	override init() {
		inProgress = AtomicInt(0)
		super.init()

		// Since we do our own caching we use an ephemeral configuration, which
		// uses no persistent storage for caches, cookies, or credentials.
		// This prevents the systems from duplicating our own caching efforts.
		let config = URLSessionConfiguration.ephemeral
		urlSession = URLSession(configuration: config, delegate: self, delegateQueue: nil)
	}

	static let osmPool = DownloadThreadPool()

	func stream(forUrl url: String, callback: @escaping (_ result: Result<InputStream, Error>) -> Void) {
		let url1 = URL(string: url)!
		var request = URLRequest(url: url1)
		request.httpMethod = "GET"
		request.addValue("8bit", forHTTPHeaderField: "Content-Transfer-Encoding")
		request.cachePolicy = .reloadIgnoringLocalCacheData

		inProgress.increment()

		urlSession.data(with: request, completionHandler: { [self] result in
			inProgress.decrement()
			switch result {
			case let .success(data):
				let inputStream = InputStream(data: data)
				callback(.success(inputStream))
			case let .failure(error):
				callback(.failure(error))
			}
		})
	}

	func cancelAllDownloads() {
		urlSession.getAllTasks(completionHandler: { tasks in
			for task in tasks {
				task.cancel()
			}
		})
	}

	func downloadsInProgress() -> Int {
		return inProgress.value()
	}
}
