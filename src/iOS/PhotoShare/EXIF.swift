//
//  EXIF.swift
//  PhotoShare
//
//  Created by Bryce Cogswell on 3/23/23.
//  Copyright © 2023 Bryce Cogswell. All rights reserved.
//

import Foundation

private let VERBOSE = false

/**************************************************************************
 exif.cpp  -- A simple ISO C++ library to parse basic EXIF
 information from a JPEG file.

 Copyright (c) 2010-2015 Mayank Lahiri
 mlahiri@gmail.com
 All rights reserved (BSD License).

 See exif.h for version history.

 Redistribution and use in source and binary forms, with or without
 modification, are permitted provided that the following conditions are met:

 -- Redistributions of source code must retain the above copyright notice,
 this list of conditions and the following disclaimer.
 -- Redistributions in binary form must reproduce the above copyright notice,
 this list of conditions and the following disclaimer in the documentation
 and/or other materials provided with the distribution.

 THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS ``AS IS'' AND ANY EXPRESS
 OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES
 OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN
 NO EVENT SHALL THE FREEBSD PROJECT OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT,
 INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING,
 BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
 DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY
 OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING
 NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE,
 EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 */

enum ExifError: Error {
	case invalidFormat
	case notJPG
	case missingEXIF
	case unknownByteAlignment
	case exifCorrupt
}

private enum Endian {
	case motorola
	case intel
}

private struct Rational {
	var numerator, denominator: UInt32
	func double() -> Double {
		if denominator == 0 {
			return 0
		}
		return Double(numerator) / Double(denominator)
	}

	init(numerator: UInt32, denominator: UInt32) {
		self.numerator = numerator
		self.denominator = denominator
	}

	init(_ other: Rational) {
		numerator = other.numerator
		denominator = other.denominator
	}
}

private enum Format: UInt16 {
	case byte = 0x1
	case ascii = 0x2
	case short = 0x3
	case long = 0x4
	case rational = 0x5

	case other7 = 7
	case other9 = 9
	case rational2 = 10

	func sizeOf() -> Int {
		switch self {
		case .byte: return 1
		case .ascii: return 1
		case .short: return 2
		case .long: return 4
		case .rational: return 8

		case .other7: return 0
		case .other9: return 0
		case .rational2: return 8
		}
	}
}

private struct IFEntry {
	let tag: UInt16
	let format: Format
	let length: UInt32
	private let data: ArraySlice<UInt8> // need to recast this to appropriate type
	private let endian: Endian

	init(tiff: ArraySlice<UInt8>, offset: Int, endian: Endian) throws {
		self.endian = endian
		tag = try parseInteger(tiff[offset...], endian: endian)
		let dataLoc: UInt32 = try parseInteger(tiff[(offset+8)...], endian: endian)
		length = try parseInteger(tiff[(offset+4)...], endian: endian)
		let format: UInt16 = try parseInteger(tiff[(offset+2)...], endian: endian)
		guard let format = Format(rawValue: format) else {
			throw ExifError.invalidFormat
		}
		self.format = format
		// The value is either the data inline, or at a location pointed to by data
		let size = Int(length) * format.sizeOf()
		let valueOffset: Int
		if size > 4 {
			valueOffset = tiff.startIndex+Int(dataLoc)
		} else {
			// for small values the data is in the data field itself.
			valueOffset = offset+8
		}
		guard valueOffset+size < tiff.endIndex else {
			throw ExifError.invalidFormat
		}
		data = tiff[valueOffset..<valueOffset+size]
	}

