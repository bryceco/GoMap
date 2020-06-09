//
//  Colors.swift
//  Go Map!!
//
//  Created by Bryce Cogswell on 6/8/20.
//  Copyright © 2020 Bryce. All rights reserved.
//

import Foundation

class Colors : UIColor {

	@objc static func colorForColorName(_ string : String) -> UIColor?
	{
		var hex : String;
		switch string {
			case "black":	hex = "#000000"
			case "silver":	hex = "#C0C0C0"
			case "gray":	hex = "#808080"
			case "white":	hex = "#FFFFFF"
			case "maroon":	hex = "#800000"
			case "red":		hex = "#FF0000"
			case "purple":	hex = "#800080"
			case "fuchsia":	hex = "#FF00FF"
			case "green":	hex = "#008000"
			case "lime":	hex = "#00FF00"
			case "olive":	hex = "#808000"
			case "yellow":	hex = "#FFFF00"
			case "navy":	hex = "#000080"
			case "blue":	hex = "#0000FF"
			case "teal":	hex = "#008080"
			case "aqua":	hex = "#00FFFF"
			default:		hex = string
		}
		let scanner = Scanner(string:hex)
		guard scanner.scanString("#", into:nil) else { return nil }
		let bits = hex.count == 4 ? 4 : hex.count == 7 ? 8 : 0;
		guard bits > 0 else { return nil }
		var i : UInt64 = 0;
		guard scanner.scanHexInt64(&i) && scanner.isAtEnd else { return nil }
		let mask : UInt64 = (1 << bits) - 1;
		return UIColor(red: 	CGFloat( (i>>(2*bits)) & mask) / CGFloat(mask),
					   green: 	CGFloat( (i>>(1*bits)) & mask) / CGFloat(mask),
					   blue: 	CGFloat( (i>>(0*bits)) & mask) / CGFloat(mask),
					   alpha: 	1.0)
	}
}
