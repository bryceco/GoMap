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

	let healthStore = HKHealthStore()

	private func locationsFor(route: HKWorkoutRoute, completion: @escaping (Result<[CLLocation], Error>) -> Void) {
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

	private func getWorkoutRoutes2(completion: @escaping (Result<[HKWorkoutRoute]?, Error>) -> Void) {
		// Check if HealthKit is available on the device
		guard HKHealthStore.isHealthDataAvailable() else {
			completion(.failure(
				NSError(domain: "com.example.healthkit", code: 1,
				        userInfo: [NSLocalizedDescriptionKey: "HealthKit is not available on this device."])))
			return
		}

		// Asynchronously request authorization to the data.
		let types = [HKObjectType.workoutType(),
		             HKSeriesType.workoutRoute()]

		healthStore.requestAuthorization(toShare: nil, read: Set(types)) { _, error in
			let sortByDate = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)
			// FIXME: We'd like to use this predicate but it crashes for some reason
			// let activities: Set<HKWorkoutActivityType> = [.walking, .running, .cycling]
			// let activityPredicates = activities.map { HKQuery.predicateForWorkouts(with: $0) }
			// let predicate = NSCompoundPredicate(orPredicateWithSubpredicates: activityPredicates)

			let routeQuery = HKSampleQuery(
				sampleType: HKSeriesType.workoutRoute(),
				predicate: nil, // predicate,
				limit: HKObjectQueryNoLimit,
				sortDescriptors: [sortByDate]) { _, samples, error in
					if let error = error {
						completion(.failure(error))
						return
					}

					// Process the route data (samples) here
					if let routes = samples as? [HKWorkoutRoute] {
						completion(.success(routes))
					} else {
						completion(.failure(
							NSError(domain: "com.example.healthkit", code: 2,
							        userInfo: [NSLocalizedDescriptionKey: "No route data found."])))
					}
				}

			// Execute the query
			self.healthStore.execute(routeQuery)
		}
	}

	func getWorkoutRoutes(completion: @escaping (Result<[[CLLocation]], Error>) -> Void) {
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
