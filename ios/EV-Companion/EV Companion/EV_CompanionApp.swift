//
//  EV_CompanionApp.swift
//  EV Companion
//
//  Created by Paolo on 1/26/24.
//

import SwiftUI

@main
struct EV_CompanionApp: App {
    @StateObject private var sharedVariables = SharedVariables()
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(SharedVariables())
        }
    }
}
