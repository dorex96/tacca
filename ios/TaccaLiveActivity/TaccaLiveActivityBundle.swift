import SwiftUI
import WidgetKit

/// Estensione widget che ospita la Live Activity della sessione.
///
/// Non contiene widget della home: serve solo alla schermata di blocco e alla
/// Dynamic Island.
@main
struct TaccaLiveActivityBundle: WidgetBundle {
  var body: some Widget {
    SessionLiveActivity()
  }
}
