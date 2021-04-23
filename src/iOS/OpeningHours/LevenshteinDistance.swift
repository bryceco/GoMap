//
//  LevenshteinDistance.swift
//  OpeningHoursPhoto
//
//  Created by Bryce Cogswell on 4/20/21.
//

import Foundation

func LevenshteinDistance(_ w1: String, _ w2: String) -> Int {
	let empty = [Int](repeating:0, count: w2.count)
	var last = [Int](0...w2.count)

	for (i, char1) in w1.enumerated() {
		var cur = [i + 1] + empty
		for (j, char2) in w2.enumerated() {
			cur[j + 1] = char1 == char2 ? last[j] : min(last[j], last[j + 1], cur[j]) + 1
		}
		last = cur
	}
	return last.last!
}
