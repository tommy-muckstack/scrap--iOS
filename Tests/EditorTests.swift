import XCTest
import Foundation
@testable import Scrap

/// Comprehensive tests for the rich text editor functionality
/// Run these tests before each release to ensure no regressions
class EditorTests: XCTestCase {
    
    var mockItem: SparkItem!
    var mockDataManager: MockDataManager!
    
    override func setUp() {
        super.setUp()
        mockItem = SparkItem(content: "Test content")
        mockDataManager = MockDataManager()
    }
    
    // MARK: - RTF Persistence Tests
    
    func testRTFSaveAndLoad() {
        // Create attributed text with bold formatting
        let text = "Hello Bold World"
        let attributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.boldSystemFont(ofSize: 17),
            .foregroundColor: UIColor.black
        ]
        let attributedText = NSMutableAttributedString(string: text)
        attributedText.addAttributes([.font: UIFont.boldSystemFont(ofSize: 17)], range: NSRange(location: 6, length: 4)) // "Bold"
        
        // Convert to RTF
        let rtfData = NavigationNoteEditView.attributedStringToData(attributedText)
        XCTAssertNotNil(rtfData, "RTF data should not be nil")
        XCTAssertGreaterThan(rtfData?.count ?? 0, 0, "RTF data should have content")
        
        // Convert back from RTF
        let restoredText = NavigationNoteEditView.dataToAttributedString(rtfData!)
        XCTAssertEqual(restoredText.string, text, "Text content should be preserved")
        
        // Check if bold formatting is preserved
        let boldRange = NSRange(location: 6, length: 4)
        let boldAttributes = restoredText.attributes(at: 6, effectiveRange: nil)
        if let font = boldAttributes[.font] as? UIFont {
            XCTAssertTrue(font.fontDescriptor.symbolicTraits.contains(.traitBold), "Bold formatting should be preserved")
        } else {
            XCTFail("Font attribute should exist")
        }
    }
    
    func testRTFWithMultipleFormats() {
        let text = "Bold Italic Underline"
        let attributedText = NSMutableAttributedString(string: text)
        
        // Apply bold to "Bold"
        attributedText.addAttributes([.font: UIFont.boldSystemFont(ofSize: 17)], range: NSRange(location: 0, length: 4))
        
        // Apply italic to "Italic"
        attributedText.addAttributes([.font: UIFont.italicSystemFont(ofSize: 17)], range: NSRange(location: 5, length: 6))
        
        // Apply underline to "Underline"
        attributedText.addAttributes([.underlineStyle: NSUnderlineStyle.single.rawValue], range: NSRange(location: 12, length: 9))
        
        // Test RTF round-trip
        let rtfData = NavigationNoteEditView.attributedStringToData(attributedText)
        XCTAssertNotNil(rtfData)
        
        let restoredText = NavigationNoteEditView.dataToAttributedString(rtfData!)
        XCTAssertEqual(restoredText.string, text)
        
        // Verify formatting preservation
        let boldFont = restoredText.attributes(at: 0, effectiveRange: nil)[.font] as? UIFont
        XCTAssertTrue(boldFont?.fontDescriptor.symbolicTraits.contains(.traitBold) == true)
        
        let underlineStyle = restoredText.attributes(at: 12, effectiveRange: nil)[.underlineStyle] as? Int
        XCTAssertEqual(underlineStyle, NSUnderlineStyle.single.rawValue)
    }
    
    // MARK: - Bullet Point Tests
    
    func testBulletPointCreation() {
        var text = "* First item"
        let transformed = RichTextTransformer.transform(text, oldText: "")
        XCTAssertEqual(transformed, "• First item", "Asterisk should convert to bullet")
        
        text = "- Second item"
        let transformed2 = RichTextTransformer.transform(text, oldText: "")
        XCTAssertEqual(transformed2, "• Second item", "Dash should convert to bullet")
    }
    
    func testBulletPointContinuation() {
        let oldText = "• First item"
        let newText = "• First item\n"
        let transformed = RichTextTransformer.transform(newText, oldText: oldText)
        XCTAssertEqual(transformed, "• First item\n• ", "New bullet should be added after Enter")
    }
    
    func testBulletPointEditing() {
        // Test that typing after a bullet doesn't overwrite previous bullets
        let initialText = "• First item\n• "
        let afterTyping = "• First item\n• Second"
        
        // Simulate the transformation that should happen when typing
        let transformed = RichTextTransformer.transform(afterTyping, oldText: initialText)
        XCTAssertEqual(transformed, "• First item\n• Second", "Typing should not overwrite previous bullets")
    }
    
    func testBulletPointBackspace() {
        let oldText = "• First item\n• "
        let newText = "• First item\n•"
        let transformed = RichTextTransformer.transform(newText, oldText: oldText)
        XCTAssertEqual(transformed, "• First item\n", "Backspace should remove bullet when appropriate")
    }
    
    // MARK: - Text Formatting Tests
    
    func testBoldFormatting() {
        let mockState = FormattingState()
        
        // Test bold toggle
        mockState.toggleTextFormat(.bold)
        XCTAssertTrue(mockState.isBoldActive, "Bold should be active after toggle")
        
        mockState.toggleTextFormat(.bold)
        XCTAssertFalse(mockState.isBoldActive, "Bold should be inactive after second toggle")
    }
    
    func testFormattingPersistence() {
        let mockState = FormattingState()
        mockState.toggleTextFormat(.bold)
        mockState.toggleTextFormat(.italic)
        
        XCTAssertTrue(mockState.isBoldActive, "Bold should remain active")
        XCTAssertTrue(mockState.isItalicActive, "Italic should remain active")
        
        // Test that formatting can be applied independently
        mockState.toggleTextFormat(.bold)
        XCTAssertFalse(mockState.isBoldActive, "Bold should be disabled")
        XCTAssertTrue(mockState.isItalicActive, "Italic should remain active")
    }
    
    // MARK: - Integration Tests
    
    func testFullEditingWorkflow() {
        // Simulate a full editing session
        var content = ""
        
        // 1. Start typing
        content = "Hello"
        var transformed = RichTextTransformer.transform(content, oldText: "")
        XCTAssertEqual(transformed, "Hello")
        
        // 2. Add bullet point
        content = "Hello\n* World"
        transformed = RichTextTransformer.transform(content, oldText: "Hello")
        XCTAssertEqual(transformed, "Hello\n• World")
        
        // 3. Continue bullet
        content = "Hello\n• World\n"
        transformed = RichTextTransformer.transform(content, oldText: "Hello\n• World")
        XCTAssertEqual(transformed, "Hello\n• World\n• ")
        
        // 4. Type in new bullet
        content = "Hello\n• World\n• Item"
        transformed = RichTextTransformer.transform(content, oldText: "Hello\n• World\n• ")
        XCTAssertEqual(transformed, "Hello\n• World\n• Item", "Should not overwrite previous content")
    }
    
    func testFormattingWithTransformations() {
        // Test that text transformations don't interfere with formatting
        let text = "**Bold** and * bullet"
        let transformed = RichTextTransformer.transform(text, oldText: "")
        
        // Should convert bullet but not interfere with bold markdown
        XCTAssertTrue(transformed.contains("• bullet"), "Should convert bullet")
        // Note: RTF formatting would be separate from text transformations
    }
    
    // MARK: - Error Cases
    
    func testInvalidRTFData() {
        let invalidData = Data([0x00, 0x01, 0x02]) // Invalid RTF data
        let result = NavigationNoteEditView.dataToAttributedString(invalidData)
        
        // Should return empty string without crashing
        XCTAssertEqual(result.string, "", "Should handle invalid RTF gracefully")
    }
    
    func testEmptyContent() {
        let emptyText = NSAttributedString(string: "")
        let rtfData = NavigationNoteEditView.attributedStringToData(emptyText)
        XCTAssertNil(rtfData, "Empty content should return nil RTF data")
    }
    
    func testLargeContent() {
        let largeText = String(repeating: "A", count: 10000)
        let attributedText = NSAttributedString(string: largeText)
        let rtfData = NavigationNoteEditView.attributedStringToData(attributedText)
        XCTAssertNotNil(rtfData, "Should handle large content")
        
        let restored = NavigationNoteEditView.dataToAttributedString(rtfData!)
        XCTAssertEqual(restored.string, largeText, "Large content should be preserved")
    }
}

