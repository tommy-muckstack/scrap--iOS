import UIKit
import Foundation

// Test script to debug NSAttributedString attachment insertion
class AttachmentDebugTest {
    
    static func testAttachmentInsertion() {
        print("🧪 Starting NSAttributedString attachment insertion test")
        
        // Create a basic attributed string
        let font = UIFont(name: "SpaceGrotesk-Regular", size: 16) ?? UIFont.systemFont(ofSize: 16)
        let attributes: [NSAttributedString.Key: Any] = [.font: font]
        let initialText = NSAttributedString(string: "Hello world. This is a test.", attributes: attributes)
        
        print("🧪 Initial text: '\(initialText.string)' (length: \(initialText.length))")
        
        // Create a mutable copy
        let mutableText = NSMutableAttributedString(attributedString: initialText)
        print("🧪 Mutable text length: \(mutableText.length)")
        
        // Create a simple NSTextAttachment for testing
        let testAttachment = NSTextAttachment()
        testAttachment.image = UIImage(systemName: "circle")
        let attachmentString = NSAttributedString(attachment: testAttachment)
        print("🧪 Created attachment string with length: \(attachmentString.length)")
        
        // Test 1: Insert at position 0
        print("\n--- Test 1: Insert at position 0 ---")
        let testText1 = NSMutableAttributedString(attributedString: mutableText)
        testText1.insert(attachmentString, at: 0)
        print("🧪 After insertion at 0, length: \(testText1.length)")
        
        // Check if attachment is found
        testText1.enumerateAttribute(.attachment, in: NSRange(location: 0, length: testText1.length), options: []) { value, range, _ in
            print("🧪 Found attachment at range \(range): \(value == nil ? "nil" : String(describing: type(of: value!)))")
        }
        
        // Test 2: Insert at end
        print("\n--- Test 2: Insert at end ---")
        let testText2 = NSMutableAttributedString(attributedString: mutableText)
        testText2.insert(attachmentString, at: testText2.length)
        print("🧪 After insertion at end, length: \(testText2.length)")
        
        // Check if attachment is found
        testText2.enumerateAttribute(.attachment, in: NSRange(location: 0, length: testText2.length), options: []) { value, range, _ in
            print("🧪 Found attachment at range \(range): \(value == nil ? "nil" : String(describing: type(of: value!)))")
        }
        
        // Test 3: Insert in middle (position 13, after "Hello world. ")
        print("\n--- Test 3: Insert in middle (position 13) ---")
        let testText3 = NSMutableAttributedString(attributedString: mutableText)
        testText3.insert(attachmentString, at: 13)
        print("🧪 After insertion at 13, length: \(testText3.length)")
        
        // Check if attachment is found
        testText3.enumerateAttribute(.attachment, in: NSRange(location: 0, length: testText3.length), options: []) { value, range, _ in
            print("🧪 Found attachment at range \(range): \(value == nil ? "nil" : String(describing: type(of: value!)))")
        }
        
        // Test 4: DrawingTextAttachment specifically
        print("\n--- Test 4: DrawingTextAttachment ---")
        let drawingAttachment = DrawingTextAttachment()
        let drawingAttachmentString = NSAttributedString(attachment: drawingAttachment)
        print("🧪 Created DrawingTextAttachment string with length: \(drawingAttachmentString.length)")
        
        let testText4 = NSMutableAttributedString(attributedString: mutableText)
        testText4.insert(drawingAttachmentString, at: 13)
        print("🧪 After DrawingTextAttachment insertion at 13, length: \(testText4.length)")
        
        // Check if DrawingTextAttachment is found
        testText4.enumerateAttribute(.attachment, in: NSRange(location: 0, length: testText4.length), options: []) { value, range, _ in
            print("🧪 Found attachment at range \(range): \(value == nil ? "nil" : String(describing: type(of: value!)))")
            if let drawingAttachment = value as? DrawingTextAttachment {
                print("🧪   DrawingTextAttachment ID: \(drawingAttachment.drawingId)")
            }
        }
        
        print("\n🧪 Test completed")
    }
}

// For command line execution
if CommandLine.arguments.count > 1 && CommandLine.arguments[1] == "test" {
    AttachmentDebugTest.testAttachmentInsertion()
}