	func val_byte() throws -> [UInt8] {
		guard format == .byte else { throw ExifError.invalidFormat }
		return Array(data)
	}
	func val_short() throws -> [UInt16] {
		guard format == .short else { throw ExifError.invalidFormat }
		return try toIntegerVector(data, endian: endian)
	}
	func val_long() throws -> [UInt32] {
		guard format == .long else { throw ExifError.invalidFormat }
		return try toIntegerVector(data, endian: endian)
	}
	func val_rational() throws -> [Rational] {
		guard format == .rational || format == .rational2 else { throw ExifError.invalidFormat }
		let vec: [UInt32] = try toIntegerVector(data, endian: endian)
		guard vec.count % 2 == 0 else {
			throw ExifError.invalidFormat
		}
		var result: [Rational] = []
		for idx in 0..<vec.count / 2 {
			result.append(Rational(numerator: vec[2 * idx], denominator: vec[2 * idx + 1]))
		}
		return result
	}
	func val_ascii() throws -> String {
		guard format == .ascii else { throw ExifError.invalidFormat }
		var val = data
		// remove trailing null
		if let last = val.last,
		   last == 0
		{
			val = val.dropLast()
		}
		guard let result = String(data: Data(val), encoding: .ascii)
		else {
			throw ExifError.invalidFormat
		}
		return result
	}
}

private func parseInteger<T: FixedWidthInteger & UnsignedInteger>(_ bytes: ArraySlice<UInt8>, endian: Endian) throws -> T {
	let size = MemoryLayout<T>.size
	guard bytes.count >= size else {
		throw ExifError.invalidFormat
	}
	var result = bytes.prefix(size).enumerated().reduce(0) {
		$0 | (T($1.element) << (8 * $1.offset))
	}
	if endian == .motorola {
		result = result.bigEndian
	}
	return result
}

private func toIntegerVector<T: FixedWidthInteger & UnsignedInteger>(_ bytes: ArraySlice<UInt8>,
																	 endian: Endian) throws -> [T]
{
	let size = MemoryLayout<T>.size
	guard bytes.count % size == 0 else {
		throw ExifError.invalidFormat
	}
	let count = bytes.count / size
	var vec: [T] = []
	vec.reserveCapacity(count)
	for idx in 0..<count {
		let v: T = try parseInteger(bytes[bytes.startIndex + size * idx..<bytes.startIndex + size * idx + size],
									endian: endian)
		vec.append(v)
	}
	return vec
}

public struct EXIFInfo {
	private var endian: Endian

	struct IFD0 {
		var imageDescription: String? // Image description
		var make: String? // Camera manufacturer's name
		var model: String? // Camera model
		var orientation: UInt16? // Image orientation, start of data corresponds to
		// 0: unspecified in EXIF data
		// 1: upper left of image
		// 3: lower right of image
		// 6: upper right of image
		// 8: lower left of image
		// 9: undefined
		var bitsPerSample: UInt16? // Number of bits per component
		var software: String? // Software used
		var dateTime: String? // File change date and time
		var copyright: String? // File copyright information

		fileprivate var gpsOffset: Int?
		fileprivate var exifOffset: Int?
	}
	var ifd0: IFD0

	struct ExifIFD {
		var exposureTime: Double? // Exposure time in seconds
		var fNumber: Double? // F/stop
		var exposureProgram: UInt16? // Exposure program
		// 0: Not defined
		// 1: Manual
		// 2: Normal program
		// 3: Aperture priority
		// 4: Shutter priority
		// 5: Creative program
		// 6: Action program
		// 7: Portrait mode
		// 8: Landscape mode
		var isoSpeedRating: UInt16? // ISO speed
		var shutterSpeed: Double? // Shutter speed (reciprocal of exposure time)
		var exposureBias: Double? // Exposure bias value in EV
		var subjectDistance: Double? // Distance to focus point in meters
		var focalLength: Double? // Focal length of lens in millimeters
		var focalLengthIn35mm: UInt16? // Focal length in 35mm film
		var flash: Int8? // 0 = no flash, 1 = flash used
		var flashReturnedLight: UInt8? // Flash returned light status
		// 0: No strobe return detection function
		// 1: Reserved
		// 2: Strobe return light not detected
		// 3: Strobe return light detected
		var flashMode: UInt8? // Flash mode
		// 0: Unknown
		// 1: Compulsory flash firing
		// 2: Compulsory flash suppression
		// 3: Automatic mode
		var meteringMode: UInt16? // Metering mode
		// 1: average
		// 2: center weighted average
		// 3: spot
		// 4: multi-spot
		// 5: multi-segment
		var dateTimeOriginal: String? // Original file date and time (may not exist)
		var dateTimeDigitized: String? // Digitization date and time (may not exist)
		var subSecTimeOriginal: String? // Sub-second time that original picture was taken
		var imageWidth: UInt? // Image width reported in EXIF data
		var imageHeight: UInt? // Image height reported in EXIF data

