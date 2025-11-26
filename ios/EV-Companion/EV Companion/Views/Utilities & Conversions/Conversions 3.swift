//
//  Conversions3.swift
//  EV Companion
//
//  Created by Paolo Vasta on 31/05/2025.
//


//
//  Conversions 3.swift
//  EV Companion
//
//  Created by Paolo Vasta on 5/31/25.
//

import SwiftUI
// testcomment added in Git
// additional comment to add in Git

// MARK: - Data Models

struct Conversion: Identifiable {
    let id = UUID()
    let name: String
    let fromUnit: String
    let toUnit: String
}

struct ConversionCategory: Identifiable {
    let id = UUID()
    let name: String
    let conversions: [Conversion]
}

// MARK: - Sample Data

let conversionCategories: [ConversionCategory] = [
    ConversionCategory(name: "Electricity", conversions: [
        Conversion(name: "mi/kWh to Wh/mi", fromUnit: "mi/kWh", toUnit: "Wh/mi"),
        Conversion(name: "Wh/mi to mi/kWh", fromUnit: "Wh/mi", toUnit: "mi/kWh"),
        Conversion(name: "km/kWh to Wh/km", fromUnit: "km/kWh", toUnit: "Wh/km"),
        Conversion(name: "Wh/km to km/kWh", fromUnit: "Wh/km", toUnit: "km/kWh"),
        Conversion(name: "km/kWh to kWh/100km", fromUnit: "km/kWh", toUnit: "kWh/100km"),
        Conversion(name: "kWh/100km to km/kWh", fromUnit: "kWh/100km", toUnit: "km/kWh"),
        Conversion(name: "Wh/km to kWh/100km", fromUnit: "Wh/km", toUnit: "kWh/100km"),
        Conversion(name: "kWh/100km to Wh/km", fromUnit: "kWh/100km", toUnit: "Wh/km")
    ]),
    ConversionCategory(name: "EV ↔️ Gas", conversions: [
        Conversion(name: "mi/kWh to MPGe", fromUnit: "mi/kWh", toUnit: "MPGe"),
        Conversion(name: "MPGe to mi/kWh", fromUnit: "MPGe", toUnit: "mi/kWh"),
        Conversion(name: "mi/kWh to km/kWh", fromUnit: "mi/kWh", toUnit: "km/kWh"),
        Conversion(name: "km/kWh to mi/kWh", fromUnit: "km/kWh", toUnit: "mi/kWh"),
        Conversion(name: "MPGe to km/kWh", fromUnit: "MPGe", toUnit: "km/kWh"),
        Conversion(name: "km/kWh to MPGe", fromUnit: "km/kWh", toUnit: "MPGe")
    ]),
    ConversionCategory(name: "Gas", conversions: [
        Conversion(name: "MPG to Gal/100mi", fromUnit: "MPG", toUnit: "Gal/100mi"),
        Conversion(name: "Gal/100mi to MPG", fromUnit: "Gal/100mi", toUnit: "MPG"),
        Conversion(name: "MPG to L/100km", fromUnit: "MPG", toUnit: "L/100km"),
        Conversion(name: "L/100km to MPG", fromUnit: "L/100km", toUnit: "MPG"),
        Conversion(name: "MPG to km/L", fromUnit: "MPG", toUnit: "km/L"),
        Conversion(name: "km/L to MPG", fromUnit: "km/L", toUnit: "MPG"),
        Conversion(name: "Gal/100mi to L/100km", fromUnit: "Gal/100mi", toUnit: "L/100km"),
        Conversion(name: "L/100km to Gal/100mi", fromUnit: "L/100km", toUnit: "Gal/100mi"),
        Conversion(name: "Gal/100mi to km/L", fromUnit: "Gal/100mi", toUnit: "km/L"),
        Conversion(name: "km/L to Gal/100km", fromUnit: "km/L", toUnit: "Gal/100mi"),
        Conversion(name: "L/100km to km/L", fromUnit: "L/100km", toUnit: "km/L"),
        Conversion(name: "km/L to L/100km", fromUnit: "km/L", toUnit: "L/100km")
    ])
]

// MARK: - Main App View

struct Conversions3: View {
    @State private var selectedCategoryIndex = 0
    @State private var selectedConversionIndex = 0
    
