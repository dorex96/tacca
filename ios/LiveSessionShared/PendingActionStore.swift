import Foundation

/// Azione eseguita dall'utente sulla Live Activity.
///
/// I campi ricalcano `LiveSessionAction` sul lato Dart: il dizionario prodotto
/// da [asDictionary] attraversa il MethodChannel così com'è.
struct PendingLiveAction: Codable {
  let id: String
  let kind: String
  let logId: Int
  let entryIndex: Int
  let setNumber: Int

  /// Millisecondi dall'epoca, come li aspetta il Dart.
  let at: Int

  var asDictionary: [String: Any] {
    [
      "id": id,
      "kind": kind,
      "logId": logId,
      "entryIndex": entryIndex,
      "setNumber": setNumber,
      "at": at,
    ]
  }
}

/// Coda delle conferme date dalla schermata di blocco.
///
/// L'App Intent gira nel processo dell'estensione, dove non esistono né il
/// motore Dart né il database: l'unica cosa che può fare è lasciare qui
/// l'azione. L'app la raccoglie al rientro in primo piano e la trasforma in
/// una serie registrata, con l'orario del tap.
enum PendingActionStore {
  private static var defaults: UserDefaults? {
    UserDefaults(suiteName: LiveSessionShared.appGroupId)
  }

  static func append(_ action: PendingLiveAction) {
    guard let defaults = defaults else { return }
    var stored = load(from: defaults)
    stored.append(action)
    guard let data = try? JSONEncoder().encode(stored) else { return }
    defaults.set(data, forKey: LiveSessionShared.pendingActionsKey)
  }

  /// Restituisce le azioni accumulate e svuota la coda.
  static func drain() -> [[String: Any]] {
    guard let defaults = defaults else { return [] }
    let stored = load(from: defaults)
    if !stored.isEmpty {
      defaults.removeObject(forKey: LiveSessionShared.pendingActionsKey)
    }
    return stored.map { $0.asDictionary }
  }

  static func clear() {
    defaults?.removeObject(forKey: LiveSessionShared.pendingActionsKey)
  }

  private static func load(from defaults: UserDefaults) -> [PendingLiveAction] {
    guard let data = defaults.data(forKey: LiveSessionShared.pendingActionsKey),
          let decoded = try? JSONDecoder().decode([PendingLiveAction].self, from: data)
    else {
      return []
    }
    return decoded
  }
}