		struct LensInfo { // Lens information
			var fStopMin: Double? // Min aperture (f-stop)
			var fStopMax: Double? // Max aperture (f-stop)
			var focalLengthMin: Double? // Min focal length (mm)
			var focalLengthMax: Double? // Max focal length (mm)
			var focalPlaneXResolution: Double? // Focal plane X-resolution
			var focalPlaneYResolution: Double? // Focal plane Y-resolution
			var focalPlaneResolutionUnit: UInt16? // Focal plane resolution unit
			// 1: No absolute unit of measurement.
			// 2: Inch.
			// 3: Centimeter.
			// 4: Millimeter.
			// 5: Micrometer.
			var make: String? // Lens manufacturer
			var model: String? // Lens model
		}
		var lensInfo: LensInfo = LensInfo()
	}
	var exifIFD: ExifIFD

	struct GPS { // GPS information embedded in file
		var altitude: Double? // Altitude in meters, relative to sea level
		var altitudeRef: Int8? // 0 = above sea level, -1 = below sea level
		var dop: Double? // GPS degree of precision (DOP)
		struct Coord_t {
			var degrees: Double = 0.0
			var minutes: Double = 0.0
			var seconds: Double = 0.0
			var direction: Character?

			var decimal: Double? {
				let dec = degrees + minutes / 60 + seconds / 3600
				guard let dir = direction else { return nil }
				if dir == "S" || dir == "W" {
					return -dec
				} else {
					return dec
				}
			}
		} // Latitude, Longitude expressed in deg/min/sec
		var latComponents = Coord_t()
		var lonComponents = Coord_t()
		var imgDirectionRef: Character?
		var imgDirection: Double?
	}
	var gps: GPS

	init() {
		endian = .intel

		ifd0 = IFD0()
		exifIFD = ExifIFD()
		gps = GPS()
	}

	init(from data: Data) throws {
		self.init()
		try self.parseJPG(data)
	}

	private mutating func parseJPG(_ data: Data) throws {
		let buf = try Self.exifSegmentForJPG(data)
		try parseEXIFSegment(buf)
	}

	// Parsing function for an entire JPEG image buffer.
	//
	// Locates the EXIF segment and parses it using parseFromEXIFSegment
	//
	static func exifSegmentForJPG(_ data: Data) throws -> ArraySlice<UInt8> {
		let buf = Array(data) as [UInt8]

		// Sanity check: all JPEG files start with 0xFFD8.
		if buf.count < 4 { throw ExifError.notJPG }
		if buf[0] != 0xFF || buf[1] != 0xD8 { throw ExifError.notJPG }

		// Sanity check: some cameras pad the JPEG image with some bytes at the end.
		// Normally, we should be able to find the JPEG end marker 0xFFD9 at the end
		// of the image buffer, but not always. As long as there are some bytes
		// except 0xD9 at the end of the image buffer, keep decrementing len until
		// an 0xFFD9 is found. If JPEG end marker 0xFFD9 is not found,
		// then we can be reasonably sure that the buffer is not a JPEG.
		if buf.indices.dropLast().last(where: { buf[$0] == 0xFF && buf[$0+1] == 0xD9 }) == nil {
			throw ExifError.notJPG
		}

		// Scan for EXIF header (bytes 0xFF 0xE1) and do a sanity check by
		// looking for bytes "Exif\0\0". The marker length data is in Motorola
		// byte order.
		// The marker has to contain at least the TIFF header, otherwise the
		// EXIF data is corrupt. So the minimum length specified here has to be:
		//   2 bytes: section size
		//   6 bytes: "Exif\0\0" string
		//   2 bytes: TIFF header (either "II" or "MM" string)
		//   2 bytes: TIFF magic (short 0x2a00 in Motorola byte order)
		//   4 bytes: Offset to first IFD
		// =========
		//  16 bytes
		guard let offs = buf.indices.dropLast(6).first(where: { buf[$0] == 0xFF && buf[$0 + 1] == 0xE1 })
		else {
			throw ExifError.missingEXIF
		}

		let section_length: UInt16 = try parseInteger(buf[(offs+2)...], endian: .motorola)
		if offs + 2 + Int(section_length) > buf.count || section_length < 16 {
			throw ExifError.exifCorrupt
		}

		let exifBuf = buf[(offs+4)...]
		return exifBuf
	}

