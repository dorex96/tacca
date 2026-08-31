import ActivityKit
import AppIntents
import Foundation
import UserNotifications

/// "Serie fatta" premuto sulla schermata di blocco.
///
/// Gira nel processo dell'estensione, non in quello dell'app: qui non ci sono
/// né il motore Dart né il database. Fa tre cose, in quest'ordine:
///
/// 1. lascia l'azione nella coda dell'App Group — è l'unica che non può
///    fallire senza perdere il lavoro dell'utente;
/// 2. aggiorna subito la Live Activity, così il tap ha un effetto visibile
///    anche se l'app dorme;
/// 3. programma la notifica di fine recupero, perché il beep lo darebbe l'app
///    e l'app non è sveglia.
///
/// L'app, al rientro in primo piano, drena la coda e registra la serie con
/// l'orario del tap; da quel momento torna lei a programmare i segnali.
@available(iOS 17.0, *)
struct CompleteSetIntent: LiveActivityIntent {
  static var title: LocalizedStringResource = "Serie fatta"

  /// Non è una scorciatoia da offrire all'utente: esiste solo per il pulsante
  /// della Live Activity.
  static var isDiscoverable: Bool = false

  init() {}

  func perform() async throws -> some IntentResult {
    guard let activity = Activity<TaccaSessionAttributes>.activities.first else {
      return .result()
    }
    let attributes = activity.attributes
    let state = activity.content.state
    guard state.canCompleteSet else { return .result() }

    let now = Date()
    PendingActionStore.append(
      PendingLiveAction(
        id: UUID().uuidString,
        kind: "setCompleted",
        logId: attributes.logId,
        entryIndex: state.entryIndex,
        setNumber: state.setNumber,
        at: Int(now.timeIntervalSince1970 * 1000)
      )
    )

    var next = state
    next.setNumber = state.setNumber + 1
    // Con le serie previste esaurite il pulsante sparisce: sarà l'app, al
    // risveglio, a spostare il banner sull'esercizio successivo.
    next.canCompleteSet = state.totalSets > 0 && next.setNumber <= state.totalSets

    if state.restSecondsOnComplete > 0 {
      let endsAt = now.addingTimeInterval(TimeInterval(state.restSecondsOnComplete))
      next.countdownStartsAt = now
      next.countdownEndsAt = endsAt
      next.countdownLabel = attributes.restLabel
      scheduleRestReminder(after: state.restSecondsOnComplete, attributes: attributes)
    } else {
      next.countdownStartsAt = nil
      next.countdownEndsAt = nil
      next.countdownLabel = nil
    }

    await activity.update(ActivityContent(state: next, staleDate: nil))
    return .result()
  }

  /// Beep di fine recupero. Id fisso: l'app lo annulla appena si risveglia,
  /// altrimenti suonerebbe due volte (il suo `SessionNotifier` programma già
  /// gli stessi segnali quando l'app va in background).
  private func scheduleRestReminder(
    after seconds: Int,
    attributes: TaccaSessionAttributes
  ) {
    let content = UNMutableNotificationContent()
    content.title = attributes.title
    content.body = attributes.restDoneLabel
    content.sound = .default

    let request = UNNotificationRequest(
      identifier: LiveSessionShared.restReminderId,
      content: content,
      trigger: UNTimeIntervalNotificationTrigger(
        timeInterval: TimeInterval(seconds),
        repeats: false
      )
    )
    UNUserNotificationCenter.current().add(request)
  }
}
