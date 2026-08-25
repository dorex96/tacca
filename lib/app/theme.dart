import 'package:flutter/material.dart';

import '../core/design/app_chrome.dart';
import '../core/design/app_colors.dart';
import '../core/design/app_radius.dart';
import '../core/design/app_spacing.dart';
import '../core/design/app_typography.dart';

/// Tema dell'app: il restyling sul linguaggio visivo del file Figma
/// "Gym full figma" — fondo `#F4F4F6`, superfici bianche a raggio 26,
/// inchiostro `#192126`, un solo accento lime `#BBF246`.
///
/// Qui vive **tutto** ciò che deve restare identico ovunque: colori, raggi,
/// altezze minime dei controlli, stile di card, campi, sheet e menu. Le
/// pagine non ridefiniscono questi valori — così una card dell'archivio e una
/// della sessione sono la stessa card.
///
/// **Un solo tema, non due.** Il design definisce una palette sola; una
/// versione scura sarebbe una seconda interfaccia inventata qui e non
/// disegnata da nessuna parte. [App] blocca quindi `themeMode` su chiaro: un
/// telefono in dark mode vede comunque l'app come è stata disegnata, non una
/// sua approssimazione.
///
/// Nota tecnica: gli stili dei component theme vanno costruiti da
/// [AppTypography] e mai ripresi da `ThemeData(...).textTheme`, perché
/// `ThemeData` fonde le *dimensioni* tipografiche solo dentro `textTheme`
/// (uno stile preso da lì arriverebbe senza `fontSize`).
abstract final class AppTheme {
  /// Area minima dei controlli tappabili: l'app si usa in palestra, spesso
  /// con una mano sola e senza guardare (RNF-04).
  static const Size _minTapSize = Size(64, 48);

  static ThemeData get theme => _build();

  static ThemeData _build() {
    const scheme = ColorScheme(
      brightness: Brightness.light,
      primary: AppColors.ink,
      onPrimary: AppColors.surface,
      primaryContainer: AppColors.lime,
      onPrimaryContainer: AppColors.ink,
      secondary: AppColors.lime,
      onSecondary: AppColors.ink,
      secondaryContainer: AppColors.lime,
      onSecondaryContainer: AppColors.ink,
      tertiary: AppColors.ink,
      onTertiary: AppColors.surface,
      tertiaryContainer: AppColors.lime,
      onTertiaryContainer: AppColors.ink,
      error: AppColors.danger,
      onError: AppColors.ink,
      errorContainer: AppColors.dangerSurface,
      onErrorContainer: AppColors.ink,
      surface: AppColors.background,
      onSurface: AppColors.ink,
      onSurfaceVariant: AppColors.muted,
      surfaceContainerLowest: AppColors.surface,
      surfaceContainerLow: AppColors.surface,
      surfaceContainer: AppColors.surface,
      surfaceContainerHigh: AppColors.fill,
      surfaceContainerHighest: AppColors.fill,
      outline: AppColors.stroke,
      outlineVariant: AppColors.stroke,
      inverseSurface: AppColors.ink,
      onInverseSurface: AppColors.surface,
      inversePrimary: AppColors.lime,
      shadow: Color(0xFF000000),
      scrim: AppColors.scrim,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      textTheme: _textTheme,
      scaffoldBackgroundColor: AppColors.background,
      canvasColor: AppColors.surface,
      splashFactory: InkSparkle.splashFactory,
      iconTheme: const IconThemeData(color: AppColors.ink, size: 24),

      // Le pagine disegnano la propria intestazione (pulsanti icona quadrati
      // + titolo Lato Black nel corpo): l'AppBar resta configurata per le
      // poche schermate di servizio che la usano ancora.
      appBarTheme: const AppBarThemeData(
        backgroundColor: AppColors.background,
        foregroundColor: AppColors.ink,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        toolbarHeight: 64,
        titleTextStyle: AppTypography.screenTitle,
        iconTheme: IconThemeData(color: AppColors.ink),
        actionsIconTheme: IconThemeData(color: AppColors.ink),
        systemOverlayStyle: AppChrome.systemOverlay,
      ),

      // La forma dell'app: bianca, raggio 26, senza bordo e senza ombra. Si
      // stacca dal fondo per luminosità, non per contorno.
      cardTheme: CardThemeData(
        elevation: 0,
        color: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        shadowColor: Colors.transparent,
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.lg),
        ),
      ),

