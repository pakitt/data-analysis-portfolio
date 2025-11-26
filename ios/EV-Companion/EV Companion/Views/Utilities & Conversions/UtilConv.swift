//
//  UtilConv.swift
//  EV Companion
//
//  Created by Paolo on 1/26/24.
//

import SwiftUI

struct UtilConv: View {
    
    @EnvironmentObject var sharedVariables: SharedVariables
    
    @AppStorage("selectionUtilConvSheet") private var selectionUtilConvSheet = 1
    
    var body: some View {
        VStack {
            Text("Utilities & Conversions")
                .font(.largeTitle)
            Picker(selection: $selectionUtilConvSheet, label: Text("Picker")) {
                Image(systemName: "arrow.left.arrow.right.square").tag(1)
                Image(systemName: "wrench.and.screwdriver").tag(2)
            }
            .pickerStyle(SegmentedPickerStyle())
            .padding(.horizontal)
            
            ScrollView{
                if selectionUtilConvSheet == 1 {
                    Conversions3()
                } else
                {
                    Utilities()
                }
                Spacer()
            }
            .padding()
        }
        
    }
}

struct UtilConv_Previews: PreviewProvider {
    static var previews: some View {
        UtilConv()
            .environmentObject(SharedVariables())
    }
}