	//
	// Main parsing function for an EXIF segment.
	//
	private mutating func parseEXIFSegment(_ buf: ArraySlice<UInt8>) throws {
		var offs = buf.startIndex // current offset into buffer
		if buf.count < 6 {
			throw ExifError.missingEXIF
		}
		guard String(data: Data(buf.prefix(6)), encoding: .ascii) == "Exif\0\0" else {
			throw ExifError.missingEXIF
		}
		offs += 6

		let tiff = buf[offs...]

		// Now parsing the TIFF header. The first two bytes are either "II" or
		// "MM" for Intel or Motorola byte alignment. Sanity check by parsing
		// the unsigned short that follows, making sure it equals 0x2a. The
		// last 4 bytes are an offset into the first IFD, which are added to
		// the global offset counter. For this block, we expect the following
		// minimum size:
		//  2 bytes: 'II' or 'MM'
		//  2 bytes: 0x002a
		//  4 bytes: offset to first IFD
		// -----------------------------
		//  8 bytes
		if offs + 8 >= tiff.endIndex {
			throw ExifError.exifCorrupt
		}

		if tiff[offs] == Character("I").asciiValue,
		   tiff[offs+1] == Character("I").asciiValue
		{
			endian = .intel
		} else if tiff[offs] == Character("M").asciiValue,
				  tiff[offs+1] == Character("M").asciiValue
		{
			endian = .motorola
		} else {
			throw ExifError.unknownByteAlignment
		}
		offs += 2
		guard let flag: UInt16 = try? parseInteger(tiff[offs...], endian: endian),
			  flag == 0x2A
		else {
			throw ExifError.exifCorrupt
		}
		offs += 2

		let ifd0Offset = tiff.startIndex + Int(try parseInteger(tiff[offs...], endian: endian) as UInt32)
		if ifd0Offset >= tiff.endIndex {
			throw ExifError.exifCorrupt
		}

		// Parse first directory
		self.ifd0 = try Self.parseIFD0(tiff: tiff,
									   offs: ifd0Offset,
									   endian: endian)

		if let exifOffset = self.ifd0.exifOffset {
			self.exifIFD = try Self.parseExifIFD(tiff: tiff,
												 offs: exifOffset,
												 endian: endian)
		}

		if let gpsOffset = self.ifd0.gpsOffset {
			self.gps = try Self.parseGps(tiff: tiff,
										 offs: gpsOffset,
										 endian: endian)
		}
	}

	private static func parseDirectory(tiff: ArraySlice<UInt8>,
									   offs: Int,
									   endian: Endian) throws -> [IFEntry]
	{
		var offs = offs
		if offs + 2 >= tiff.endIndex {
			throw ExifError.exifCorrupt
		}
		let num_sub_entries: UInt16 = try parseInteger(tiff[offs...], endian: endian)
		if offs + 6 + 12 * Int(num_sub_entries) >= tiff.endIndex {
			throw ExifError.exifCorrupt
		}
		offs += 2
		var list: [IFEntry] = []
		for _ in 0..<num_sub_entries {
			do {
				let entry = try IFEntry(tiff: tiff, offset: offs, endian: endian)
				list.append(entry)
			} catch {
				print("\(error)")
			}
			offs += 12
		}
		// following 4 bytes contain offset to next IFD, which we ignore
		return list
	}

