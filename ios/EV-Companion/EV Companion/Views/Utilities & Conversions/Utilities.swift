//
//  Utilities.swift
//  EV Companion
//
//  Created by Paolo on 1/26/24.
//

import SwiftUI

struct Utilities: View {
    @EnvironmentObject var sharedVariables: SharedVariables
    
    @State private var chargedTo: Double = 80.0
    @State private var chargedFrom: Double = 20.0
    @State private var howManykWh: Double = 50.0
    
    
    @State private var isEditing1 = false
    @State private var isEditing2 = false
    @State private var isEditing3 = false
    
    var body: some View {
        
        
        VStack {
            GroupBox {
                Text("How big is my EV's battery?")
                    .font(.title3)
                    .fontWeight(.bold)
                    .multilineTextAlignment(.center)
                    .padding(.bottom)
                
                Text("Estimate your battery size, if unknown, using information from your last charging session:")
                    .font(.body)
                    .padding(.bottom)
                
                GroupBox {
                    HStack{
                        Text("Charged up to:")
                            .font(.headline)
                        Text("\(chargedTo, specifier: "%.f")%")
                            .foregroundColor(isEditing1 ? .red : .blue)
                    }
                    Slider(value: $chargedTo, in: 0...100, step: 5) {
                        Text("Charge up to")
                    } minimumValueLabel: {
                        Text("0%")
                    } maximumValueLabel: {
                        Text("100%")
                    } onEditingChanged: { editing in
                        isEditing1 = editing
                        sharedVariables.estimatedBatterySize = estimateBatterySize(startcharge: chargedFrom, endcharge: chargedTo, kWhCharged: howManykWh)
                    }
                    
                    HStack{
                        Text("From:")
                            .font(.headline)
                        Text("\(chargedFrom, specifier: "%.f")%")
                            .foregroundColor(isEditing2 ? .red : .blue)
                    }
                    Slider(value: $chargedFrom,    in: 0...100, step: 1) {
                        Text("Charged up to")
                    } minimumValueLabel: {
                        Text("0%")
                    } maximumValueLabel: {
                        Text("100%")
                    } onEditingChanged: { editing in
                        isEditing2 = editing
                        sharedVariables.estimatedBatterySize = estimateBatterySize(startcharge: chargedFrom, endcharge: chargedTo, kWhCharged: howManykWh)
                    }
                    
                    HStack{
                        Text("How many kWh charged:")
                            .font(.headline)
                        Text("\(howManykWh, specifier: "%.1f")")
                            .foregroundColor(isEditing3 ? .red : .blue)
                    }
                    Slider(value: $howManykWh, in: 0...150, step: 0.1) {
                        Text("Charge up to")
                    } minimumValueLabel: {
                        Text("0 kWh")
                    } maximumValueLabel: {
                        Text("150 kWh")
                    } onEditingChanged: { editing in
                        isEditing3 = editing
                        sharedVariables.estimatedBatterySize = estimateBatterySize(startcharge: chargedFrom, endcharge: chargedTo, kWhCharged: howManykWh)
                    }
                    .padding()
                    
                    VStack{
                        Text("The estimated battery size for your EV is:")
                        Text("\(sharedVariables.estimatedBatterySize, specifier: "%.1f") kWh (±5%)")
                            .fontWeight(.bold)
                    }
                }
            }
            
            
        }
        if isEditing1 == true || isEditing2 == true || isEditing3 == true {
            // self.estimatedBatterySize = calcBatterySize
        }
        
    }
    
}

func estimateBatterySize(startcharge: Double, endcharge: Double, kWhCharged: Double) -> Double {
    return (kWhCharged/(endcharge-startcharge)*100.0)
}


struct Utilities_Previews: PreviewProvider {
    static var previews: some View {
        Utilities()
            .environmentObject(SharedVariables())
    }
}


