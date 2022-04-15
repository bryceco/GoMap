//
//  ExternalGPS.swift
//  Go Map!!
//
//  Created by Bryce Cogswell on 11/19/16.
//  Copyright © 2016 Bryce Cogswell. All rights reserved.
//

import CoreLocation
import ExternalAccessory
import Foundation

class ExternalGPS: NSObject, StreamDelegate {
	var session: EASession?
	var readBuffer: Data
	var writeBuffer: Data
	var accessoryManager: EAAccessoryManager

	override init() {
		readBuffer = Data()
		writeBuffer = Data()
		accessoryManager = EAAccessoryManager.shared()

		super.init()

		NotificationCenter.default.addObserver(
			self,
			selector: #selector(accessoryDidConnect(_:)),
			name: .EAAccessoryDidConnect,
			object: nil)
		NotificationCenter.default.addObserver(
			self,
			selector: #selector(EAAccessoryDelegate.accessoryDidDisconnect(_:)),
			name: .EAAccessoryDidDisconnect,
			object: nil)
		accessoryManager.registerForLocalNotifications()

		DLog("GPS = \(accessoryManager.connectedAccessories)\n")
		for acc in accessoryManager.connectedAccessories {
			_ = connect(acc)
		}
	}

	func connect(_ accessory: EAAccessory) -> Bool {
		if let session = self.session {
			// disconnect previous session
			session.inputStream?.close()
			session.outputStream?.close()
			self.session = nil
		}

		guard let gpsProtocol = accessory.protocolStrings.first(where: { $0 == "com.dualav.xgps150" })
		else {
			return false
		}

		guard let session = EASession(accessory: accessory, forProtocol: gpsProtocol) else { return false }
		session.inputStream?.delegate = self
		session.inputStream?.schedule(in: RunLoop.current, forMode: .default)
		session.inputStream?.open()
		session.outputStream?.delegate = self
		session.outputStream?.schedule(in: RunLoop.current, forMode: .default)
		session.outputStream?.open()
		self.session = session

		return true
	}

	@objc func accessoryDidConnect(_ notification: Notification?) {
		if let connectedAccessory = notification?.userInfo?[EAAccessoryKey] as? EAAccessory {
			_ = connect(connectedAccessory)
		}
	}

	@objc func accessoryDidDisconnect(_ notification: Notification?) {
		session?.inputStream?.close()
		session?.outputStream?.close()
		session = nil
	}

	// http://aprs.gids.nl/nmea/#allgp
	// http://www.gpsinformation.org/dale/nmea.htm
	func processNMEA(_ data: inout Data) {
		while data.count > 8 {
			var str = ""
			data.withUnsafeBytes({ bytes in
				str = bytes.load(as: String.self)
			})

			if str.first == "@" {
				// skip to \0
				var pos = 1
				while pos < data.count {
					pos += 1
				}
				if pos >= data.count {
					return
				}
				data.removeFirst(pos + 1)
				continue
			}

			if str.first == "C" {
				// skip to \n
				var pos = 1
				while pos < data.count, str[String.Index(utf16Offset: pos, in: str)] != "\n" {
					pos += 1
				}
				if pos >= data.count {
					return
				}
				data.removeFirst(pos + 1)
				continue
			}

			if str.first == "\0" {
				// end of block
				(data as? NSMutableData)?.replaceBytes(in: NSRange(location: 0, length: 1), withBytes: nil, length: 0)
				continue
			}

			// scan for \r\n
			var pos = 1
			while pos < data.count, str[String.Index(utf16Offset: pos, in: str)] != "\n" {
				pos += 1
			}
			if pos >= data.count {
				return
			}
			//            let line = String(bytes: str, encoding: .utf8)
			let line = str
			//		DLog(@"%@",line);
			data.removeFirst(pos + 1)

			if line.hasPrefix("PGLL") {
				// lat/lon data
				let scanner = Scanner(string: line)
				var lat: NSString? = ""
				var lon: NSString? = ""
				var NS: NSString? = ""
				var EW: NSString? = ""
				var time: NSString? = ""
				var checksum: Int32 = -1
				scanner.scanString("PGLL", into: nil)
				scanner.scanString(",", into: nil)

				scanner.scanUpTo(",", into: &lat)
				scanner.scanString(",", into: nil)
				scanner.scanUpTo(",", into: &NS)
				scanner.scanString(",", into: nil)

				scanner.scanUpTo(",", into: &lon)
				scanner.scanString(",", into: nil)
				scanner.scanUpTo(",", into: &EW)
				scanner.scanString(",", into: nil)

				scanner.scanUpTo(",", into: &time)
				scanner.scanString(",", into: nil)

				scanner.scanUpTo("*", into: nil) // skip void/active marker
				scanner.scanString("*", into: nil)

				scanner.scanInt32(&checksum)

				var dot = (lat as NSString?)?.range(of: ".").location ?? 0
				var dLat = (Double((lat as NSString?)?.substring(to: dot - 2) ?? "") ?? 0.0) +
					(Double((lat as NSString?)?.substring(from: dot - 2) ?? "") ?? 0.0) / 60.0
				if NS == "S" {
					dLat = -dLat
				}

				dot = (lon as NSString?)?.range(of: ".").location ?? 0
				var dLon = (Double((lon as NSString?)?.substring(to: dot - 2) ?? "") ?? 0.0) +
					(Double((lon as NSString?)?.substring(from: dot - 2) ?? "") ?? 0.0) / 60.0
				if EW == "W" {
					dLon = -dLon
				}

#if os(iOS)
				let loc = CLLocation(latitude: CLLocationDegrees(dLat), longitude: CLLocationDegrees(dLon))
				DLog("lat/lon = \(loc)")
				let appDelegate = AppDelegate.shared
				appDelegate.mapView?.locationUpdated(to: loc)
#endif
			} else if line.hasPrefix("PGSV") {
				// satelite info, one line per satelite
			} else if line.hasPrefix("PGSA") {
				// summary satelite info
			} else if line.hasPrefix("PRMC") {
				// recommended minimum GPS data
			} else if line.hasPrefix("PVTG") {
				// velocity data
			} else if line.hasPrefix("PGGA") {
				// fix information
			} else if line.hasPrefix("PZDA") {
				// date & time
			}
		}
	}

	func updateReadData() {
		let BufferSize = 128
		var buffer: [UInt8] = [0]

		while session?.inputStream?.hasBytesAvailable ?? false {
			let bytesRead = session?.inputStream?.read(&buffer, maxLength: BufferSize) ?? 0
			readBuffer.append(&buffer, count: bytesRead)

			processNMEA(&readBuffer)
		}
	}

	func sendData() {
		while session?.outputStream?.hasSpaceAvailable ?? false, writeBuffer.count > 0 {
			var bytesWritten = 0
			writeBuffer.withContiguousStorageIfAvailable({ ptr in
				bytesWritten = session?.outputStream?.write(ptr.baseAddress!, maxLength: writeBuffer.count) ?? 0
			})
			if bytesWritten == -1 {
				// error
				return
			} else if bytesWritten > 0 {
				writeBuffer.removeFirst(bytesWritten)
			}
		}
	}

	// MARK: NSStream delegate methods

	func stream(_ aStream: Stream, handle eventCode: Stream.Event) {
		switch eventCode {
		case []:
			break
		case .openCompleted:
			break
		case .hasBytesAvailable:
			// Read Data
			updateReadData()
		case .hasSpaceAvailable:
			// Write Data
			sendData()
		case .errorOccurred:
			break
		case .endEncountered:
			break
		default:
			break
		}
	}
}
