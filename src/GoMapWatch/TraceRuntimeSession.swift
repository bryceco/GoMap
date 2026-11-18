//
//  TraceRuntimeSession.swift
//  GoMapWatch
//
//  Copyright © 2026 Bryce Cogswell. All rights reserved.
//

import WatchKit

final class TraceRuntimeSession: NSObject, WKExtendedRuntimeSessionDelegate {
	private var session: WKExtendedRuntimeSession?

	func update(recording: Bool) {
		if recording {
			guard session == nil || session?.state == .invalid,
			      WKApplication.shared().applicationState == .active
			else {
				return
			}
			let session = WKExtendedRuntimeSession()
			session.delegate = self
			session.start()
			self.session = session
		} else {
			if session?.state == .running {
				session?.invalidate()
			}
			session = nil
		}
	}

	func extendedRuntimeSessionDidStart(_ extendedRuntimeSession: WKExtendedRuntimeSession) {}

	func extendedRuntimeSessionWillExpire(_ extendedRuntimeSession: WKExtendedRuntimeSession) {}

	func extendedRuntimeSession(_ extendedRuntimeSession: WKExtendedRuntimeSession,
	                            didInvalidateWith reason: WKExtendedRuntimeSessionInvalidationReason,
	                            error: Error?)
	{
		if extendedRuntimeSession === session {
			session = nil
		}
	}
}
