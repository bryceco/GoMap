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

	private let queue = DispatchQueue(label: "com.gomap.notificationservice")
	private var subscribers: [Subscriber] = []

	func subscribe(_ observer: AnyObject, handler: @escaping (T) -> Void) {
		queue.sync {
			subscribers.append(Subscriber(object: observer, callback: handler))
		}
	}

	func notify(_ result: T) {
		queue.async {
			self.subscribers = self.subscribers.filter { $0.object != nil }
			for subscriber in self.subscribers {
				DispatchQueue.main.async {
					subscriber.callback(result)
				}
			}
		}
	}
}

extension NotificationService where T == Void {
	func notify() {
		notify(())
	}
}
