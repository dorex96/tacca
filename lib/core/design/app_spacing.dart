import 'package:flutter/widgets.dart';

/// Griglia a 8 punti (con mezzo passo a 4 e 12): ogni margine, padding e
/// distanza dell'app esce da qui.
///
/// Serve a una cosa sola: che due schermate diverse abbiano lo stesso ritmo
/// verticale. I numeri "a occhio" sparsi nei widget sono la prima causa di
/// interfacce che sembrano montate da persone diverse.
abstract final class AppSpacing {
  /// 4 — distanza fra elementi della stessa riga (icona/testo, testo/testo).
  static const double xs = 4;

  /// 8 — distanza fra elementi vicini dello stesso gruppo.
  static const double sm = 8;

  /// 12 — distanza fra campi di uno stesso form.
  static const double md = 12;

  /// 16 — margine standard del contenuto rispetto al bordo dello schermo.
  static const double lg = 16;

  /// 24 — stacco fra gruppi distinti nella stessa schermata.
  static const double xl = 24;

  /// 32 — stacco fra sezioni.
  static const double xxl = 32;

  /// Spazio libero in fondo alle liste con FAB esteso, perché l'ultimo
  /// elemento resti raggiungibile e non finisca sotto il pulsante.
  static const double fabClearance = 96;

  /// Padding di pagina per i contenuti a piena larghezza.
  static const EdgeInsets pageInsets = EdgeInsets.all(lg);

  /// Padding di pagina per le liste: stesso margine laterale, più aria in
  /// fondo per l'ultimo elemento.
  static const EdgeInsets listInsets = EdgeInsets.fromLTRB(lg, lg, lg, xxl);
}
