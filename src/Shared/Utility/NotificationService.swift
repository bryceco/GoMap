//
//  NotificationService.swift
//  Go Map!!
//
//  Created by Bryce Cogswell on 7/26/25.
//  Copyright © 2025 Bryce Cogswell. All rights reserved.
//

import Foundation

final class NotificationService<T> {
	private struct Subscriber {
		weak var object: AnyObject?
		let callback: (T) -> Void
	}

	private var subscribers: [Subscriber] = []

	func subscribe(object: AnyObject, callback: @escaping (T) -> Void) {
		subscribers.append(Subscriber(object: object, callback: callback))
	}

	func notify(_ result: T) {
		subscribers = subscribers.filter { $0.object != nil }
		for subscriber in subscribers {
			subscriber.callback(result)
		}
	}
}
