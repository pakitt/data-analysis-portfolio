//
//  MyEV.swift
//  EV Companion
//
//  Created by Paolo on 1/26/24.
//

import SwiftUI

struct MyEV: View {
    @EnvironmentObject var sharedVariables: SharedVariables
    
    @State private var isSheetVisible = false
    @State private var isEditing1 = false
    @State private var isEditing2 = false
    @State private var showAnotherView = false
    
    @AppStorage("evEfficiency") var evEfficiency: Double = 3.0
    @AppStorage("batterySize") var batterySize: Double = 50.0
    @AppStorage("nickName") var nickName: String = ""
    
    var body: some View {
        VStack {
            
            
            Text("My EV")
                .font(.title)
            ScrollView{
                GroupBox{
                    TextField("Your EV's Nickname", text: $nickName)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .onChange(of: nickName) { oldValue, newValue in
                            nickName = newValue
                        }
                }
                
                
                //  TextField("Make (optional)", text: $inputMake)
                //   .textFieldStyle(RoundedBorderTextFieldStyle())
                
                // TextField("Model (optional)", text: $inputModel)
                // .textFieldStyle(RoundedBorderTextFieldStyle())
                
      //          .padding(.horizontal)
                
                GroupBox{
                    HStack{
                        Text("Average consumption:")
                            .font(.headline)
                        Text("\(evEfficiency, specifier: "%.1f")")
                            .foregroundColor(isEditing1 ? .red : .blue)
                        Text("mi/kWh")
                    }
                    
                    Slider(value: $evEfficiency, in: 0...10, step: 0.1) {
                        Text("Average consumption in mi/kWh")
                    } minimumValueLabel: {
                        Text("0")
                    } maximumValueLabel: {
                        Text("10")
                    } onEditingChanged: { editing in
                        isEditing1 = editing
                    }
                    .onChange(of: evEfficiency) { oldValue, newValue in
                        evEfficiency = newValue
                    }
                    //        globalData.updateEVEfficiency(with: newValue)
                    //        userDefaults.set(newValue, forKey: KeyValue.evEfficiency.rawValue)
                }
                
        //        .padding(.horizontal)
                
                GroupBox{
                    HStack{
                        Text("Battery Size (available):")
                            .font(.headline)
                        Text("\(batterySize, specifier: "%.1f")")
                            .foregroundColor(isEditing2 ? .red : .blue)
                        Text("kWh")
                    }
                    Slider(value: $batterySize, in: 0...300, step: 0.1) {
                        Text("Battery Size (usable)")
                    } minimumValueLabel: {
                        Text("0")
                    } maximumValueLabel: {
                        Text("300")
                    } onEditingChanged: { editing in
                        isEditing2 = editing
                    }
                    //   .onChange(of: batterySize) { oldValue, newValue in
                    //        userDefaults.set(newValue, forKey: KeyValue.batterySize.rawValue)
                    //        globalData.updateBatterySize(with: newValue)
                    
                    
                    // .padding(.horizontal)
                    
                    let textWithSheet = "What does 'available' mean?"
                    Text("\(textWithSheet)")
                        .foregroundColor(Color.blue)
                        .modifier(WordTappableTextModifier(isSheetVisible: $isSheetVisible, sheetText: textWithSheet))
                        .onTapGesture {
                            showAnotherView.toggle()
                        }
                    if showAnotherView {
                        UtilConv()
                        
                    }
                    
                }
     //           .padding(.horizontal)
            }
        }
    }
}


struct MyEV_Previews: PreviewProvider {
    static var previews: some View {
        MyEV()
            .environmentObject(SharedVariables())
    }
}
