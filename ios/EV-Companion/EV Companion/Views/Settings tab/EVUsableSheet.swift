//
//  EVUsableSheet.swift
//  EV Companion
//
//  Created by Paolo on 1/26/24.
//

import SwiftUI

struct EVUsableSheet: View {
    var textToShow: String
    
    var body: some View {
        VStack{
            Text("'Available' battery means the portion of the EV's battery you can charge. The overall size (capacity) of the battery installed in your EV is slightly bigger.")
                .padding(.top)
            Text("This extra capacity is used by the battery management software for the maintenance and longevity of the battery. For example, if your battery is 100kWh, only 94kWh might be accessible at all times.")
                .padding(.top)
            Text("Read your car manufactuer's website or user's manual to know what is the usable size of your EV's battery.")
                .padding(.top)
            Spacer()
        }
        .padding()
        .presentationDragIndicator(/*@START_MENU_TOKEN@*/.visible/*@END_MENU_TOKEN@*/)
        
    }
}

struct WordTappableTextModifier: ViewModifier {
    @Binding var isSheetVisible: Bool
    var sheetText: String
    
    func body(content: Content) -> some View {
        content
            .onTapGesture {
                isSheetVisible.toggle()
            }
            .sheet(isPresented: $isSheetVisible) {
                EVUsableSheet(textToShow: sheetText)
            }
    }
}

struct EVUsableSheet_Previews: PreviewProvider {
    static var previews: some View {
        EVUsableSheet(textToShow: "Battery Size (usable)")
    }
}
