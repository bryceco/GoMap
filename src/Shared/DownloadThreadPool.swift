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

	func stream(forUrl url: URL) async throws -> InputStream {
		let request = {
			var request = URLRequest(url: url)
			request.httpMethod = "GET"
			request.cachePolicy = .reloadIgnoringLocalCacheData
			request.setUserAgent()
			return request
		}()

		inProgress.increment()
		defer { inProgress.decrement() }

		let data = try await urlSession.data(with: request)
		return InputStream(data: data)
	}

	func cancelAllDownloads() async {
		for task in await urlSession.allTasks {
			task.cancel()
		}
	}

	func downloadsInProgress() -> Int {
		return inProgress.value()
	}
}
