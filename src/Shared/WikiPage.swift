//  Converted to Swift 5.4 by Swiftify v5.4.27034 - https://swiftify.com/
//
//  WikiPage.swift
//  Go Map!!
//
//  Created by Bryce Cogswell on 5/26/20.
//  Copyright © 2020 Bryce. All rights reserved.
//

import Foundation

@objcMembers
@objc(WikiPage)
class WikiPage: NSObject {
    static var g_shared = WikiPage()
    
    class func shared() -> WikiPage {
        // `dispatch_once()` call was converted to a static variable initializer
        return g_shared
    }

    func wikiLanguage(forLanguageCode code: String) -> String? {
        if code.count == 0 {
            return ""
        }
        let special = [
            "en": "",
            "de": "DE:",
            "es": "ES:",
            "fr": "FR:",
            "it": "IT:",
            "ja": "JA:",
            "nl": "NL:",
            "ru": "RU:",
            "zh-CN": "Zh-hans:",
            "zh-HK": "Zh-hant:",
            "zh-TW": "Zh-hant:"
        ]
        var result = special[code]
        if result != "" {
            return result
        }

        result = (code as NSString).substring(to: 1).uppercased() + (code as NSString).substring(from: 1) + ":"
        return result
    }

    func ifUrlExists(_ url: URL, completion: @escaping (_ exists: Bool) -> Void) {
        let request = NSMutableURLRequest(url: url)
        request.httpMethod = "HEAD"
        request.cachePolicy = .returnCacheDataElseLoad
        let task = URLSession.shared.downloadTask(
            with: request as URLRequest,
            completionHandler: { purl, response, error in
                var exists = false
                if error == nil {
                    let httpResponse = response as? HTTPURLResponse
                    switch httpResponse?.statusCode {
                        case 200, 301, 302:
                            exists = true
                        default:
                            break
                    }
                }
                completion(exists)
            })
        task.resume()
    }

    func bestWikiPage(
        forKey tagKey: String,
        value tagValue: String,
        language: String,
        completion: @escaping (_ url: URL?) -> Void
    ) {
        var tagKey = tagKey
        var tagValue = tagValue
        var language = language
        if let lang = wikiLanguage(forLanguageCode: language) {
            language = lang
        }

        var pageList: [AnyHashable] = []

        tagKey = tagKey.addingPercentEncoding(withAllowedCharacters: CharacterSet.urlQueryAllowed) ?? ""
        tagValue = tagValue.addingPercentEncoding(withAllowedCharacters: CharacterSet.urlQueryAllowed) ?? ""

        // key+value
        if tagValue.count != 0 {
            // exact language
            pageList.append("\(language)Tag:\(tagKey)=\(tagValue)")
            if language.count != 0 {
                pageList.append("Tag:\(tagKey)=\(tagValue)")
            }
        }
        pageList.append("\(language)Key:\(tagKey)")
        if language.count != 0 {
            pageList.append("Key:\(tagKey)")
        }

        var urlDict: [AnyHashable : Any] = [:]

        DispatchQueue.global(qos: .default).async(execute: { [self] in

            let group = DispatchGroup()
            let baseURL = URL(string: "https://wiki.openstreetmap.org/wiki/")

            for page in pageList {
                guard let page = page as? String else {
                    continue
                }
                let url = baseURL?.appendingPathComponent(page)
                if url == nil {
                    continue
                }
                group.enter()
                if let url = url {
                    ifUrlExists(url) { exists in
                        if exists {
                            DispatchQueue.main.async(execute: {
                                urlDict[page] = url
                            })
                        }
                        group.leave()
                    }
                }
            }
            _ = group.wait(timeout: DispatchTime.distantFuture)

            DispatchQueue.main.async(execute: {
                for page in pageList {
                    guard let page = page as? String else {
                        continue
                    }
                    let url = urlDict[page] as? URL
                    if let url = url {
                        completion(url)
                        return
                    }
                }
                completion(nil)
            })
        })

#if false
            // query wiki metadata for which pages match
            let urlComponents = NSURLComponents(string: "https://wiki.openstreetmap.org/w/api.php?action=wbgetentities&sites=wiki&languages=en&format=json")
            let newItem = NSURLQueryItem(name: "titles", value: titles)
            if let queryItems = urlComponents?.queryItems {
                urlComponents?.queryItems = queryItems + [newItem]
            }
            var request: URLRequest? = nil
            if let URL = urlComponents?.url {
                request = URLRequest(url: URL)
            }
            var task: URLSessionDataTask? = nil
            if let request = request {
                task = URLSession.shared.dataTask(with: request, completionHandler: { data, response, error in

                    if error == nil && (data?.count ?? 0) != 0 {

                        SwiftTryCatch.try({
                            var json: Any? = nil
                            do {
                                if let data = data {
                                    json = try JSONSerialization.jsonObject(with: data, options: [])
                                }
                            } catch {
                            }
                            let entitiesDict = json?["entities"] as? [AnyHashable : Any]
                            (entitiesDict as NSDictionary?)?.enumerateKeysAndObjects({ name, entityDict, stop in
                                let claims = entityDict["claims"] as? [AnyHashable : Any]
                                if let claim = claims?["P31"] {
                                    for lang in claim {
                                        let value = lang["mainsnak"]["datavalue"]["value"] as? [AnyHashable : Any]
                                        let pageTitle = value?["text"] as? String
                                        let pageLanguage = value?["language"] as? String
                                        print("\(pageLanguage ?? "") = \(pageTitle ?? "")")
                                    }
                                }
                            })
                        }, catch: { exception in
                        }, finallyBlock: {
                        })
                    }
                    completion(error)
                })
            }
            task?.resume()
#endif
    }
}
