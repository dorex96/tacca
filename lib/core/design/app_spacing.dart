import 'package:flutter/widgets.dart';

/// Griglia a 4 punti: ogni margine, padding e distanza dell'app esce da qui.
///
/// Il ritmo del restyling è tre distanze e basta: **8** fra righe dello
/// stesso elenco, **12** fra una label e il gruppo che introduce, **24** fra
/// gruppi distinti. Il resto sono padding interni dei componenti.
abstract final class AppSpacing {
  /// 4 — distanza fra elementi della stessa riga (icona/testo, testo/testo).
  static const double xs = 4;

  /// 8 — righe consecutive di uno stesso elenco.
  static const double sm = 8;

  /// 12 — label di sezione → gruppo che introduce.
  static const double md = 12;

  /// 16 — padding interno "stretto" (banner, celle).
  static const double lg = 16;

  /// 20 — padding interno delle card e delle righe bianche.
  static const double card = 20;

  /// 24 — inset del contenuto rispetto al bordo dello schermo, e stacco fra
  /// gruppi distinti nella stessa schermata.
  static const double xl = 24;

  /// 40 — stacco fra sezioni molto diverse.
  static const double xxl = 40;

  /// Spazio libero in fondo alle liste sormontate dal pulsante pillola e
  /// dalla tab bar flottante, perché l'ultimo elemento resti raggiungibile.
  static const double dockClearance = 168;

  /// Come [dockClearance] ma senza tab bar (pagine fuori dalla shell).
  static const double actionClearance = 120;

  /// Spazio in fondo alle liste che hanno sotto solo la tab bar flottante.
  static const double tabBarClearance = 96;

  /// Inset laterale del contenuto: 24 su entrambi i lati.
  static const EdgeInsets pageInsets = EdgeInsets.symmetric(horizontal: xl);
}
