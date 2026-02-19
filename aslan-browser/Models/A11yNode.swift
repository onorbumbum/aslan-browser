//
//  A11yNode.swift
//  aslan-browser
//

import Foundation

struct A11yRect: Codable {
    let x: Double
    let y: Double
    let w: Double
    let h: Double
}

struct A11yNode: Codable {
    let ref: String      // e.g. "@e0"
    let role: String     // e.g. "link", "button", "textbox"
    let name: String     // accessible name
    let tag: String      // e.g. "A", "BUTTON", "INPUT"
    let value: String?   // for inputs, selects, textareas
    let rect: A11yRect   // bounding rect
}