	private static func parseIFD0(tiff: ArraySlice<UInt8>, offs: Int, endian: Endian) throws -> IFD0 {
		var ifd0 = IFD0()
		let entries = try Self.parseDirectory(tiff: tiff,
											  offs: offs,
											  endian: endian)
		for entry in entries {
			do {
				switch entry.tag {
				case 0x102:
					// Bits per sample
					ifd0.bitsPerSample = try entry.val_short()[0]
				case 0x10E:
					// Image description
					ifd0.imageDescription = try entry.val_ascii()
				case 0x10F:
					// Digicam make
					ifd0.make = try entry.val_ascii()
				case 0x110:
					// Digicam model
					ifd0.model = try entry.val_ascii()
				case 0x112:
					// Orientation of image
					ifd0.orientation = try entry.val_short()[0]
				case 0x131:
					// Software used for image
					ifd0.software = try entry.val_ascii()
				case 0x132:
					// EXIF/TIFF date/time of image modification
					ifd0.dateTime = try entry.val_ascii()
				case 0x8298:
					// Copyright information
					ifd0.copyright = try entry.val_ascii()
				case 0x8825:
					// GPS IFS offset
					ifd0.gpsOffset = try tiff.startIndex + Int(entry.val_long()[0])
				case 0x8769:
					ifd0.exifOffset = try tiff.startIndex + Int(entry.val_long()[0])
				default:
					// unknown
#if VERBOSE
					let hex = String(result.tag, radix: 16, uppercase: false)
					print("unsupported tag: \(hex)")
#endif
				}
			} catch {
				print("\(error)")
			}
		}
		return ifd0
	}

	private static func parseExifIFD(tiff: ArraySlice<UInt8>, offs: Int, endian: Endian) throws -> ExifIFD {
		var sub: ExifIFD = ExifIFD()
		let entries = try Self.parseDirectory(tiff: tiff,
											  offs: offs,
											  endian: endian)
		for entry in entries {
			do {
				switch entry.tag {
				case 0x829A:
					// Exposure time in seconds
					sub.exposureTime = try entry.val_rational()[0].double()
				case 0x829D:
					// FNumber
					sub.fNumber = try entry.val_rational()[0].double()
				case 0x8822:
					// Exposure Program
					sub.exposureProgram = try entry.val_short()[0]
				case 0x8827:
					// ISO Speed Rating
					sub.isoSpeedRating = try entry.val_short()[0]
				case 0x9003:
					// Original date and time
					sub.dateTimeOriginal = try entry.val_ascii()
				case 0x9004:
					// Digitization date and time
					sub.dateTimeDigitized = try entry.val_ascii()
				case 0x9201:
					// Shutter speed value
					sub.shutterSpeed = try entry.val_rational()[0].double()
				case 0x9204:
					// Exposure bias value
					sub.exposureBias = try entry.val_rational()[0].double()
				case 0x9206:
					// Subject distance
					sub.subjectDistance = try entry.val_rational()[0].double()
				case 0x9209:
					// Flash used
					let data = try entry.val_short()[0]
					sub.flash = Int8(data & 1)
					sub.flashReturnedLight = UInt8((data >> 1) & 3)
					sub.flashMode = UInt8((data >> 3) & 3)
				case 0x920A:
					// Focal length
					sub.focalLength = try entry.val_rational()[0].double()
				case 0x9207:
					// Metering mode
					sub.meteringMode = try entry.val_short()[0]
				case 0x9291:
					// Subsecond original time
					sub.subSecTimeOriginal = try entry.val_ascii()
				case 0xA002:
					// EXIF Image width
					if entry.format == .long {
						sub.imageWidth = UInt(try entry.val_long()[0])
					} else {
						sub.imageWidth = UInt(try entry.val_short()[0])
					}
				case 0xA003:
					// EXIF Image height
					if entry.format == .long {
						sub.imageHeight = try UInt(entry.val_long()[0])
					} else {
						sub.imageHeight = try UInt(entry.val_short()[0])
					}
				case 0xA20E:
					// EXIF Focal plane X-resolution
					sub.lensInfo.focalPlaneXResolution = try entry.val_rational()[0].double()
				case 0xA20F:
					// EXIF Focal plane Y-resolution
					sub.lensInfo.focalPlaneYResolution = try entry.val_rational()[0].double()
				case 0xA210:
					// EXIF Focal plane resolution unit
					sub.lensInfo.focalPlaneResolutionUnit = try entry.val_short()[0]
				case 0xA405:
					// Focal length in 35mm film
					sub.focalLengthIn35mm = try entry.val_short()[0]
				case 0xA432:
					// Focal length and FStop.
					let list = try entry.val_rational()
					if list.count > 0 {
						sub.lensInfo.focalLengthMin = list[0].double()
					}
					if list.count > 1 {
						sub.lensInfo.focalLengthMax = list[1].double()
					}
					if list.count > 2 {
						sub.lensInfo.fStopMin = list[2].double()
					}
					if list.count > 3 {
						sub.lensInfo.fStopMax = list[3].double()
					}
				case 0xA433:
					// Lens make.
					sub.lensInfo.make = try entry.val_ascii()
				case 0xA434:
					// Lens model.
					sub.lensInfo.model = try entry.val_ascii()
				case 0x9000:
					// ExifVersion
					break
				default:
					// ignore
#if VERBOSE
					let hex = String(result.tag, radix: 16, uppercase: false)
					print("Unsupported subtype \(hex)")
					#endif
				}
			} catch {
				print("\(error)")
			}
		}
		return sub
	}

