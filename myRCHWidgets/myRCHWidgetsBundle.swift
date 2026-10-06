import SwiftUI
import WidgetKit

@main
struct myRCHWidgetsBundle: WidgetBundle {
    var body: some Widget {
        TodayWidget()
        NextDoseWidget()
        MedicationWidget()
        NextVisitWidget()
        UpcomingVisitsWidget()
        URNumberWidget()
        AllergyWidget()
        WhatsNewWidget()
        ShowURNumberControl()
        LogNextDoseControl()
        DoseLiveActivity()
        VisitLiveActivity()
    }
}
