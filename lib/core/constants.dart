import 'package:flutter/widgets.dart';

/// Costanti applicative condivise.
abstract final class AppConstants {
  /// Locale supportate: italiano (default) e inglese.
  static const List<Locale> supportedLocales = [Locale('it'), Locale('en')];

  /// Termini e condizioni completi. Si aprono nel browser di sistema
  /// (`LinkOpener`): l'app non incorpora nessuna WebView.
  static const String termsUrl =
      'https://tverdohleb.dev/apps/tacca/terminiecondizioni.html';

  /// Versione dell'informativa mostrata al primo avvio (`LegalNoticeCubit`).
  ///
  /// Quello che viene salvato non è un booleano ma questo numero: alzarlo di
  /// uno quando cambia la sostanza dei termini rimette l'avviso davanti anche
  /// a chi aveva già accettato la versione precedente.
  static const int legalNoticeVersion = 1;
}
