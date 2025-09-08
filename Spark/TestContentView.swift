import SwiftUI

// Minimal test view to debug white screen
struct TestContentView: View {
    var body: some View {
        VStack {
            Text("Spark Test")
                .font(.largeTitle)
                .padding()
            
            TextField("Test input", text: .constant(""))
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .padding()
            
            Button("Test Button") {
                print("Button tapped")
            }
            .padding()
        }
        .background(Color.gray.opacity(0.1))
    }
}

struct TestContentView_Previews: PreviewProvider {
    static var previews: some View {
        TestContentView()
    }
}