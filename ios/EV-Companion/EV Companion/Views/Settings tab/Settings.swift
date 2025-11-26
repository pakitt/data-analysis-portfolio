//
//  Settings.swift
//  EV Companion
//
//  Created by Paolo on 1/26/24.
//

import SwiftUI

struct Settings: View {
    
    @EnvironmentObject var sharedVariables: SharedVariables
    
    
    @State private var initialMpgSelection: Double = 15.0
    // @State var mpgSelection = Array(1...100)
    @State var initialGasPrice = 4.00
    @State private var isEditing = false
    
    // @AppStorage("mpg") var mpg: Int = 15
    // @AppStorage("gasPrice") var gasPrice: Double = 4.0
    
    var body: some View {
        VStack {
            
            Text("Global")
                .font(.title)
            ScrollView{
                GroupBox{
                    HStack{
                        Text("Average MPG:")
                        Picker("MPG selection", selection: $initialMpgSelection) {
                            ForEach(Array(stride(from: 1.0, through: 100.0, by: 1.0)), id:\.self) { value in
                                Text(String(format:"%.0f", value)).tag(value)
                            }
                        }
                        .pickerStyle(WheelPickerStyle())
                        .onChange(of: initialMpgSelection) {oldvalue, newValue in
                            sharedVariables.mpg = newValue
                        }
                    }
                    .frame(height: 110.0)
                }
                GroupBox{
                    HStack{
                        Text("Price for gallon of gas:")
                            .font(.headline)
                        Text("$\(initialGasPrice, specifier: "%.2f")")
                            .foregroundColor(isEditing ? .red : .blue)
                    }
                    
                    Slider(value: $initialGasPrice, in: 0...10, step: 0.1) {
                        Text("Price for gallon of gas")
                    } minimumValueLabel: {
                        Text("$0")
                    } maximumValueLabel: {
                        Text("$10")
                    } onEditingChanged: { editing in
                        isEditing = editing
                    }
                    .onChange(of: initialGasPrice) { oldValue, newValue in
                        sharedVariables.gasPrice = newValue
                    }
                }
                GroupBox{
                    HStack{
                        Spacer()
                        Text("Units")
                        Picker(selection: /*@START_MENU_TOKEN@*/.constant(1)/*@END_MENU_TOKEN@*/, label: /*@START_MENU_TOKEN@*/Text("Picker")/*@END_MENU_TOKEN@*/) {
                            Text("Imperial (US)").tag(1)
                            Text("Metric").tag(2)
                        }
                        Spacer()
                    }
                }
            }
        //    .padding()
        }
    }
}
struct Settings_Previews: PreviewProvider {
    static var previews: some View {
        Settings()
            .environmentObject(SharedVariables())
    }
    
}

