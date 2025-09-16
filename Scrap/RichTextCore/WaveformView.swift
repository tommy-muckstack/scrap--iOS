import SwiftUI
import AVFoundation

struct WaveformView: View {
    @State private var amplitudes: [CGFloat] = Array(repeating: 0.1, count: 5)
    @State private var animationTimer: Timer?
    
    let isRecording: Bool
    let barCount: Int
    let barWidth: CGFloat
    let barSpacing: CGFloat
    let maxHeight: CGFloat
    let color: Color
    
    init(
        isRecording: Bool,
        barCount: Int = 5,
        barWidth: CGFloat = 3,
        barSpacing: CGFloat = 2,
        maxHeight: CGFloat = 20,
        color: Color = .white
    ) {
        self.isRecording = isRecording
        self.barCount = barCount
        self.barWidth = barWidth
        self.barSpacing = barSpacing
        self.maxHeight = maxHeight
        self.color = color
    }
    
    var body: some View {
        HStack(spacing: barSpacing) {
            ForEach(0..<barCount, id: \.self) { index in
                RoundedRectangle(cornerRadius: barWidth / 2)
                    .fill(color)
                    .frame(width: barWidth, height: amplitudes[index] * maxHeight)
                    .animation(
                        .easeInOut(duration: 0.3)
                        .delay(Double(index) * 0.1),
                        value: amplitudes[index]
                    )
            }
        }
        .frame(height: maxHeight)
        .onChange(of: isRecording) { newValue in
            if newValue {
                startAnimation()
            } else {
                stopAnimation()
            }
        }
        .onDisappear {
            stopAnimation()
        }
    }
    
    private func startAnimation() {
        animationTimer = Timer.scheduledTimer(withTimeInterval: 0.15, repeats: true) { _ in
            withAnimation(.easeInOut(duration: 0.3)) {
                for i in 0..<amplitudes.count {
                    // Create random amplitude variations for realistic waveform effect
                    amplitudes[i] = CGFloat.random(in: 0.3...1.0)
                }
            }
        }
    }
    
    private func stopAnimation() {
        animationTimer?.invalidate()
        animationTimer = nil
        
        withAnimation(.easeOut(duration: 0.5)) {
            for i in 0..<amplitudes.count {
                amplitudes[i] = 0.1
            }
        }
    }
}

// Preview for testing
struct WaveformView_Previews: PreviewProvider {
    @State static var isRecording = true
    
    static var previews: some View {
        VStack(spacing: 20) {
            WaveformView(isRecording: isRecording)
            
            Button("Toggle Recording") {
                isRecording.toggle()
            }
        }
        .padding()
        .background(Color.black)
    }
}