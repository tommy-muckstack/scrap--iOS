//
//  KeyboardResponsiveModifier.swift
//  Scrap
//
//  A SwiftUI view modifier that dynamically adjusts bottom padding
//  to keep content visible above the keyboard with smooth animations.
//

import SwiftUI
import Combine

/// Environment key to share keyboard height across views
struct KeyboardHeightEnvironmentKey: EnvironmentKey {
    static let defaultValue: CGFloat = 0
}

extension EnvironmentValues {
    var keyboardHeight: CGFloat {
        get { self[KeyboardHeightEnvironmentKey.self] }
        set { self[KeyboardHeightEnvironmentKey.self] = newValue }
    }
}

/// A view modifier that responds to keyboard appearance with smooth animations
struct KeyboardResponsiveModifier: ViewModifier {
    @State private var keyboardHeight: CGFloat = 0
    @State private var cancellables = Set<AnyCancellable>()

    func body(content: Content) -> some View {
        content
            .padding(.bottom, keyboardHeight)
            .environment(\.keyboardHeight, keyboardHeight)
            .onAppear {
                subscribeToKeyboardNotifications()
            }
            .onDisappear {
                cancellables.removeAll()
            }
    }

    private func subscribeToKeyboardNotifications() {
        // Keyboard will show
        NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)
            .compactMap { notification -> CGFloat? in
                guard let keyboardFrame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else {
                    return nil
                }
                return keyboardFrame.height
            }
            .sink { height in
                withAnimation(.easeOut(duration: 0.25)) {
                    keyboardHeight = height
                }
            }
            .store(in: &cancellables)

        // Keyboard will hide
        NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)
            .sink { _ in
                withAnimation(.easeOut(duration: 0.25)) {
                    keyboardHeight = 0
                }
            }
            .store(in: &cancellables)
    }
}

extension View {
    /// Makes the view responsive to keyboard appearance with smooth animations
    func keyboardResponsive() -> some View {
        modifier(KeyboardResponsiveModifier())
    }
}
