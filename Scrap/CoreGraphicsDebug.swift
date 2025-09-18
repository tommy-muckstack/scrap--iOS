import Foundation
import UIKit

// MARK: - CoreGraphics NaN Error Debugging Helper
// This file helps identify the exact source of CoreGraphics NaN errors

class CoreGraphicsDebugger {
    static let shared = CoreGraphicsDebugger()
    
    private init() {}
    
    /// Enable comprehensive CoreGraphics debugging
    /// Call this in your app delegate or early in app lifecycle
    static func enableDebugMode() {
        // Enable CoreGraphics debugging with detailed backtraces for production issues only
        #if DEBUG
        setenv("CG_CONTEXT_SHOW_BACKTRACE", "1", 1)
        setenv("CG_PDF_VERBOSE", "1", 1)
        setenv("CG_NUMERICS_SHOW_BACKTRACE", "1", 1)  // Show backtraces for NaN errors
        setenv("CG_GEOMETRY_VERBOSE", "1", 1)         // Show geometry calculation details
        #endif
        
        // Only log in debug builds
        #if DEBUG
        print("🔍 CoreGraphics Debug Mode Enabled")
        #endif
    }
    
    /// Validate all numeric values in NSAttributedString attributes
    static func validateAttributedString(_ attributedString: NSAttributedString) -> [String] {
        var issues: [String] = []
        let range = NSRange(location: 0, length: attributedString.length)
        
        attributedString.enumerateAttributes(in: range, options: []) { attributes, subRange, _ in
            for (key, value) in attributes {
                switch key {
                case .font:
                    if let font = value as? UIFont {
                        let size = font.pointSize
                        if !size.isFinite || size.isNaN {
                            issues.append("❌ Font size NaN/infinite at range \(subRange): \(size)")
                        }
                        if size <= 0 {
                            issues.append("⚠️  Font size <= 0 at range \(subRange): \(size)")
                        }
                    }
                    
                case .baselineOffset:
                    if let offset = value as? NSNumber {
                        let offsetValue = offset.doubleValue
                        if !offsetValue.isFinite || offsetValue.isNaN {
                            issues.append("❌ Baseline offset NaN/infinite at range \(subRange): \(offsetValue)")
                        }
                    }
                    
                case .kern:
                    if let kern = value as? NSNumber {
                        let kernValue = kern.doubleValue
                        if !kernValue.isFinite || kernValue.isNaN {
                            issues.append("❌ Kerning NaN/infinite at range \(subRange): \(kernValue)")
                        }
                    }
                    
                case .paragraphStyle:
                    if let paragraphStyle = value as? NSParagraphStyle {
                        let values = [
                            paragraphStyle.lineSpacing,
                            paragraphStyle.paragraphSpacing,
                            paragraphStyle.headIndent,
                            paragraphStyle.tailIndent,
                            paragraphStyle.firstLineHeadIndent,
                            paragraphStyle.minimumLineHeight,
                            paragraphStyle.maximumLineHeight
                        ]
                        
                        for (index, val) in values.enumerated() {
                            if !val.isFinite || val.isNaN {
                                let names = ["lineSpacing", "paragraphSpacing", "headIndent", "tailIndent", "firstLineHeadIndent", "minimumLineHeight", "maximumLineHeight"]
                                issues.append("❌ ParagraphStyle.\(names[index]) NaN/infinite at range \(subRange): \(val)")
                            }
                        }
                    }
                    
                default:
                    // Check if value is a numeric type that could be NaN
                    if let number = value as? NSNumber {
                        let doubleValue = number.doubleValue
                        if !doubleValue.isFinite || doubleValue.isNaN {
                            issues.append("❌ Attribute \(key.rawValue) NaN/infinite at range \(subRange): \(doubleValue)")
                        }
                    }
                }
            }
        }
        
        return issues
    }
    
    /// Safe font creation with comprehensive validation
    static func createSafeFont(name: String, size: CGFloat) -> UIFont {
        let safeSize = safeFontSize(size)
        
        if let customFont = UIFont(name: name, size: safeSize) {
            return customFont
        } else {
            return UIFont.systemFont(ofSize: safeSize)
        }
    }
    
    /// Safe font size validation
    private static func safeFontSize(_ size: CGFloat) -> CGFloat {
        guard size.isFinite && size > 0 else {
            return 17.0
        }
        let minSize: CGFloat = 8.0
        let maxSize: CGFloat = 72.0
        let clampedSize = max(minSize, min(maxSize, size))
        
        return clampedSize
    }
    
    /// Validate all CGFloat values in geometry calculations
    static func validateGeometry(_ values: [CGFloat], context: String) -> [CGFloat] {
        return values.map { value in
            guard value.isFinite && !value.isNaN else {
                return 0.0
            }
            return value
        }
    }
    
    /// Comprehensive UIFont validation
    static func validateFont(_ font: UIFont?) -> UIFont {
        guard let font = font else {
            return UIFont.systemFont(ofSize: 17)
        }
        
        let size = font.pointSize
        guard size.isFinite && !size.isNaN && size > 0 else {
            return createSafeFont(name: font.fontName, size: 17)
        }
        
        return font
    }
    
    /// Safe attribute creation
    static func createSafeAttributes(font: UIFont, color: UIColor, baselineOffset: CGFloat? = nil) -> [NSAttributedString.Key: Any] {
        var attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color
        ]
        
        if let offset = baselineOffset {
            if offset.isFinite && !offset.isNaN {
                attributes[.baselineOffset] = offset
            }
        }
        
        return attributes
    }
    
    /// Comprehensive pre-render validation to catch any NaN values before they hit CoreGraphics
    static func validateBeforeRender(_ attributedString: NSAttributedString, context: String = "Unknown") -> Bool {
        let issues = validateAttributedString(attributedString)
        if !issues.isEmpty {
            #if DEBUG
            print("❌ CoreGraphicsDebugger: Found NaN issues in \(context)")
            #endif
            return false
        }
        return true
    }
    
    /// Validate CGPoint for NaN/infinite values
    static func validateCGPoint(_ point: CGPoint, context: String = "CGPoint") -> CGPoint {
        let safeX = point.x.isFinite && !point.x.isNaN ? point.x : 0.0
        let safeY = point.y.isFinite && !point.y.isNaN ? point.y : 0.0
        
        if safeX != point.x || safeY != point.y {
            #if DEBUG
            print("❌ CoreGraphicsDebugger: Invalid \(context) (\(point.x), \(point.y)), using (\(safeX), \(safeY))")
            #endif
        }
        
        return CGPoint(x: safeX, y: safeY)
    }
}