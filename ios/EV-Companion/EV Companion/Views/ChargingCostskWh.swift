//
//  ChargingCostskWh.swift
//  EV Companion
//
//  Created by Paolo on 1/26/24.
//

import SwiftUI

struct ChargingCostskWh: View {
    
    @EnvironmentObject var sharedVariables: SharedVariables
    
    @State private var isEditing1 = false
    @State private var isEditing2 = false
    @State private var isEditing3 = false
    
    
    @AppStorage("chargeLevelTo")  var chargeLevelTo: Double = 80.0
    @AppStorage("chargeLevelFrom")  var chargeLevelFrom: Double = 20.0
    @AppStorage("costkWh")  var costkWh: Double = 0.45
    @AppStorage("useEstimate") var useEstimate: Bool = false
    
    var body: some View {
        
        var dataSavings = savingsvsGas(startcharge: chargeLevelFrom, endcharge: chargeLevelTo, batterySize: sharedVariables.batterySize, cost: costkWh, mpg: sharedVariables.mpg, evEfficiency: sharedVariables.evEfficiency, gasPrice: sharedVariables.gasPrice)
        
        
        VStack {
            Text("Charging Costs")
                .font(.largeTitle)
            ScrollView {
                GroupBox {
                    HStack{
                        Text("Charge up to:")
                            .font(.headline)
                        Text("\(chargeLevelTo, specifier: "%.f")%")
                            .foregroundColor(isEditing1 ? .orange : .blue)
                    }
                    Slider(value: $chargeLevelTo, in: 0...100, step: 5) {
                        Text("Charge up to")
                    } minimumValueLabel: {
                        Text("0%")
                    } maximumValueLabel: {
                        Text("100%")
                    } onEditingChanged: { editing in
                        isEditing1 = editing
                    }
                    .onChange(of: chargeLevelTo) { oldValue, newValue in
                        chargeLevelTo = newValue
                    }
                    
                    
                    HStack{
                        Text("From:")
                            .font(.headline)
                        Text("\(chargeLevelFrom, specifier: "%.f")%")
                            .foregroundColor(isEditing2 ? .orange : .blue)
                    }
                    Slider(value: $chargeLevelFrom,    in: 0...100, step: 1) {
                        Text("Charge up to")
                    } minimumValueLabel: {
                        Text("0%")
                    } maximumValueLabel: {
                        Text("100%")
                    } onEditingChanged: { editing in
                        isEditing2 = editing
                    }
                    .onChange(of: chargeLevelFrom) { oldValue, newValue in
                        chargeLevelFrom = newValue
                    }
                    
                    HStack{
                        Text("Cost per kWh:")
                            .font(.headline)
                        Text("$\(costkWh, specifier: "%.2f")")
                            .foregroundColor(isEditing3 ? .orange : .blue)
                    }
                    Slider(value: $costkWh, in: 0...1.00, step: 0.01) {
                        Text("Charge up to")
                    } minimumValueLabel: {
                        Text("$0.00")
                    } maximumValueLabel: {
                        Text("$1.00")
                    } onEditingChanged: { editing in
                        isEditing3 = editing
                    }
                    .onChange(of: costkWh) { oldValue, newValue in
                        costkWh = newValue
                    }
                }
                
                
                GroupBox {
                    HStack{
                        Spacer()
                        VStack{
                            HStack {
                                Text("This charge:")
                                
                                if chargeLevelTo < chargeLevelFrom {
                                    Text("---")
                                        .foregroundColor(.red)
                                    
                                } else {
                                    Text("\(kwhCharged(startcharge: chargeLevelFrom, endcharge: chargeLevelTo, batterySize: sharedVariables.batterySize), specifier: "%.2f") kWh")
                                    
                                }
                            }
                            HStack {
                                Text("Total cost:")
                                
                                if chargeLevelTo < chargeLevelFrom {
                                    Text("---")
                                        .foregroundColor(.red)
                                    
                                } else {
                                    Text("$\(costPerCharge(startcharge: chargeLevelFrom, endcharge: chargeLevelTo, batterySize: sharedVariables.batterySize, cost: costkWh), specifier: "%.2f")")
                                    
                                }
                            }
                        }
                        
                        Spacer()
                    }
                    .font(.title)
                }
                
                GroupBox {
                    if dataSavings.percentageSavings > 0 {
                        HStack {
                            Spacer()
                            VStack(alignment: .center) {
                                Text("Driving your EV at \(sharedVariables.evEfficiency, specifier: "%.1f") mi/kWh is")
                                    .multilineTextAlignment(.center)
                                Text("$\(dataSavings.absoluteSavings, specifier: "%.2f") more expensive")
                                    .fontWeight(.bold)
                                    .multilineTextAlignment(.center)
                                Text("than a \(sharedVariables.mpg, specifier: "%.f") MPG car using gas at $\(sharedVariables.gasPrice, specifier: "%.2f")/gal")
                                    .multilineTextAlignment(.center)
                                
                            }
                            Spacer()
                        }
                    } else {
                        HStack{
                            Spacer()
                            VStack {
                                Text("🎉 Savings! 🎉")
                                    .font(.title)
                                    .bold()
                                Text("Your EV is saving you")
                                Spacer()
                                HStack {
                                    Text("$\(dataSavings.absoluteSavings, specifier: "%.2f")")
                                        .font(.title2)
                                        .bold()
                                        .foregroundColor(.green)
                                    // Text(" or ")
                                    // Text("\(dataSavings.percentageSavings, specifier: "%.f")%")
                                }
                                Text("compared to a \(sharedVariables.mpg, specifier: "%.f") MPG gas car filled at $\(sharedVariables.gasPrice, specifier: "%.2f")/gal")
                                    .multilineTextAlignment(.center)
                            }
                            Spacer()
                            
                        }
                        .padding(.horizontal)
                    }
                }
                .font(.title3)
                .onAppear(perform: {
                    dataSavings.absoluteSavings = 0.0
                    dataSavings.percentageSavings = 0.0
                })
                
                GroupBox {
                    VStack(alignment: .leading){
                        Text("My EV battery size is: \(sharedVariables.batterySize, specifier: "%.1f") kWh")
                        Spacer()
                        HStack {
                            Spacer()
                            Text("or")
                            Spacer()
                        }
                        Spacer()
                        Toggle(isOn: $useEstimate) {
                            Text("Use the estimated battery size of \(sharedVariables.estimatedBatterySize, specifier: "%.1f") kWh instead")
                            
                                .onChange(of: useEstimate) {oldValue, newValue in
                                    useEstimate = newValue
                                    if newValue == true {
                                        sharedVariables.batterySize =  sharedVariables.estimatedBatterySize
                                    }
                                    else {
                                        sharedVariables.batterySize = sharedVariables.batterySize
                                    }
                                }
                        }
                    }
                }
                
                Spacer()
            }
            .padding()
            
        }
        .scrollIndicators(.hidden)
    }
}


func kwhCharged(startcharge: Double, endcharge: Double, batterySize: Double) -> Double {
    return((endcharge-startcharge)/100.0*batterySize)
}
func costPerCharge(startcharge: Double, endcharge: Double, batterySize: Double, cost: Double) -> Double {
    return(kwhCharged(startcharge:startcharge, endcharge:endcharge, batterySize:batterySize)*cost)
}

func savingsvsGas(startcharge: Double, endcharge: Double, batterySize: Double, cost: Double, mpg:Double, evEfficiency: Double, gasPrice: Double) -> (absoluteSavings: Double, percentageSavings: Double){
    let gallonsAsEV = kwhCharged(startcharge: startcharge, endcharge: endcharge, batterySize: batterySize) * evEfficiency / mpg
    let costGas = gallonsAsEV * gasPrice
    let absoluteSavings = costPerCharge(startcharge: startcharge, endcharge: endcharge, batterySize: batterySize, cost: cost) - costGas
    let percentageSavings = absoluteSavings / costGas * 100.0
    return (absoluteSavings,percentageSavings)
}


struct ChargingCost_Previews: PreviewProvider {
    static var previews: some View {
        ChargingCostskWh()
            .environmentObject(SharedVariables())
    }
}
