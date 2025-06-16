//
//  SceneDelegate.swift
//  Go Map!!
//
//  Created by Bryce Cogswell on 6/14/25.
//  Copyright © 2025 Bryce Cogswell. All rights reserved.
//
import UIKit

class SceneDelegate: UIResponder, UIWindowSceneDelegate {
	var window: UIWindow?

	func scene(_ scene: UIScene,
	           willConnectTo session: UISceneSession,
	           options connectionOptions: UIScene.ConnectionOptions)
	{
		guard let windowScene = scene as? UIWindowScene else { return }
		let window = UIWindow(windowScene: windowScene)

		// Load the initial view controller from Main.storyboard
		let storyboard = UIStoryboard(name: "MainStoryboard", bundle: nil)
		let rootViewController = storyboard.instantiateInitialViewController()

		window.rootViewController = rootViewController
		self.window = window
		window.makeKeyAndVisible()
	}
}
