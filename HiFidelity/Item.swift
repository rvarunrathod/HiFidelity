//
//  Item.swift
//  HiFidelity
//
//  Created by Varun Rathod on 21/10/25.
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