      listTileTheme: ListTileThemeData(
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.card,
          vertical: AppSpacing.xs,
        ),
        minVerticalPadding: AppSpacing.md,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.lg),
        ),
        iconColor: AppColors.muted,
        titleTextStyle: AppTypography.row,
        subtitleTextStyle: AppTypography.paragraphSmall,
      ),

      // Campi pieni, senza contorno: il contorno lo fa il colore della
      // superficie. Il focus è l'unico stato che disegna un bordo.
      inputDecorationTheme: InputDecorationThemeData(
        filled: true,
        fillColor: AppColors.surface,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.card,
          vertical: AppSpacing.lg,
        ),
        border: _fieldBorder(Colors.transparent),
        enabledBorder: _fieldBorder(Colors.transparent),
        disabledBorder: _fieldBorder(Colors.transparent),
        focusedBorder: _fieldBorder(AppColors.ink, width: 1.5),
        errorBorder: _fieldBorder(AppColors.danger),
        focusedErrorBorder: _fieldBorder(AppColors.danger, width: 1.5),
        labelStyle: AppTypography.sectionLabel,
        floatingLabelStyle: AppTypography.meta,
        hintStyle: AppTypography.row.copyWith(color: AppColors.muted),
        helperStyle: AppTypography.meta,
        errorStyle: AppTypography.meta.copyWith(color: AppColors.danger),
        prefixIconColor: AppColors.muted,
        suffixIconColor: AppColors.muted,
      ),

      // Pillola scura: l'azione principale di ogni schermata.
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.ink,
          foregroundColor: AppColors.surface,
          disabledBackgroundColor: AppColors.stroke,
          disabledForegroundColor: AppColors.muted,
          minimumSize: _minTapSize,
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
          elevation: 0,
          shape: const StadiumBorder(),
          textStyle: AppTypography.button,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.ink,
          minimumSize: _minTapSize,
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.card),
          side: const BorderSide(color: AppColors.stroke),
          shape: const StadiumBorder(),
          textStyle: AppTypography.button,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.ink,
          minimumSize: const Size(48, 48),
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
          shape: const StadiumBorder(),
          textStyle: AppTypography.buttonSmall,
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          foregroundColor: AppColors.ink,
          minimumSize: const Size.square(44),
          shape: const CircleBorder(),
        ),
      ),

      chipTheme: ChipThemeData(
        backgroundColor: AppColors.fill,
        selectedColor: AppColors.lime,
        side: BorderSide.none,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.chip),
        ),
        labelStyle: AppTypography.chip,
        secondaryLabelStyle: AppTypography.chipStrong,
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
        iconTheme: const IconThemeData(color: AppColors.muted, size: 16),
      ),

      // I pannelli modali coprono la pagina: raggio 24 in alto e chiusura
      // con la X in testata (niente maniglia — nel design non c'è).
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: AppColors.surface,
        modalBackgroundColor: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        modalBarrierColor: AppColors.scrim,
        showDragHandle: false,
        elevation: 0,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(AppRadius.sheet),
          ),
        ),
      ),

      dialogTheme: DialogThemeData(
        backgroundColor: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        barrierColor: AppColors.scrim,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.lg),
        ),
        insetPadding: const EdgeInsets.all(AppSpacing.xl),
        titleTextStyle: AppTypography.sheetTitle,
        contentTextStyle: AppTypography.paragraph,
      ),

      popupMenuTheme: PopupMenuThemeData(
        color: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        shadowColor: const Color(0x26000000),
        elevation: 8,
        menuPadding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.lg),
        ),
        textStyle: AppTypography.row,
      ),

      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppColors.ink,
        contentTextStyle: AppTypography.paragraph.copyWith(
          color: AppColors.surface,
        ),
        actionTextColor: AppColors.lime,
        insetPadding: const EdgeInsets.all(AppSpacing.xl),
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.lg),
        ),
      ),

      // Dentro una card la tile espandibile non deve disegnare le proprie
      // linee di separazione: il contenitore è già la card.
      expansionTileTheme: const ExpansionTileThemeData(
        shape: RoundedRectangleBorder(side: BorderSide.none),
        collapsedShape: RoundedRectangleBorder(side: BorderSide.none),
        tilePadding: EdgeInsets.symmetric(horizontal: AppSpacing.lg),
        childrenPadding: EdgeInsets.zero,
        iconColor: AppColors.ink,
        collapsedIconColor: AppColors.muted,
        backgroundColor: AppColors.surface,
        collapsedBackgroundColor: AppColors.surface,
      ),

      dividerTheme: const DividerThemeData(
        color: AppColors.stroke,
        thickness: 1,
        space: AppSpacing.xl,
      ),

      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: AppColors.ink,
        linearTrackColor: AppColors.stroke,
        circularTrackColor: Colors.transparent,
        linearMinHeight: 4,
      ),
    );
  }

  static OutlineInputBorder _fieldBorder(Color color, {double width = 1}) {
    return OutlineInputBorder(
      borderRadius: BorderRadius.circular(AppRadius.md),
      borderSide: BorderSide(color: color, width: width),
    );
  }

  /// I ruoli Material mappati sui token del design. Le pagine usano
  /// [AppTypography] direttamente; questo serve ai widget di framework che
  /// pescano dal `TextTheme` (dialog, snackbar, `ListTile`, `DropdownMenu`).
  static const TextTheme _textTheme = TextTheme(
    displayLarge: AppTypography.clock,
    displayMedium: AppTypography.clock,
    displaySmall: AppTypography.clock,
    headlineLarge: AppTypography.screenTitle,
    headlineMedium: AppTypography.screenTitle,
    headlineSmall: AppTypography.sheetTitleLong,
    titleLarge: AppTypography.subtitle,
    titleMedium: AppTypography.cardTitle,
    titleSmall: AppTypography.blockType,
    bodyLarge: AppTypography.row,
    bodyMedium: AppTypography.paragraph,
    bodySmall: AppTypography.paragraphSmall,
    labelLarge: AppTypography.button,
    labelMedium: AppTypography.meta,
    labelSmall: AppTypography.chip,
  );
}
