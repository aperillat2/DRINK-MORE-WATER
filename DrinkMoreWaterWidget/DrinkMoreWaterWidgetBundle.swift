//
//  DrinkMoreWaterWidgetBundle.swift
//  DrinkMoreWaterWidget
//
//  Created by AARON PERILLAT on 10/26/26.
//

import WidgetKit
import SwiftUI

@main
struct DrinkMoreWaterWidgetBundle: WidgetBundle {
    var body: some Widget {
        DrinkMoreWaterWidget()
        // Lock Screen / Control Center / Action button control (iOS 18+).
        if #available(iOS 18.0, *) {
            AddWaterControl()
        }
    }
}
