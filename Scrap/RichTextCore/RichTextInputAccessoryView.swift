//
//  RichTextInputAccessoryView.swift
//  Scrap
//
//  UIKit-based toolbar for rich text formatting
//

import UIKit
import SwiftUI

/// A UIKit toolbar that serves as the keyboard input accessory view
class RichTextInputAccessoryView: UIView {
    
    private let context: RichTextContext
    private let showingFormatting: Binding<Bool>
    
    init(context: RichTextContext, showingFormatting: Binding<Bool>) {
        self.context = context
        self.showingFormatting = showingFormatting
        super.init(frame: CGRect(x: 0, y: 0, width: UIScreen.main.bounds.width, height: 44))
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
            context: context,
            showingFormatting: showingFormatting
        )
        
        let hostingController = UIHostingController(rootView: toolbar)
        hostingController.view.backgroundColor = .clear
        hostingController.view.translatesAutoresizingMaskIntoConstraints = false
        
        addSubview(hostingController.view)
        
        NSLayoutConstraint.activate([
            hostingController.view.leadingAnchor.constraint(equalTo: leadingAnchor),
            hostingController.view.trailingAnchor.constraint(equalTo: trailingAnchor),
            hostingController.view.topAnchor.constraint(equalTo: topAnchor),
            hostingController.view.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }
    
    override var intrinsicContentSize: CGSize {
        return CGSize(width: UIView.noIntrinsicMetric, height: 52)
    }
}

/// Extension to create and manage the input accessory view
extension UITextView {
    
    private struct AssociatedKeys {
        static var richTextInputAccessory = "richTextInputAccessory"
    }
    
    /// Set up rich text input accessory view
    func setupRichTextInputAccessory(context: RichTextContext, showingFormatting: Binding<Bool>) {
        let accessoryView = RichTextInputAccessoryView(
            context: context,
            showingFormatting: showingFormatting
        )
        
        self.inputAccessoryView = accessoryView
        
        // Store reference
        objc_setAssociatedObject(
            self,
            &AssociatedKeys.richTextInputAccessory,
            accessoryView,
            .OBJC_ASSOCIATION_RETAIN_NONATOMIC
        )
        
        // Ensure the accessory view is shown
        self.reloadInputViews()
    }
}