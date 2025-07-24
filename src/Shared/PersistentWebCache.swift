//
//  PersistentWebCache.swift
//  Go Map!!
//
//  Created by Bryce on 5/3/20.
//  Copyright © 2020 Bryce Cogswell. All rights reserved.
//

import Foundation

enum WebCacheError: LocalizedError {
	case objectForDataFailure
	case urlFunctionFailure

	public var errorDescription: String? {
		switch self {
		case .objectForDataFailure: return "objectForData() failed"
		case .urlFunctionFailure: return "urlFunction() failed"
		}
	}
}

final class PersistentWebCache<T: AnyObject> {
	private let cacheDirectory: URL
	private let memoryCache: NSCache<NSString, T>
	// Track objects we're already downloading so we don't issue duplicate requests.
	// Each object has a list of completions to call when it becomes available.
	private var pending: [String: [(Result<T, Error>) -> Void]]

	class func encodeKey(forFilesystem string: String) -> String {
		var string = string
		let allowed = CharacterSet(charactersIn: "/").inverted
		string = string.addingPercentEncoding(withAllowedCharacters: allowed) ?? string
		return string
	}

	func fileList(withAttributes attr: [URLResourceKey]) -> [URL] {
		let fm = FileManager.default
		let options: FileManager.DirectoryEnumerationOptions = [.skipsSubdirectoryDescendants,
		                                                        .skipsPackageDescendants,
		                                                        .skipsHiddenFiles]
		let list = try? fm.contentsOfDirectory(at: cacheDirectory,
		                                       includingPropertiesForKeys: attr,
		                                       options: options)
		return list ?? []
	}

	func allKeys() -> [String] {
		var a: [String] = []
		for url in fileList(withAttributes: []) {
			let s = url.lastPathComponent // automatically removes escape encoding
			a.append(s)
		}
		return a
	}

	init(name: String, memorySize: Int, daysToKeep: Double) {
		let name = PersistentWebCache.encodeKey(forFilesystem: name)
		cacheDirectory = ArchivePath.webCache(name).url()
		memoryCache = NSCache<NSString, T>()
		memoryCache.countLimit = 1000
		memoryCache.totalCostLimit = memorySize
		pending = [:]

		try? FileManager.default.createDirectory(
			at: cacheDirectory,
			withIntermediateDirectories: true,
			attributes: nil)

		removeObjectsAsyncOlderThan(Date(timeIntervalSinceNow: -daysToKeep * 24 * 60 * 60))
	}

	func resetMemoryCache() {
		memoryCache.removeAllObjects()
	}

	func removeAllObjects() {
		for url in fileList(withAttributes: []) {
			try? FileManager.default.removeItem(at: url)
		}
		memoryCache.removeAllObjects()
	}

	private func removeObjectsAsyncOlderThan(_ expiration: Date) {
		Task(priority: .background) {
			for url in fileList(withAttributes: [.contentModificationDateKey]) {
				if let date = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate,
				   date < expiration
				{
					try? FileManager.default.removeItem(at: url)
				}
			}
		}
	}

	func getDiskCacheSize() async -> (size: Int, count: Int) {
		var count = 0
		var size = 0
		for url in fileList(withAttributes: [URLResourceKey.fileAllocatedSizeKey]) {
			let url = url as NSURL
			var len: AnyObject?
			try? url.getResourceValue(&len, forKey: URLResourceKey.fileAllocatedSizeKey)
			count += 1
			if let len = len as? NSNumber {
				size += len.intValue
			}
		}
		return (size, count)
	}

	/// Call this function to retrieve an object with a specified cacheKey, downloading and caching the object if it doesn't exist.
	/// If the object already exists in the memory cache it will be returned synchronously.
	/// If the object is not in memory:
	/// - nil will be returned synchronously
	/// - it will looked for in the disk cache asynchronously, and if found converted from Data to the appropriate return type by objectForData()
	/// If the object is not on disk:
	/// - the URL for the object is calculated by fallbackURL() and
	/// - the object is downloaded and stored on disk, converted to type T via objectForData(), and returned via completion()
	/// If the object is not available on disk or at the URL an error is returned via completion()
	func object(
		withKey cacheKey: String,
		fallbackURL urlFunction: @escaping () -> URL?,
		objectForData: @escaping (_ data: Data) -> T?,
		completion: @escaping (_ result: Result<T, Error>) -> Void) -> T?
	{
		DbgAssert(Thread.isMainThread) // since we update our data structures on the main thread we need this true
		assert(memoryCache.totalCostLimit != 0)
		if let cachedObject = memoryCache.object(forKey: cacheKey as NSString) {
			return cachedObject
		}

		if var plist = pending[cacheKey] {
			// already being downloaded
			plist.append(completion)
			pending[cacheKey] = plist
			return nil
		}
		pending[cacheKey] = [completion]

		// this function must be called along every path at some point, in order to call
		// completions of our callee
		func processData(_ result: Result<Data, Error>) -> Bool {
			let r: Result<T, Error>
			var size = -1
			switch result {
			case let .success(data):
				if let obj = objectForData(data) {
					size = data.count
					r = .success(obj)
				} else {
					r = .failure(WebCacheError.objectForDataFailure)
				}
			case let .failure(error):
				r = .failure(error)
			}
			DispatchQueue.main.async(execute: {
				if let obj = try? r.get() {
					self.memoryCache.setObject(obj,
					                           forKey: cacheKey as NSString,
					                           cost: size)
				}
				for completion in self.pending[cacheKey] ?? [] {
					completion(r)
				}
				self.pending.removeValue(forKey: cacheKey)
			})
			return size >= 0
		}

		Task(priority: .medium) {
			// check disk cache
			let fileName = PersistentWebCache.encodeKey(forFilesystem: cacheKey)
			let filePath = cacheDirectory.appendingPathComponent(fileName)
			if let data = try? Data(contentsOf: filePath) {
				_ = processData(.success(data))
			} else {
				// fetch from server
				guard let url = urlFunction() else {
					_ = processData(.failure(WebCacheError.urlFunctionFailure))
					return
				}

				let result: Result<Data, Error>
				do {
					let data = try await URLSession.shared.data(with: url)
					result = .success(data)
				} catch {
					result = .failure(error)
				}
				if processData(result),
				   let data = try? result.get()
				{
					Task(priority: .medium) {
						(data as NSData).write(to: filePath, atomically: true)
					}
				}
			}
		}
		return nil
	}
}