    var body: some View {
        GroupBox {
            NavigationView {
                VStack(spacing: 20) {
                    // Category Picker
                    Picker("Category", selection: $selectedCategoryIndex) {
                        ForEach(0..<conversionCategories.count, id: \.self) { index in
                            Text(conversionCategories[index].name)
                        }
                    }
                    .pickerStyle(.wheel)
                    
                    // Conversion Picker
                    Picker("Conversion", selection: $selectedConversionIndex) {
                        ForEach(0..<conversionCategories[selectedCategoryIndex].conversions.count, id: \.self) { index in
                            Text(conversionCategories[selectedCategoryIndex].conversions[index].name)
                        }
                    }
                    .pickerStyle(.wheel)
                    
                    // Display selected conversion UI
                    ConversionView(
                        conversion: conversionCategories[selectedCategoryIndex].conversions[selectedConversionIndex]
                    )
                    
                    Spacer()
                }
                .padding()
            }
        }
    }
}

// MARK: - Conversion View

struct ConversionView: View {
    let conversion: Conversion
    @State private var inputValue: String = ""
    
    var convertedValue: String {
        guard let input = Double(inputValue) else { return "-" }
        
        // Logic for conversions
        // 1gal = 33.7kWh
        // 1 MPGe    ≈ 1 mi/(33.70 kW·h)
        // ≈ 0.02967 mi/kW·h
        // ≈ 0.04775 km/kW·h
        
        switch conversion.name {
        case "mi/kWh to Wh/mi":
            return String(format: "%.2f", 1000 / input)
        case "Wh/mi to mi/kWh":
            return String(format: "%.2f", 1000 / input)
        case "km/KWh to Wh/km":
            return String(format: "%.2f", )
        case "Celsius to Fahrenheit":
            return String(format: "%.2f", input * 9 / 5 + 32)
        default:
            return "-"
        }
    }
    
