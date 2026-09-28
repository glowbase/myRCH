import SwiftUI
import WidgetKit

@main
struct myRCHWidgetsBundle: WidgetBundle {
    var body: some Widget {
        NextDoseWidget()
        MedicationWidget()
        NextVisitWidget()
        URNumberWidget()
        AllergyWidget()
        WhatsNewWidget()
        ShowURNumberControl()
        LogNextDoseControl()
    }
}
