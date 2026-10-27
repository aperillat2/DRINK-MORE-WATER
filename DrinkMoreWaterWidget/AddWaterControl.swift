//
//  AddWaterControl.swift
//  DrinkMoreWaterWidget
//

import AppIntents
import SwiftUI
import WidgetKit

/// A one-tap "Add Water" control (iOS 18+). People can place it in the two control slots at the
/// bottom of the Lock Screen, in Control Center, or on the Action button. It runs the same
/// `AddWaterIntent` as the widgets' Add button, without unlocking or opening the app.
@available(iOS 18.0, *)
struct AddWaterControl: ControlWidget {
    static let kind = "com.dreampuddle.drinkmorewater.AddWaterControl"

    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: Self.kind) {
            ControlWidgetButton(action: AddWaterIntent()) {
                Label("Add Water", systemImage: "drop.fill")
            }
        }
        .displayName("Add Water")
        .description("Adds your per-tap amount of water to today's total.")
    }
}