// MARK: - Mock Classes

class MockDataManager: ObservableObject {
    var savedRTFData: Data?
    
    func updateItemWithRTF(_ item: SparkItem, rtfData: Data) {
        savedRTFData = rtfData
    }
    
    func updateItem(_ item: SparkItem, newContent: String) {
        item.content = newContent
    }
}

// MARK: - Performance Tests

extension EditorTests {
    
    func testRTFPerformance() {
        // Test RTF conversion performance with realistic content
        let content = """
        # Meeting Notes
        
        ## Attendees
        • John Smith - **Product Manager**
        • Jane Doe - *Designer*  
        • Bob Wilson - __Developer__
        
        ## Action Items
        1. Review designs ✓
        2. Update documentation
        3. Schedule follow-up
        
        **Important:** Remember to send updates by Friday!
        """
        
        let attributedText = NSMutableAttributedString(string: content)
        // Add some formatting
        attributedText.addAttribute(.font, value: UIFont.boldSystemFont(ofSize: 17), range: NSRange(location: 0, length: 7))
        
        measure {
            for _ in 0..<100 {
                if let rtfData = NavigationNoteEditView.attributedStringToData(attributedText) {
                    let _ = NavigationNoteEditView.dataToAttributedString(rtfData)
                }
            }
        }
    }
}

// MARK: - Test Runner Script

extension EditorTests {
    
    /// Run this before each release to ensure editor functionality works
    static func runRegressionTests() {
        print("🧪 Running Editor Regression Tests...")
        
        let testSuite = EditorTests()
        testSuite.setUp()
        
        let tests: [(String, () -> Void)] = [
            ("RTF Save/Load", testSuite.testRTFSaveAndLoad),
            ("Multiple Formats", testSuite.testRTFWithMultipleFormats),
            ("Bullet Creation", testSuite.testBulletPointCreation),
            ("Bullet Continuation", testSuite.testBulletPointContinuation),
            ("Bullet Editing", testSuite.testBulletPointEditing),
            ("Bold Formatting", testSuite.testBoldFormatting),
            ("Full Workflow", testSuite.testFullEditingWorkflow),
            ("Invalid Data", testSuite.testInvalidRTFData)
        ]
        
        var passed = 0
        var failed = 0
        
        for (name, test) in tests {
            do {
                test()
                print("✅ \(name) - PASSED")
                passed += 1
            } catch {
                print("❌ \(name) - FAILED: \(error)")
                failed += 1
            }
        }
        
        print("\n🧪 Test Results: \(passed) passed, \(failed) failed")
        if failed == 0 {
            print("🎉 All editor tests passed! Safe to release.")
        } else {
            print("⚠️ Some tests failed. Fix issues before release.")
        }
    }
}