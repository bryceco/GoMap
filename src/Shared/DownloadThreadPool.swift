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
    

	func stream(forUrl url: String, callback: @escaping (_ result: Result<InputStream,Error>) -> Void) {
		let url1 = URL(string: url)!
		var request = URLRequest(url: url1)
		request.httpMethod = "GET"
        request.addValue("8bit", forHTTPHeaderField: "Content-Transfer-Encoding")
        request.cachePolicy = .reloadIgnoringLocalCacheData
        
		inProgress.increment()
        
        let task = urlSession.dataTask(with: request, completionHandler: { [self] data, response, error in
			inProgress.decrement()
			if let error = error {
				DLog("Error: \(error.localizedDescription)")
				callback(.failure(error))
				return
			}

			if let httpResponse = response as? HTTPURLResponse,
			   httpResponse.statusCode >= 400
			{
				DLog("HTTP error \(httpResponse.statusCode): \(HTTPURLResponse.localizedString(forStatusCode: httpResponse.statusCode))")
				DLog("URL: \(url)")
				var text: String = ""
				if let data = data {
					if let dataText = String(data: data, encoding: .utf8) {
						text = dataText
					}
				}
				if text.isEmpty {
					text = HTTPURLResponse.localizedString(forStatusCode: httpResponse.statusCode)
				}
				let error = NSError(domain: "HTTP", code: httpResponse.statusCode, userInfo: [
					NSLocalizedDescriptionKey: text
				])
				callback(.failure(error))
				return
			}

			guard let data = data else {
				callback(.failure(NSError()))
				return
			}

			let inputStream = InputStream(data: data)
			callback(.success(inputStream))
		})
        task.resume()
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
