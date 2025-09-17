import Foundation
import UIKit

// Simple test to see what happens to ASCII markers during RTF conversion
let testString = "Test checkboxes:\n(CHECKED) First item\n(UNCHECKED) Second item\nRegular text"
let attributedString = NSAttributedString(string: testString)

print("Original string: '\(testString)'")

do {
    // Convert to RTF
    let rtfData = try attributedString.data(
        from: NSRange(location: 0, length: attributedString.length),
        documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
    )
    
    print("RTF data size: \(rtfData.count) bytes")
    
    // Convert back from RTF
    let restoredString = try NSAttributedString(
        data: rtfData,
        options: [.documentType: NSAttributedString.DocumentType.rtf],
        documentAttributes: nil
    )
    
    print("After RTF round-trip: '\(restoredString.string)'")
    
    // Check for markers
    if restoredString.string.contains("(CHECKED)") {
        print("✅ (CHECKED) marker survived")
    } else {
        print("❌ (CHECKED) marker was lost")
    }
    
    if restoredString.string.contains("(UNCHECKED)") {
        print("✅ (UNCHECKED) marker survived")
    } else {
        print("❌ (UNCHECKED) marker was lost")
    }
    
    // Show character-by-character analysis
    for (i, char) in restoredString.string.enumerated() {
        if char == "(" || char == ")" {
            print("Found special char at \(i): '\(char)'")
        }
    }
    
} catch {
    print("Error: \(error)")
}