//
//  DownloadThreads.m
//  OpenStreetMap
//
//  Created by Bryce Cogswell on 11/7/12.
//  Copyright (c) 2012 Bryce Cogswell. All rights reserved.
//

import Foundation

@objcMembers
class DownloadThreadPool: NSObject, URLSessionDataDelegate, URLSessionTaskDelegate {
    
    var _urlSession: URLSession?
    var _downloadCount: AtomicInt
    
    override init() {
		_downloadCount = AtomicInt(0)
        super.init()
        let config = URLSessionConfiguration.default
        _urlSession = URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }
    
    static var pool = DownloadThreadPool()
    
    class func osmPool() -> DownloadThreadPool {
        return pool
    }
    
    func stream(forUrl url: String, callback: @escaping (_ stream: InputStream?, _ error: Error?) -> Void) {
        var request: URLRequest? = nil
        if let url1 = URL(string: url) {
            request = URLRequest(url: url1)
        }
        request?.httpMethod = "GET"
        request?.addValue("8bit", forHTTPHeaderField: "Content-Transfer-Encoding")
        request?.cachePolicy = .reloadIgnoringLocalCacheData
        
		_downloadCount.increment()
        
        var task: URLSessionDataTask? = nil
        if let request = request {
            task = _urlSession?.dataTask(with: request, completionHandler: { [self] data, response, error in
				_downloadCount.decrement()
                var data = data
                var error = error
                let httpResponse = response as? HTTPURLResponse
                if let error = error {
                    DLog("Error: \(error.localizedDescription)")
                    data = nil
                } else if (httpResponse != nil) && (httpResponse?.statusCode ?? 0) >= 400 {
                    DLog("HTTP error \(httpResponse?.statusCode ?? 0): \(HTTPURLResponse.localizedString(forStatusCode: httpResponse?.statusCode ?? 0))")
                    DLog("URL: \(url)")
                    var text: String? = nil
                    if let data = data {
                        text = String(data: data, encoding: .utf8)
                    }
                    if (text?.count ?? 0) == 0 {
                        text = HTTPURLResponse.localizedString(forStatusCode: httpResponse?.statusCode ?? 0)
                    }
                    error = NSError(domain: "HTTP", code: httpResponse?.statusCode ?? 0, userInfo: [
                        NSLocalizedDescriptionKey: text ?? ""
                    ])
                    data = nil
                }
                
                if data != nil && error == nil {
                    var inputStream: InputStream? = nil
                    if let data = data {
                        inputStream = InputStream(data: data)
                    }
                    callback(inputStream, nil)
                } else {
                    callback(nil, error!)
                }
            })
        }
        task?.resume()
    }
    
    func cancelAllDownloads() {
        _urlSession?.getAllTasks(completionHandler: { tasks in
            for task in tasks {
                task.cancel()
            }
        })
    }
    
    func downloadsInProgress() -> Int {
		return _downloadCount.value()
    }
}
