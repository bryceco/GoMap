//
//  PersistentWebCache.swift
//  Go Map!!
//
//  Created by Bryce on 5/3/20.
//  Copyright © 2020 Bryce Cogswell. All rights reserved.
//

import Foundation

final class PersistentWebCache<T: AnyObject> {
	private let _cacheDirectory: URL
	private let _memoryCache: NSCache<NSString, T>
	private var _pending: [String: [(T?) -> Void]] // track objects we're already downloading so we don't issue multiple requests

	class func encodeKey(forFilesystem string: String) -> String {
		var string = string
		let allowed = CharacterSet(charactersIn: "/").inverted
		string = string.addingPercentEncoding(withAllowedCharacters: allowed) ?? ""
		return string
	}

	func fileEnumerator(withAttributes attr: [URLResourceKey]) -> FileManager.DirectoryEnumerator {
		return FileManager.default.enumerator(
			at: _cacheDirectory,
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
		let bundleName = Bundle.main.infoDictionary?["CFBundleIdentifier"] as? String
		_cacheDirectory = try! FileManager.default.url(for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: true).appendingPathComponent(bundleName ?? "", isDirectory: true).appendingPathComponent(name, isDirectory: true)

		_memoryCache = NSCache<NSString, T>()
		_memoryCache.countLimit = 10000
		_memoryCache.totalCostLimit = memorySize

		_pending = [:]

		try! FileManager.default.createDirectory(at: _cacheDirectory, withIntermediateDirectories: true, attributes: nil)
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
		_memoryCache.removeAllObjects()
	}

	func removeObjectsAsyncOlderThan(_ expiration: Date) {
		DispatchQueue.global(qos: .background).async { [self] in
			for url in fileEnumerator(withAttributes: [.contentModificationDateKey]) {
				if let url = url as? URL,
				   let date = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate,
				   date < expiration
				{
					try? FileManager.default.removeItem(at: url)
				}
			}
		}
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
		completion: @escaping (_ object: T?) -> Void) -> T?
	{
		DbgAssert(Thread.isMainThread) // since we update our data structures on the main thread we need this true
		assert(_memoryCache.totalCostLimit != 0)
		if let cachedObject = _memoryCache.object(forKey: cacheKey as NSString) {
			return cachedObject
		}

		if let plist = _pending[cacheKey] {
			// already being downloaded
			_pending[cacheKey] = plist + [completion]
			return nil
		}
		_pending[cacheKey] = [completion]

		let processData: ((_ data: Data?) -> Bool) = { data in
			let obj = data != nil ? objectForData(data!) : nil
			DispatchQueue.main.async {
				if let obj = obj {
					self._memoryCache.setObject(obj,
					                            forKey: cacheKey as NSString,
					                            cost: data!.count)
				}
				for completion in self._pending[cacheKey] ?? [] {
					completion(obj)
				}
				self._pending.removeValue(forKey: cacheKey)
			}
			return obj != nil
		}

		DispatchQueue.global(qos: .default).async { [self] in
			// check disk cache
			let fileName = PersistentWebCache.encodeKey(forFilesystem: cacheKey)
			let filePath = _cacheDirectory.appendingPathComponent(fileName)
			if let data = try? Data(contentsOf: filePath) {
				_ = processData(data)
			} else {
				// fetch from server
				guard let url = urlFunction() else {
					_ = processData(nil)
					return
				}
				let request = URLRequest(url: url)
				let task = URLSession.shared.dataTask(with: request, completionHandler: { data, response, _ in
					let data = ((response as? HTTPURLResponse)?.statusCode ?? 404) < 300 ? data : nil
					if processData(data) {
						DispatchQueue.global(qos: .default).async {
							(data! as NSData).write(to: filePath, atomically: true)
						}
					}
				})
				task.resume()
			}
		}
		return nil
	}
}