    var body: some View {
        VStack(spacing: 12) {
            TextField("Enter value in \(conversion.fromUnit)", text: $inputValue)
                .keyboardType(.decimalPad)
                .textFieldStyle(.roundedBorder)
                .padding(.horizontal)
            
            Text("Converted to \(conversion.toUnit): \(convertedValue)")
                .font(.headline)
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
}

//import SwiftUI
//
//struct Conversions3: View {
//
//    @EnvironmentObject var sharedVariables: SharedVariables
//
////   //Shared conversion parameters
////    @AppStorage("mikWH") var mikWH: Double = 0.0
////    @AppStorage("kmkWH") var kmkWH: Double = 0.0
////
////    //Electricty conversion parameters
////    @AppStorage("whMi") var whMi: Double = 0.0
////    @AppStorage("whKm") var whKm: Double = 0.0
////    @AppStorage("kwhHundredKm") var kwhHundredKm: Double = 0.0
////
////    //EV <-> Gas conversion parameters
////    @AppStorage("mpgE") var mpgE: Double = 0.0
////
////    //Gas conversion parameters
////    @AppStorage("galHundredMi") var galHundredMi: Double = 0.0
////    @AppStorage("literHundredKm") var literHundredKm: Double = 0.0
////    @AppStorage("kmLiter") var kmLiter: Double = 0.0
//
//    @State private var numberFormatter: NumberFormatter = {
//        var nf = NumberFormatter()
//        nf.numberStyle = .decimal
//        return nf
//    }()
//
//    var body: some View {
//        ScrollView {
//            GroupBox {
//                Text("Electricity")
//                    .font(.title2)
//                    .bold()
//                HStack {
//                    Text("Imperial")
//                        .font(.title3)
//                        .underline()
//                    Spacer()
//                }
//                VStack{
//                    HStack() {
//                        Text("mi/kWh:")
//                        TextField("Enter mi/kWh", value: $sharedVariables.mikWH, formatter: numberFormatter)
//                            .textFieldStyle(RoundedBorderTextFieldStyle())
//                            .onSubmit(of: .text) {
//                                sharedVariables.whMi = 1000 / sharedVariables.mikWH
//                                sharedVariables.mpgE = sharedVariables.mikWH / 0.02967
//                            }
//                            .multilineTextAlignment(.center)
//                            .padding(.horizontal)
//
//                    }
//                    HStack() {
//                        Text("Wh/mi:")
//                        TextField("Enter Wh/mi", value: $sharedVariables.whMi, formatter: numberFormatter)
//                            .textFieldStyle(RoundedBorderTextFieldStyle())
//                            .onSubmit(of: .text) {
//                                sharedVariables.mikWH = 1000 / sharedVariables.whMi
//                            }
//                            .multilineTextAlignment(.center)
//                            .padding(.horizontal)
//
//                    }
//                }
//
//
//                HStack{
//                    Text("Metric")
//                        .font(.title3)
//                        .underline()
//                    Spacer()
//                }
//                VStack{
//                    HStack {
//                        Text("km/kWh:")
//                        TextField("Enter km/kWh", value: $sharedVariables.kmkWH, formatter: numberFormatter)
//                            .textFieldStyle(RoundedBorderTextFieldStyle())
//                            .onSubmit(of: .text) {
//                                sharedVariables.whKm = 1000 / sharedVariables.kmkWH
//                                sharedVariables.kwhHundredKm = 100 / sharedVariables.kmkWH
//                                sharedVariables.mpgE = sharedVariables.kmkWH / 0.04775
//                            }
//                            .multilineTextAlignment(.center)
//                            .padding(.horizontal)
//
//                    }
//
//                    HStack{
//                        Text("Wh/km:")
//                        TextField("Enter Wh/km", value: $sharedVariables.whKm, formatter: numberFormatter)
//                            .textFieldStyle(RoundedBorderTextFieldStyle())
//                            .onSubmit(of: .text) {
//                                sharedVariables.kmkWH = 1000 / sharedVariables.whKm
//                                sharedVariables.kwhHundredKm = 10 * sharedVariables.whKm
//                            }
//                            .multilineTextAlignment(.center)
//                            .padding(.horizontal)
//
//                    }
//
//                    HStack{
//                        Text("kWh/100km:")
//                        TextField("Enter kWh/100km", value: $sharedVariables.kwhHundredKm, formatter: numberFormatter)
//                            .textFieldStyle(RoundedBorderTextFieldStyle())
//                            .onSubmit(of: .text) {
//                                sharedVariables.kmkWH = 100 / sharedVariables.kwhHundredKm
//                                sharedVariables.whKm = sharedVariables.kwhHundredKm / 10
//                            }
//                            .multilineTextAlignment(.center)
//                            .padding(.horizontal)
//
//                    }
//                }
//            }
//           // .padding(/*@START_MENU_TOKEN@*/.horizontal/*@END_MENU_TOKEN@*/)
//
//
//            GroupBox {
//                HStack {
//                    Text("EV")
//                        .font(.title2)
//                        .bold()
//                    Image(systemName: "arrow.left.arrow.right")
//                    //      .imageScale(.large)
//                    Text("Gas")
//                        .font(.title2)
//                        .bold()
//
//                    //1gal = 33.7kWh
//                    //1 MPGe    ≈ 1 mi/(33.70 kW·h)
//                    //≈ 0.02967 mi/kW·h
//                    // ≈ 0.04775 km/kW·h
//
//                }
//                .padding(.bottom)
//                VStack {
//                    HStack{
//                        Text("mi/kWh:")
//                        TextField("Enter mi/kWh", value: $sharedVariables.mikWH, formatter: numberFormatter)
//                            .textFieldStyle(RoundedBorderTextFieldStyle())
//                            .onSubmit(of: .text) {
//                                sharedVariables.mpgE = sharedVariables.mikWH / 0.02967
//                                sharedVariables.whMi = 1000 / sharedVariables.mikWH
//                            }
//                            .multilineTextAlignment(.center)
//                            .padding(.horizontal)
//
//                    }
//
//
//                    HStack{
//                        Text("MPGe")
//                        TextField("MPGe", value: $sharedVariables.mpgE, formatter: numberFormatter)
//                            .textFieldStyle(RoundedBorderTextFieldStyle())
//                            .onSubmit(of: .text) {
//                                sharedVariables.mikWH = sharedVariables.mpgE * 0.02967
//                                sharedVariables.whMi = 1000 / sharedVariables.mikWH
//                                sharedVariables.kmkWH = sharedVariables.mpgE * 0.04775
//                                sharedVariables.whKm = 1000 / sharedVariables.kmkWH
//                            }
//                            .multilineTextAlignment(.center)
//                            .padding(.horizontal)
//
//                    }
//
//
//
//                    HStack {
//                        Text("km/kWh:")
//                        TextField("Enter km/kWh", value: $sharedVariables.kmkWH, formatter: numberFormatter)
//                            .textFieldStyle(RoundedBorderTextFieldStyle())
//                            .onSubmit(of: .text) {
//                                sharedVariables.whKm = 1000 / sharedVariables.kmkWH
//                                sharedVariables.kwhHundredKm = 100 / sharedVariables.kmkWH
//                                sharedVariables.mpgE = sharedVariables.mikWH / 0.04775
//                            }
//                            .multilineTextAlignment(.center)
//                            .padding(.horizontal)
//
//                    }
//                }
//            }
//       //     .padding(.horizontal)
//
//            GroupBox {
//                Text("Gas")
//                    .font(.title2)
//                    .bold()
//                VStack{
//                    HStack{
//                        Text("MPG")
//                        TextField("MPG", value: $sharedVariables.mpgE, formatter: numberFormatter)
//                            .textFieldStyle(RoundedBorderTextFieldStyle())
//                            .onSubmit(of: .text) {
//                                sharedVariables.galHundredMi = 100 / sharedVariables.mpgE
//                                sharedVariables.literHundredKm = 235 / sharedVariables.mpgE
//                                sharedVariables.kmLiter = 100 / sharedVariables.literHundredKm
//                                sharedVariables.mikWH = sharedVariables.mpgE * 0.02967
//                                sharedVariables.whMi = 1000 / sharedVariables.mikWH
//                                sharedVariables.kmkWH = sharedVariables.mpgE * 0.04775
//                                sharedVariables.whKm = 1000 / sharedVariables.kmkWH
//                                sharedVariables.kwhHundredKm = 100 / sharedVariables.kmkWH
//
//                            }
//                            .multilineTextAlignment(.center)
//                            .padding(.horizontal)
//
//                    }
//
//                    HStack{
//                        Text("Gal/100mi")
//                        TextField("Gal/100mi", value: $sharedVariables.galHundredMi, formatter: numberFormatter)
//                            .textFieldStyle(RoundedBorderTextFieldStyle())
//                            .onSubmit(of: .text) {
//                                sharedVariables.mpgE = sharedVariables.galHundredMi / 100
//                                sharedVariables.literHundredKm = 235 / sharedVariables.mpgE
//                                sharedVariables.kmLiter = 100 / sharedVariables.literHundredKm
//                                sharedVariables.mikWH = sharedVariables.mpgE * 0.02967
//                                sharedVariables.whMi = 1000 / sharedVariables.mikWH
//                                sharedVariables.kmkWH = sharedVariables.mpgE * 0.04775
//                                sharedVariables.whKm = 1000 / sharedVariables.kmkWH
//                                sharedVariables.kwhHundredKm = 100 / sharedVariables.kmkWH
//
//                            }
//                            .multilineTextAlignment(.center)
//                            .padding(.horizontal)
//
//                    }
//
//                    HStack{
//                        Text("L/100km")
//                        TextField("L/100km", value: $sharedVariables.literHundredKm, formatter: numberFormatter)
//                            .textFieldStyle(RoundedBorderTextFieldStyle())
//                            .onSubmit(of: .text) {
//                                sharedVariables.mpgE = 235 / sharedVariables.literHundredKm
//                                sharedVariables.galHundredMi =  sharedVariables.mpgE / 100
//                                sharedVariables.kmLiter = 100 / sharedVariables.literHundredKm
//                                sharedVariables.mikWH = sharedVariables.mpgE * 0.02967
//                                sharedVariables.whMi = 1000 / sharedVariables.mikWH
//                                sharedVariables.kmkWH = sharedVariables.mpgE * 0.04775
//                                sharedVariables.whKm = 1000 / sharedVariables.kmkWH
//                                sharedVariables.kwhHundredKm = 100 / sharedVariables.kmkWH
//                            }
//                            .multilineTextAlignment(.center)
//                            .padding(.horizontal)
//
//                    }
//
//                    HStack{
//                        Text("km/L")
//                        TextField("km/L", value: $sharedVariables.kmLiter, formatter: numberFormatter)
//                            .textFieldStyle(RoundedBorderTextFieldStyle())
//                            .onSubmit(of: .text) {
//                                sharedVariables.literHundredKm = 100 / sharedVariables.kmLiter
//                                sharedVariables.mpgE = 235 / sharedVariables.literHundredKm
//                                sharedVariables.galHundredMi =  sharedVariables.mpgE / 100
//                                sharedVariables.mikWH = sharedVariables.mpgE * 0.02967
//                                sharedVariables.whMi = 1000 / sharedVariables.mikWH
//                                sharedVariables.kmkWH = sharedVariables.mpgE * 0.04775
//                                sharedVariables.whKm = 1000 / sharedVariables.kmkWH
//                                sharedVariables.kwhHundredKm = 100 / sharedVariables.kmkWH
//
//                            }
//                            .multilineTextAlignment(.center)
//                            .padding(.horizontal)
//
//                    }
//                }
//            }
//      //      .padding(.horizontal)
//
//        }
//
//    }
//}

struct Conversions3_Previews: PreviewProvider {
    static var previews: some View {
        Conversions3()
            .environmentObject(SharedVariables())
    }
}
