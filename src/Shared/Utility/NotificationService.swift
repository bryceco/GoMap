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
			subscribers = subscribers.filter { $0.object !== observer && $0.object != nil }
			subscribers.append(Subscriber(object: observer, callback: handler))
		}
	}

	func unsubscribe(_ observer: AnyObject) {
		queue.sync {
			subscribers = subscribers.filter { $0.object !== observer && $0.object != nil }
		}
	}

	func notify(_ result: T) {
		if Thread.isMainThread {
			// Synchronous path for main thread
			var currentSubscribers: [Subscriber] = []
			queue.sync {
				if self.subscribers.contains(where: { $0.object == nil }) {
					// This is rare, so only do if necessary
					self.subscribers = self.subscribers.filter { $0.object != nil }
				}
				currentSubscribers = self.subscribers
			}
			for subscriber in currentSubscribers {
				subscriber.callback(result)
			}
		} else {
			// Async path for background threads
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
}

extension NotificationService where T == Void {
	func notify() {
		notify(())
	}
}

@propertyWrapper
final class Notify<T> {
	private let service = NotificationService<T>()
	private var value: T

	var wrappedValue: T {
		get { value }
		set {
			value = newValue
			service.notify(newValue)
		}
	}

	var projectedValue: Notify<T> {
		return self
	}

	func assign<Root: AnyObject>(to keyPath: ReferenceWritableKeyPath<Root, T>,
	                             on object: Root)
	{
		object[keyPath: keyPath] = value

		service.subscribe(object) { [weak object] newValue in
			object?[keyPath: keyPath] = newValue
		}
	}

	init(wrappedValue: T) {
		self.value = wrappedValue
	}

	func subscribe(_ observer: AnyObject, handler: @escaping (T) -> Void) {
		service.subscribe(observer, handler: handler)
	}

	func unsubscribe(_ observer: AnyObject) {
		service.unsubscribe(observer)
	}
}
