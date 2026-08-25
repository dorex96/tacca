import 'package:flutter/painting.dart';

/// Palette del restyling: i colori esatti del file Figma "Gym full figma".
///
/// Sono **otto** valori e non uno di più. L'interfaccia si regge su un
/// contrasto solo — inchiostro scuro su fondo chiarissimo — e su un unico
/// accento acido usato per dire "questo, adesso": la scheda in uso, la tab
/// attiva, l'esercizio corrente. Ogni colore aggiunto qui toglie forza a
/// quell'accento, quindi si aggiunge solo se il design lo prevede.
///
/// Regola non negoziabile: **sopra il lime il testo è sempre [ink]**. Il lime
/// ha luminanza alta, il bianco sopra non si legge.
abstract final class AppColors {
  /// Fondo di ogni schermata. Le superfici bianche ci galleggiano sopra.
  static const Color background = Color(0xFFF4F4F6);

  /// Card, righe, sheet, menu: tutto ciò che sta "sopra" il fondo.
  static const Color surface = Color(0xFFFFFFFF);

  /// Inchiostro: titoli, testo primario e superfici scure (pulsante
  /// principale, tab bar, barra del timer).
  static const Color ink = Color(0xFF192126);

  /// Testo dei paragrafi lunghi (descrizione, note): leggermente più chiaro
  /// di [ink] perché a paragrafo il nero pieno stanca.
  static const Color body = Color(0xFF232A3A);

  /// Dati secondari: label di sezione, meta, placeholder.
  static const Color muted = Color(0xFF8C9092);

  /// Accento. Un solo elemento per schermata lo porta.
  static const Color lime = Color(0xFFBBF246);

  /// Contorni: si disegnano con `inset` (un box shadow interno o un
  /// [Border] da 1px), mai come divider a piena larghezza.
  static const Color stroke = Color(0xFFD4D8E0);

  /// Azioni distruttive. Compare solo come *testo* (voce di menu, "Rimuovi
  /// serie") o come fondo dell'unica conferma finale di eliminazione.
  static const Color danger = Color(0xFFFF5678);

  /// Velo rosa dietro un dato distruttivo (chip "Interrotta"): il rosa
  /// pieno come fondo di un testo non si legge, questo sì.
  static const Color dangerSurface = Color(0xFFFFE3EA);

  /// Riempimento neutro *dentro* una superficie bianca: righe delle serie,
  /// campi degli sheet, chip. È lo stesso tono del fondo schermata, che è
  /// ciò che fa sembrare "scavati" questi elementi.
  static const Color fill = background;

  /// Velo sotto sheet e dialog.
  static const Color scrim = Color(0x66192126);
}
