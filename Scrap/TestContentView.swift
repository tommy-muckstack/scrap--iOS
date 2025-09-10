import SwiftUI

// Minimal test view to debug white screen
struct TestContentView: View {
    var body: some View {
        VStack {
            Text("Scrap Test")
                .font(GentleLightning.Typography.hero)
                .foregroundColor(GentleLightning.Colors.textPrimary)
                .padding()
            
            TextField("Test input", text: .constant(""))
                .font(GentleLightning.Typography.bodyInput)
                .foregroundColor(GentleLightning.Colors.textPrimary)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .padding()
            
            Button("Test Button") {
                print("Button tapped")
            }
            .font(GentleLightning.Typography.body)
            .foregroundColor(GentleLightning.Colors.textPrimary)
            .padding()
        }
        .background(GentleLightning.Colors.backgroundWarm)
    }
}

struct TestContentView_Previews: PreviewProvider {
    static var previews: some View {
        TestContentView()
    }
}