	private static func parseGps(tiff: ArraySlice<UInt8>,
								 offs: Int,
								 endian: Endian) throws -> GPS
	{
		var geo: GPS = GPS()
		let entries = try Self.parseDirectory(tiff: tiff,
											  offs: offs,
											  endian: endian)
		for entry in entries {
			do {
				switch entry.tag {
				case 1:
					// GPS north or south
					guard let dir = try entry.val_ascii().first else { throw ExifError.invalidFormat }
					geo.latComponents.direction = dir
				case 2:
					// GPS latitude
					guard entry.length == 3 else {
						throw ExifError.invalidFormat
					}
					geo.latComponents.degrees = try entry.val_rational()[0].double()
					geo.latComponents.minutes = try entry.val_rational()[1].double()
					geo.latComponents.seconds = try entry.val_rational()[2].double()
				case 3:
					// GPS east or west
					guard let dir = try entry.val_ascii().first else { throw ExifError.invalidFormat }
					geo.lonComponents.direction = dir
				case 4:
					// GPS longitude
					guard entry.length == 3 else {
						throw ExifError.invalidFormat
					}
					geo.lonComponents.degrees = try entry.val_rational()[0].double()
					geo.lonComponents.minutes = try entry.val_rational()[1].double()
					geo.lonComponents.seconds = try entry.val_rational()[2].double()
				case 5:
					// GPS altitude reference (below or above sea level)
					geo.altitudeRef = Int8(try entry.val_byte()[0])
					if geo.altitudeRef == 1, let alt = geo.altitude {
						geo.altitude = -alt
					}
				case 6:
					// GPS altitude
					geo.altitude = try entry.val_rational()[0].double()
					if let ref = geo.altitudeRef, ref == 1 {
						geo.altitude = -geo.altitude!
					}
				case 11:
					// GPS degree of precision (DOP)
					geo.dop = try entry.val_rational()[0].double()
				case 16:
					// GPX direction
					// T=true,M=magnetic
					geo.imgDirectionRef = try entry.val_ascii().first
				case 17:
					// GPX direction
					geo.imgDirection = try entry.val_rational()[0].double()
					if geo.imgDirectionRef == "M" {
						// convert magnetic north to true north
					}
				default:
					// Other
					break
				}
			} catch {
				print("\(error)")
			}
		}
		return geo
	}
}
