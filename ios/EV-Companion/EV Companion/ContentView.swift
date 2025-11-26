//
//  ContentView.swift
//  EV Companion
//
//  Created by Paolo on 1/26/24.
//

import SwiftUI

struct ContentView: View {
    
    @EnvironmentObject var sharedVariables: SharedVariables
    
    var body: some View {
        
        TabView {
            ChargingCostskWh()
                .tabItem {
                    Label("Costs", systemImage: "bolt")
                }
            UtilConv()
                .tabItem {
                    Label("Utilities & Conversions", systemImage: "arrow.left.arrow.right")
                }
            SettingsMain()
                .tabItem {
                    Label("Settings", systemImage: "gear")
                }
        }
        
    }
    
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
            .environmentObject(SharedVariables())
    }
}
