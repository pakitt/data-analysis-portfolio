//
//  SharedVariables.swift
//  EV Companion
//
//  Created by Paolo Vasta on 7/23/24.
//

import Foundation
import SwiftUI

class SharedVariables: ObservableObject {
    
    //EV parameters
    @AppStorage("estimatedBatterySize") var estimatedBatterySize: Double = 40.0
    @AppStorage("evEfficiency") var evEfficiency: Double = 3.0
    @AppStorage("batterySize") var batterySize: Double = 80.0
    
    //Gas vehicle parameters
    @AppStorage("mpg") var mpg: Double = 30.0

    //Market variables
    @AppStorage("gasPrice") var gasPrice: Double = 4.0
    
    
    //Shared conversion parameters
     @AppStorage("mikWH") var mikWH: Double = 0.0
     @AppStorage("kmkWH") var kmkWH: Double = 0.0
   
     //Electricty conversion parameters
     @AppStorage("whMi") var whMi: Double = 0.0
     @AppStorage("whKm") var whKm: Double = 0.0
     @AppStorage("kwhHundredKm") var kwhHundredKm: Double = 0.0
    
     //EV <-> Gas conversion parameters
     @AppStorage("mpgE") var mpgE: Double = 0.0
   
     //Gas conversion parameters
     @AppStorage("galHundredMi") var galHundredMi: Double = 0.0
     @AppStorage("literHundredKm") var literHundredKm: Double = 0.0
     @AppStorage("kmLiter") var kmLiter: Double = 0.0
    
}
