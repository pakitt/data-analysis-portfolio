//
//  Untitled.swift
//  EV Companion
//
//  Created by Paolo Vasta on 01/05/2025.
//

import SwiftUI

struct SettingsMain: View {
    
    @EnvironmentObject var sharedVariables: SharedVariables
    
    @AppStorage("selectionSettingsSheet") private var selectionSettingsSheet = 1
   
    var body: some View {
        VStack {
            Text("Settings")
                .font(.largeTitle)
            Picker(selection: $selectionSettingsSheet, label: Text("Picker")) {
                Image(systemName: "gear").tag(1)
                Image(systemName: "car").tag(2)
            }
            .pickerStyle(SegmentedPickerStyle())
            .padding(.horizontal)
            
            ScrollView{
                if selectionSettingsSheet == 1 {
                    Settings()
                } else
                {
                    MyEV()
                }
                Spacer()
            }
            .padding()
        
    }
    
    }
}
struct SettingsMain_Previews: PreviewProvider {
    static var previews: some View {
        SettingsMain()
            .environmentObject(SharedVariables())
    }
    
}

