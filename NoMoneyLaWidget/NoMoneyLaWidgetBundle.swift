//
//  NoMoneyLaWidgetBundle.swift
//  NoMoneyLaWidget
//
//  Created by Ricky Ding on 22/2/2026.
//

import WidgetKit
import SwiftUI

@main
struct NoMoneyLaWidgetBundle: WidgetBundle {
    var body: some Widget {
        NoMoneyLaWidget()
        NoMoneyLaWidgetControl()
        NoMoneyLaWidgetLiveActivity()
    }
}
