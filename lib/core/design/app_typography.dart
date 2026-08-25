import 'package:flutter/painting.dart';

import 'app_colors.dart';

/// Tipografia del restyling.
///
/// Due caratteri con due ruoli distinti, mai mescolati dentro la stessa riga:
///
/// * **Lato** per tutta l'interfaccia — titoli, righe, pulsanti, numeri.
///   Serrata, con line-height quasi nullo: è ciò che dà alle schermate
///   l'aspetto "impaginato" invece che "elencato".
/// * **il carattere di sistema** (SF Pro su iOS, Roboto su Android) per i
///   paragrafi in prosa: descrizione della scheda, note, spiegazioni. Un
///   paragrafo lungo in Lato serrato non si legge.
///
/// I paragrafi si ottengono lasciando `fontFamily` a null: `TextTheme` non
/// eredita alcuna famiglia globale, perché [AppTheme] non imposta mai
/// `ThemeData.fontFamily`.
///
/// **Sui pesi.** Il design nomina Lato Medium (500) ed ExtraBold (800), che
/// però non esistono: la famiglia pubblicata ha 400/700/900. Sono quelli i
/// pesi che il canvas del design ha davvero renderizzato, e sono quelli che
/// stanno qui — scritti espliciti, così nessuno si chiede perché un "500"
/// arrivi regolare.
abstract final class AppTypography {
  static const String fontFamily = 'Lato';

  static const List<FontFeature> _tabular = [FontFeature.tabularFigures()];

  // ---------------------------------------------------------------- Lato

  /// Titolo di schermata ("Le mie schede", "Giorno A"). Lato Black 24.
  static const TextStyle screenTitle = TextStyle(
    fontFamily: fontFamily,
    fontSize: 24,
    height: 1.0,
    fontWeight: FontWeight.w900,
    color: AppColors.ink,
  );

  /// Titolo di un bottom sheet.
  static const TextStyle sheetTitle = screenTitle;

  /// Titolo di sheet con testo lungo (nome esercizio + numero di serie).
  static const TextStyle sheetTitleLong = TextStyle(
    fontFamily: fontFamily,
    fontSize: 22,
    height: 1.2,
    fontWeight: FontWeight.w900,
    color: AppColors.ink,
  );

  /// Sottotitolo: giorno nel dettaglio scheda, nome dell'esercizio corrente.
  static const TextStyle subtitle = TextStyle(
    fontFamily: fontFamily,
    fontSize: 18,
    height: 1.2,
    fontWeight: FontWeight.w900,
    color: AppColors.ink,
  );

  /// Titolo di una card non in evidenza.
  static const TextStyle cardTitle = TextStyle(
    fontFamily: fontFamily,
    fontSize: 16,
    height: 1.2,
    fontWeight: FontWeight.w700,
    color: AppColors.ink,
  );

  /// Etichetta di un pulsante pillola.
  static const TextStyle button = TextStyle(
    fontFamily: fontFamily,
    fontSize: 16,
    height: 1.5,
    fontWeight: FontWeight.w700,
    color: AppColors.ink,
  );

  /// Etichetta di un pulsante compatto (alto 40–44).
  static const TextStyle buttonSmall = TextStyle(
    fontFamily: fontFamily,
    fontSize: 14,
    height: 1.2,
    fontWeight: FontWeight.w700,
    color: AppColors.ink,
  );

  /// Tipo di blocco ("Superset", "EMOM"): maiuscoletto tipografico ottenuto
  /// con la spaziatura, non con `toUpperCase()`.
  static const TextStyle blockType = TextStyle(
    fontFamily: fontFamily,
    fontSize: 14,
    height: 1.2,
    fontWeight: FontWeight.w700,
    letterSpacing: 0.6,
    color: AppColors.ink,
  );

  /// Riga di elenco, voce di menu, label di campo: il peso "corrente".
  static const TextStyle row = TextStyle(
    fontFamily: fontFamily,
    fontSize: 16,
    height: 1.2,
    fontWeight: FontWeight.w400,
    color: AppColors.ink,
  );

  /// Riga di elenco in evidenza (nome della scheda in uso).
  static const TextStyle rowStrong = TextStyle(
    fontFamily: fontFamily,
    fontSize: 16,
    height: 1.2,
    fontWeight: FontWeight.w700,
    color: AppColors.ink,
  );

  /// Label di sezione ("In uso", "Schede", "Archiviate", "Descrizione").
  static const TextStyle sectionLabel = TextStyle(
    fontFamily: fontFamily,
    fontSize: 16,
    height: 1.2,
    fontWeight: FontWeight.w400,
    color: AppColors.muted,
  );

  /// Dato secondario accanto a una riga ("3 giorni").
  static const TextStyle meta = TextStyle(
    fontFamily: fontFamily,
    fontSize: 13,
    height: 1.2,
    fontWeight: FontWeight.w400,
    color: AppColors.muted,
  );

  /// Come [meta], ma è un dato che va notato.
  static const TextStyle metaStrong = TextStyle(
    fontFamily: fontFamily,
    fontSize: 13,
    height: 1.2,
    fontWeight: FontWeight.w700,
    color: AppColors.ink,
  );

  /// Testo dentro una chip piccola.
  static const TextStyle chip = TextStyle(
    fontFamily: fontFamily,
    fontSize: 12,
    height: 1.0,
    fontWeight: FontWeight.w400,
    color: AppColors.muted,
  );

  /// Chip che porta un conteggio in corso ("2/4 serie").
  static const TextStyle chipStrong = TextStyle(
    fontFamily: fontFamily,
    fontSize: 12,
    height: 1.0,
    fontWeight: FontWeight.w700,
    color: AppColors.ink,
  );

  /// Cifre del timer: enormi, incolonnate, leggibili col telefono appoggiato
  /// a terra (RNF-04).
  static const TextStyle clock = TextStyle(
    fontFamily: fontFamily,
    fontSize: 44,
    height: 1.0,
    fontWeight: FontWeight.w900,
    color: AppColors.surface,
    fontFeatures: _tabular,
  );

  /// Valore numerico allineato a destra in una riga (carico × ripetizioni).
  static const TextStyle numeric = TextStyle(
    fontFamily: fontFamily,
    fontSize: 16,
    height: 1.2,
    fontWeight: FontWeight.w700,
    color: AppColors.ink,
    fontFeatures: _tabular,
  );

  /// Numero grande di un campo (peso e ripetizioni nel log rapido).
  static const TextStyle numericField = TextStyle(
    fontFamily: fontFamily,
    fontSize: 22,
    height: 1.2,
    fontWeight: FontWeight.w900,
    color: AppColors.ink,
    fontFeatures: _tabular,
  );

  // ------------------------------------------------- carattere di sistema

  /// Paragrafo in prosa. `fontFamily` volutamente nullo: è il carattere di
  /// sistema.
  static const TextStyle paragraph = TextStyle(
    fontSize: 14,
    height: 1.5,
    fontWeight: FontWeight.w400,
    color: AppColors.body,
  );

  /// Paragrafo secondario (note di un blocco, sottotitolo di una riga).
  static const TextStyle paragraphSmall = TextStyle(
    fontSize: 13,
    height: 1.5,
    fontWeight: FontWeight.w400,
    color: AppColors.muted,
  );

  /// Riga di servizio sotto una card ("Ultima volta (12/08): …").
  static const TextStyle caption = TextStyle(
    fontSize: 12,
    height: 1.4,
    fontWeight: FontWeight.w400,
    color: AppColors.muted,
  );
}
