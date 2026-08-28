//
//  HealthKitRoutes.swift
//  Go Map!!
//
//  Created by Bryce Cogswell on 2/27/24.
//  Copyright © 2024 Bryce Cogswell. All rights reserved.
//

import CoreLocation
import Foundation
import HealthKit

class HealthKitRoutes {
	static let shared = HealthKitRoutes()

	private enum Error: LocalizedError {
		case notAvailable
		case noRouteData

		var errorDescription: String? {
			switch self {
			case .notAvailable: return NSLocalizedString("HealthKit is not available on this device.", comment: "")
			case .noRouteData: return NSLocalizedString("No route data found.", comment: "")
			}
		}
	}

	let healthStore = HKHealthStore()

	private func locationsFor(route: HKWorkoutRoute, completion: @escaping (Result<[CLLocation], Swift.Error>) -> Void) {
		var allLocations: [CLLocation] = []

		// Create the route query.
		let query = HKWorkoutRouteQuery(route: route) { _, locationsOrNil, done, errorOrNil in
			guard let currentLocationBatch = locationsOrNil else {
				completion(.failure(errorOrNil!))
				return
			}
			allLocations.append(contentsOf: currentLocationBatch)
			if done {
				completion(.success(allLocations))
			}
		}
		healthStore.execute(query)
	}

	private func getWorkoutRoutes2(completion: @escaping (Result<[HKWorkoutRoute]?, Swift.Error>) -> Void) {
		// Check if HealthKit is available on the device
		guard HKHealthStore.isHealthDataAvailable() else {
			completion(.failure(Error.notAvailable))
			return
		}

		// Asynchronously request authorization to the data.
		let types = [HKObjectType.workoutType(),
		             HKSeriesType.workoutRoute()]

		healthStore.requestAuthorization(toShare: nil, read: Set(types)) { _, error in
			let sortByDate = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)
			let startDate = Calendar.current.date(byAdding: .day, value: -31, to: Date())!
			let predicate = HKQuery.predicateForSamples(withStart: startDate, end: nil, options: [])

			let routeQuery = HKSampleQuery(
				sampleType: HKSeriesType.workoutRoute(),
				predicate: predicate,
				limit: HKObjectQueryNoLimit,
				sortDescriptors: [sortByDate])
			{ _, samples, error in
				if let error = error {
					completion(.failure(error))
					return
				}

				// Process the route data (samples) here
				if let routes = samples as? [HKWorkoutRoute] {
					completion(.success(routes))
				} else {
					completion(.failure(Error.noRouteData))
				}
			}

			// Execute the query
			self.healthStore.execute(routeQuery)
		}
	}

	func getWorkoutRoutes(completion: @escaping (Result<[[CLLocation]], Swift.Error>) -> Void) {
		getWorkoutRoutes2(completion: { result in
			if case let .failure(error) = result {
				completion(.failure(error))
				return
			}
			let routes = (try! result.get())!
			if routes.isEmpty {
				DispatchQueue.main.async(execute: {
					completion(.success([]))
				})
				return
			}
			var allRoutes: [[CLLocation]] = []
			for route in routes {
				self.locationsFor(route: route, completion: { result in
					// append to our array on main thread so its synchronized
					DispatchQueue.main.async(execute: {
						switch result {
						case let .failure(error):
							completion(.failure(error))
							return
						case let .success(locations):
							allRoutes.append(locations)
							if allRoutes.count == routes.count {
								completion(.success(allRoutes))
							}
						}
					})
				})
			}
		})
	}
}
