/// Raggi di arrotondamento dell'app.
///
/// Il restyling ha una forma dominante — la card bianca a raggio 26 — e
/// quattro raggi di supporto. Più valori di così e l'interfaccia sembra
/// assemblata a caso.
abstract final class AppRadius {
  /// 8 — quadratini con la sigla (numero esercizio, lettera del giro).
  static const double xs = 8;

  /// 12 — pulsante icona 40×40 e piccoli contenitori quadrati.
  static const double sm = 12;

  /// 20 — righe delle serie e campi grandi degli sheet.
  static const double md = 20;

  /// 24 — bordo superiore dei bottom sheet.
  static const double sheet = 24;

  /// 26 — **la** forma dell'app: card, righe di lista, menu, banner.
  static const double lg = 26;

  /// 32 — tab bar flottante.
  static const double xl = 32;

  /// 43 — chip. È il valore del file Figma: su un'altezza di 26–32 px si
  /// comporta come una pillola, ma resta quello.
  static const double chip = 43;

  /// Pillola: pulsanti alti 48 e ogni forma completamente arrotondata.
  static const double pill = 999;
}
