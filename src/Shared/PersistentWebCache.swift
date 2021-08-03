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
	// track objects we're already downloading so we don't issue multiple requests
	private var pending: [String: [(Result<T, Error>) -> Void]]

	class func encodeKey(forFilesystem string: String) -> String {
		var string = string
		let allowed = CharacterSet(charactersIn: "/").inverted
		string = string.addingPercentEncoding(withAllowedCharacters: allowed) ?? string
		return string
	}

	func fileEnumerator(withAttributes attr: [URLResourceKey]) -> FileManager.DirectoryEnumerator {
		return FileManager.default.enumerator(
			at: cacheDirectory,
			includingPropertiesForKeys: attr,
			options: [.skipsSubdirectoryDescendants, .skipsPackageDescendants, .skipsHiddenFiles],
			errorHandler: nil)!
	}

	func allKeys() -> [String] {
		var a: [String] = []
		for url in fileEnumerator(withAttributes: []) {
			guard let url = url as? URL else {
				continue
			}
			let s = url.lastPathComponent // automatically removes escape encoding
			a.append(s)
		}
		return a
	}

	init(name: String, memorySize: Int) {
		let name = PersistentWebCache.encodeKey(forFilesystem: name)
		let bundleName = Bundle.main.infoDictionary?["CFBundleIdentifier"] as! String
		cacheDirectory = try! FileManager.default.url(
			for: .cachesDirectory,
			in: .userDomainMask,
			appropriateFor: nil,
			create: true).appendingPathComponent(bundleName, isDirectory: true)
			.appendingPathComponent(name, isDirectory: true)

		memoryCache = NSCache<NSString, T>()
		memoryCache.countLimit = 1000
		memoryCache.totalCostLimit = memorySize

		pending = [:]

		try? FileManager.default.createDirectory(
			at: cacheDirectory,
			withIntermediateDirectories: true,
			attributes: nil)
	}

	func removeAllObjects() {
		for url in fileEnumerator(withAttributes: []) {
			guard let url = url as? URL else {
				continue
			}
			do {
				try FileManager.default.removeItem(at: url)
			} catch {}
		}
		memoryCache.removeAllObjects()
	}

	func removeObjectsAsyncOlderThan(_ expiration: Date) {
		DispatchQueue.global(qos: .background).async(execute: { [self] in
			for url in fileEnumerator(withAttributes: [.contentModificationDateKey]) {
				if let url = url as? URL,
				   let date = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate,
				   date < expiration
				{
					try? FileManager.default.removeItem(at: url)
				}
			}
		})
	}

	func getDiskCacheSize(_ pSize: UnsafeMutablePointer<Int>, count pCount: UnsafeMutablePointer<Int>) {
		var count = 0
		var size = 0
		for url in fileEnumerator(withAttributes: [URLResourceKey.fileAllocatedSizeKey]) {
			guard let url = url as? NSURL else {
				continue
			}
			var len: AnyObject?
			try? url.getResourceValue(&len, forKey: URLResourceKey.fileAllocatedSizeKey)
			count += 1
			if let len = len as? NSNumber {
				size += len.intValue
			}
		}
		pSize.pointee = size
		pCount.pointee = count
	}

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

		if let plist = pending[cacheKey] {
			// already being downloaded
			pending[cacheKey] = plist + [completion]
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
				if case let .success(obj) = r {
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

		DispatchQueue.global(qos: .default).async(execute: { [self] in
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
				URLSession.shared.data(with: url, completionHandler: { result in
					if processData(result),
					   case let .success(data) = result
					{
						DispatchQueue.global(qos: .default).async(execute: {
							(data as NSData).write(to: filePath, atomically: true)
						})
					}
				})
			}
		})
		return nil
	}
}
