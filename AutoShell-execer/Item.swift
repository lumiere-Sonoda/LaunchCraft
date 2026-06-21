//
//  Item.swift
//  AutoShell-execer
//
//  Created by aritosonoda on 2026/06/21.
//

import Foundation
import SwiftData

@Model
final class Item {
    var timestamp: Date
    
    init(timestamp: Date) {
        self.timestamp = timestamp
    }
}
