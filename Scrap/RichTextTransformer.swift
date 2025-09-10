import Foundation

/// Centralized class for handling rich text transformations in the note editor
/// Handles bullet points, arrows, and future formatting enhancements
class RichTextTransformer {
    
    // MARK: - Public Interface
    
    /// Main transformation function that applies all rich text rules
    /// - Parameters:
    ///   - newText: The new text content
    ///   - oldText: The previous text content (for context-aware transformations)
    /// - Returns: Transformed text with rich formatting applied
    static func transform(_ newText: String, oldText: String) -> String {
        print("🎨 RichTextTransformer: Processing '\(newText.prefix(50))...' (old: '\(oldText.prefix(20))...')")
        
        // Apply transformations in order
        var processed = newText
        
        // 1. Handle bullet point transformations (context-aware)
        processed = transformBullets(processed, oldText: oldText)
        
        // 2. Handle arrow replacements (always apply)
        processed = transformArrows(processed)
        
        // 3. Future: Add bold, italic, font size transformations here
        
        if processed != newText {
            print("✨ RichTextTransformer: Applied transformation - result: '\(processed.prefix(50))...'")
        }
        
        return processed
    }
    
    // MARK: - Bullet Point Transformations
    
    /// Handles all bullet point related transformations
    private static func transformBullets(_ text: String, oldText: String) -> String {
        // Handle Enter key - continue bullet lists
        if text.count > oldText.count && text.hasSuffix("\n") {
            return handleBulletContinuation(text)
        }
        
        // Handle backspace - remove bullets when appropriate  
        if text.count < oldText.count {
            return handleBulletBackspace(text, oldText: oldText)
        }
        
        // Handle new bullet creation (* or - at start of line)
        let withBullets = convertMarkdownBullets(text)
        return withBullets
    }
    
    /// Converts * or - at start of line to bullet points
    private static func convertMarkdownBullets(_ text: String) -> String {
        let lines = text.components(separatedBy: "\n")
        var modified = false
        var newLines = lines
        
        for (index, line) in lines.enumerated() {
            // Convert "* " or "- " at start of line to bullet
            if line.hasPrefix("* ") || line.hasPrefix("- ") {
                newLines[index] = "• " + line.dropFirst(2)
                modified = true
                print("🔸 RichTextTransformer: Converted '\(line)' to bullet point")
            }
        }
        
        return modified ? newLines.joined(separator: "\n") : text
    }
    
    /// Continues bullet points on new lines
    private static func handleBulletContinuation(_ text: String) -> String {
        let lines = text.components(separatedBy: "\n")
        guard lines.count >= 2 else { return text }
        
        let previousLine = lines[lines.count - 2]
        let currentLine = lines[lines.count - 1]
        
        // If previous line starts with bullet and current line is empty, add bullet
        if previousLine.hasPrefix("• ") && currentLine.isEmpty {
            var newLines = lines
            newLines[newLines.count - 1] = "• "
            print("🔸 RichTextTransformer: Continued bullet point on new line")
            return newLines.joined(separator: "\n")
        }
        
        return text
    }
    
    /// Handles backspace behavior for bullet points
    private static func handleBulletBackspace(_ text: String, oldText: String) -> String {
        let newLines = text.components(separatedBy: "\n")
        let oldLines = oldText.components(separatedBy: "\n")
        
        // Find which line changed
        for (index, line) in newLines.enumerated() {
            if index < oldLines.count {
                let oldLine = oldLines[index]
                
                // If user backspaced the space after bullet, remove bullet entirely
                if oldLine.hasPrefix("• ") && line == "•" {
                    var modifiedLines = newLines
                    modifiedLines[index] = ""
                    print("🔸 RichTextTransformer: Removed bullet after backspace")
                    return modifiedLines.joined(separator: "\n")
                }
            }
        }
        
        return text
    }
    
    // MARK: - Arrow Transformations
    
    /// Converts -> to → arrow character
    private static func transformArrows(_ text: String) -> String {
        let result = text.replacingOccurrences(of: "->", with: "→")
        if result != text {
            print("🔸 RichTextTransformer: Converted arrows: -> → →")
        }
        return result
    }
    
    // MARK: - Future Formatting (Placeholder)
    
    /// Placeholder for future bold text transformations (**text**)
    private static func transformBold(_ text: String) -> String {
        // Future: Handle **bold** markdown
        return text
    }
    
    /// Placeholder for future italic text transformations (*text*)
    private static func transformItalic(_ text: String) -> String {
        // Future: Handle *italic* markdown
        return text
    }
    
    /// Placeholder for future heading transformations (# text)
    private static func transformHeadings(_ text: String) -> String {
        // Future: Handle # heading markdown
        return text
    }
}

// MARK: - Extensions for Testing

#if DEBUG
extension RichTextTransformer {
    /// Test function for verifying transformations
    static func runTests() {
        print("🧪 RichTextTransformer: Running tests...")
        
        // Test bullet conversion
        let bulletTest = transform("* Item 1\n- Item 2", oldText: "")
        assert(bulletTest == "• Item 1\n• Item 2", "Bullet conversion failed")
        
        // Test arrow conversion
        let arrowTest = transform("This -> That", oldText: "")
        assert(arrowTest == "This → That", "Arrow conversion failed")
        
        print("✅ RichTextTransformer: All tests passed!")
    }
}
#endif