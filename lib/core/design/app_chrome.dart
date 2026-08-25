import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'app_colors.dart';

/// Ciò che sta *sopra* la pagina: ombre dei livelli flottanti e aspetto
/// delle barre di sistema.
///
/// Nel restyling l'ombra è un'eccezione, non un livello di profondità
/// generico: le card non ne hanno, e ce l'hanno solo le superfici che
/// compaiono davanti al contenuto (menu contestuali, tab bar flottante).
abstract final class AppChrome {
  /// L'ombra del file di design:
  /// `0 8px 24px rgba(0,0,0,.15), 0 2px 6px rgba(0,0,0,.06)`.
  static const List<BoxShadow> floating = [
    BoxShadow(color: Color(0x26000000), blurRadius: 24, offset: Offset(0, 8)),
    BoxShadow(color: Color(0x0F000000), blurRadius: 6, offset: Offset(0, 2)),
  ];

  /// Barra di stato trasparente con icone scure: il fondo dell'app è chiaro
  /// ovunque, quindi non cambia mai.
  static const SystemUiOverlayStyle systemOverlay = SystemUiOverlayStyle(
    statusBarColor: Color(0x00000000),
    statusBarIconBrightness: Brightness.dark,
    statusBarBrightness: Brightness.light,
    systemNavigationBarColor: AppColors.background,
    systemNavigationBarIconBrightness: Brightness.dark,
  );
}
