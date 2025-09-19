//
//  RichTextInputAccessoryView.swift
//  Scrap
//
//  UIKit-based toolbar for rich text formatting
//

import UIKit
import SwiftUI
import ObjectiveC

/// A UIKit toolbar that serves as the keyboard input accessory view
class RichTextInputAccessoryView: UIView {
    
    private let context: RichTextContext
    
    init(context: RichTextContext) {
        self.context = context
        
        // Safely get screen width with fallback to prevent NaN issues
        let screenWidth = UIScreen.main.bounds.width
        let safeWidth = screenWidth.isFinite && screenWidth > 0 ? screenWidth : 320 // iPhone SE fallback
        
        super.init(frame: CGRect(x: 0, y: 0, width: safeWidth, height: 44))
        setupView()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupView() {
        backgroundColor = UIColor.systemBackground
        
        // Add shadow
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOffset = CGSize(width: 0, height: -1)
        layer.shadowOpacity = 0.1
        layer.shadowRadius = 1
        
        // Create SwiftUI toolbar and embed it
        let toolbar = RichFormattingToolbar(
            context: context
        )
        
        let hostingController = UIHostingController(rootView: toolbar)
        hostingController.view.backgroundColor = UIColor.clear
        hostingController.view.translatesAutoresizingMaskIntoConstraints = false
        
        addSubview(hostingController.view)
        
        NSLayoutConstraint.activate([
            hostingController.view.leadingAnchor.constraint(equalTo: leadingAnchor),
            hostingController.view.trailingAnchor.constraint(equalTo: trailingAnchor),
            hostingController.view.topAnchor.constraint(equalTo: topAnchor),
            hostingController.view.bottomAnchor.constraint(equalTo: bottomAnchor),
            hostingController.view.heightAnchor.constraint(equalToConstant: 52) // Fixed height to prevent growth
        ])
    }
    
    override var intrinsicContentSize: CGSize {
        return CGSize(width: UIView.noIntrinsicMetric, height: 52)
    }
}

/// Extension to create and manage the input accessory view
extension UITextView {
    
    private struct AssociatedKeys {
        static var richTextInputAccessory: UInt8 = 0
    }
    
    /// Set up rich text input accessory view
    func setupRichTextInputAccessory(context: RichTextContext, showingFormatting: Binding<Bool>) {
        // Only create and set the input accessory view if formatting should be shown
        if showingFormatting.wrappedValue {
            let accessoryView = RichTextInputAccessoryView(
                context: context
            )
            
            self.inputAccessoryView = accessoryView
            
            // Store reference
            objc_setAssociatedObject(
                self,
                &AssociatedKeys.richTextInputAccessory,
                accessoryView,
                .OBJC_ASSOCIATION_RETAIN_NONATOMIC
            )
        } else {
            // Hide the input accessory view when formatting is disabled
            self.inputAccessoryView = nil
            
            // Clear stored reference
            objc_setAssociatedObject(
                self,
                &AssociatedKeys.richTextInputAccessory,
                nil,
                .OBJC_ASSOCIATION_RETAIN_NONATOMIC
            )
        }
        
        // Ensure the accessory view state is updated
        self.reloadInputViews()
    }
}