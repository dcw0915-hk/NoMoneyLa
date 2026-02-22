import WidgetKit
import SwiftUI

@main
struct NoMoneyLaWidgetBundle: WidgetBundle {
    var body: some Widget {
        NoMoneyLaWidget()
        RecentTransactionWidget()   // <-- 新增
        NoMoneyLaWidgetControl()
        NoMoneyLaWidgetLiveActivity()
    }
}
