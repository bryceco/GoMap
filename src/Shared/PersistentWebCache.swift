//  Converted to Swift 5.4 by Swiftify v5.4.27034 - https://swiftify.com/
//
//  PersistentWebCache.swift
//  Go Map!!
//
//  Created by Bryce on 5/3/20.
//  Copyright © 2020 Bryce. All rights reserved.
//

import Foundation

@objcMembers
class PersistentWebCache: NSObject {
    var _cacheDirectory: URL?
    var _memoryCache: NSCache<AnyObject, AnyObject>?
    var _pending: NSMutableDictionary? // track objects we're already downloading so we don't issue multiple requests
    
    class func encodeKey(forFilesystem string: String) -> String {
        var string = string
        let allowed = CharacterSet(charactersIn: "/").inverted
        string = string.addingPercentEncoding(withAllowedCharacters: allowed) ?? ""
        return string
    }
    
    func fileEnumerator(withAttributes attr: NSArray?) -> FileManager.DirectoryEnumerator {
        return FileManager.default.enumerator(
            at: _cacheDirectory!,
            includingPropertiesForKeys: (attr as? [URLResourceKey]),
            options: [.skipsSubdirectoryDescendants, .skipsPackageDescendants, .skipsHiddenFiles],
            errorHandler: nil)!
    }
    
    func allKeys() -> [String] {
        var a: [AnyHashable] = []
        for url in fileEnumerator(withAttributes: nil) {
            guard let url = url as? URL else {
                continue
            }
            let s = url.lastPathComponent // automatically removes escape encoding
            a.append(s)
        }
        return a as? [String] ?? []
    }
    
    override init() {
        super.init()
    }
    
    init(name: String, memorySize: Int) {
        var name = name
        super.init()
        name = PersistentWebCache.encodeKey(forFilesystem: name)
        
        _memoryCache = NSCache()
        _memoryCache?.countLimit = 10000
        _memoryCache?.totalCostLimit = memorySize
        
        _pending = [:]
        
        let bundleName = Bundle.main.infoDictionary?["CFBundleIdentifier"] as? String
        do {
            _cacheDirectory = try FileManager.default.url(for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: true).appendingPathComponent(bundleName ?? "", isDirectory: true).appendingPathComponent(name, isDirectory: true)
        } catch {}
        do {
            if let cacheDirectory = _cacheDirectory {
                try FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true, attributes: nil)
            }
        } catch {}
    }
    
    func removeAllObjects() {
        for url in fileEnumerator(withAttributes: nil) {
            guard let url = url as? URL else {
                continue
            }
            do {
                try FileManager.default.removeItem(at: url)
            } catch {
            }
        }
        _memoryCache?.removeAllObjects()
    }
    
    func removeObjectsAsyncOlderThan(_ expiration: Date) {
        DispatchQueue.global(qos: .default).async(execute: { [self] in
            for url in fileEnumerator(withAttributes: [URLResourceKey.contentModificationDateKey]) {
                guard let url = url as? NSURL else {
                    continue
                }
                var date: AnyObject? = nil
                do {
                    try url.getResourceValue(&date, forKey: URLResourceKey.contentModificationDateKey)
                    if (date as? Date)?.compare(expiration).rawValue ?? 0 < 0 {
                        do {
                            try FileManager.default.removeItem(at: url as URL)
                        } catch {}
                    }
                } catch {}
            }
        })
    }
    
    @objc func getDiskCacheSize(_ pSize: UnsafeMutablePointer<Int>, count pCount: UnsafeMutablePointer<Int>) {
        var count = 0
        var size = 0
        for url in fileEnumerator(withAttributes: [URLResourceKey.fileAllocatedSizeKey]) {
            guard let url = url as? NSURL else {
                continue
            }
            var len: AnyObject? = nil
            do {
                try url.getResourceValue(&len, forKey: URLResourceKey.fileAllocatedSizeKey)
            } catch {}
            count += 1
            size += (len as? NSNumber)?.intValue ?? 0
        }
        pSize.pointee = size
        pCount.pointee = count
    }
    
    func object(
        withKey cacheKey: String,
        fallbackURL urlFunction: @escaping () -> URL,
        objectForData: @escaping (_ data: Data?) -> Any,
        completion: @escaping (_ object: Any) -> Void
    ) -> Any? {
        DbgAssert(Thread.isMainThread)
        let cachedObject = _memoryCache?.object(forKey: (cacheKey as AnyObject))
        if let cachedObject = cachedObject {
            return cachedObject
        }
        
        let plist = _pending?[cacheKey] as? NSMutableArray
        if let plist = plist {
            // already being downloaded
            plist.add(completion)
            return nil
        }
        _pending?[cacheKey] = [completion]
        
        let gotData: ((_ data: Data) -> Bool) = { [self] data in
            let obj = objectForData != nil ? (objectForData(data) as? Data) : data
            DispatchQueue.main.async(execute: { [self] in
                if let obj = obj {
                    _memoryCache?.setObject((obj as AnyObject), forKey: (cacheKey as AnyObject), cost: data.count)
                }
                let completionList = _pending?[cacheKey] as? NSArray
                for innerCompletion in completionList ?? [] {
                    if let innerCompletion = (innerCompletion as? (Any?) -> Void) {
                        innerCompletion(obj)
                    }
                }
                _pending?.removeObject(forKey: cacheKey)
            })
            return obj != nil
        }
        
        DispatchQueue.global(qos: .default).async(execute: { [self] in
            // check disk cache
            let fileName = PersistentWebCache.encodeKey(forFilesystem: cacheKey)
            let filePath = _cacheDirectory?.appendingPathComponent(fileName)
            var fileData: Data? = nil
            if let filePath = filePath {
                do {
                    fileData = try Data(contentsOf: filePath)
                } catch  {}
            }
            if let fileData = fileData {
                gotData(fileData)
            } else {
                // fetch from server
                let url = urlFunction()
                let request = URLRequest(url: url)
                let task = URLSession.shared.dataTask(with: request, completionHandler: { data, response, error in
                    if let data = data {
                        if gotData(data) {
                            DispatchQueue.global(qos: .default).async(execute: {
                                if let filePath = filePath {
                                    NSData(data: data).write(to: filePath, atomically: true)
                                }
                            })
                        }
                    }
                })
                task.resume()
            }
        })
        return nil
    }
}

func DbgAssert(_ x: Bool) {
    assert(x, "unspecified")
}
