import 'package:flutter/material.dart';

import '../design/app_colors.dart';
import '../design/app_radius.dart';
import '../design/app_spacing.dart';
import '../design/app_typography.dart';
import '../design/linear_icons.dart';
import 'linear_icon.dart';

/// Il colore di un [PillButton]. Ogni schermata ha **una** pillola scura
/// ([PillTone.primary]): è l'azione che la schermata esiste per far fare.
enum PillTone {
  /// Inchiostro pieno, testo bianco. L'azione principale.
  primary,

  /// Lime, testo inchiostro. L'azione principale quando sta sopra una
  /// superficie già scura (es. "Ferma" dentro la barra del timer).
  accent,

  /// Bianca su fondo grigio: azione secondaria in testata ("Termina").
  surface,

  /// Solo contorno: azione secondaria dentro una card bianca.
  outline,

  /// Solo contorno, testo rosa: azione distruttiva non finale.
  danger,

  /// Rosa pieno, testo inchiostro: la conferma finale di un'eliminazione.
  dangerFilled,
}

/// Pulsante pillola: altezza 48, raggio pieno, etichetta Lato 700 16.
///
/// È l'unico pulsante "grande" dell'app. Le varianti cambiano solo il
/// colore — forma, altezza e tipografia restano identiche, perché è la forma
/// a far riconoscere il pulsante prima di leggerlo.
class PillButton extends StatelessWidget {
  const PillButton({
    required this.label,
    required this.onPressed,
    this.icon,
    this.iconColor,
    this.leading,
    this.tone = PillTone.primary,
    this.expand = true,
    this.height = 48,
    super.key,
  });

  /// Variante compatta usata dentro le card e le testate: alta 44, etichetta
  /// da 14.
  const PillButton.compact({
    required this.label,
    required this.onPressed,
    this.icon,
    this.iconColor,
    this.leading,
    this.tone = PillTone.primary,
    this.expand = false,
    super.key,
  }) : height = 44;

  final String label;
  final VoidCallback? onPressed;
  final LinearIconData? icon;

  /// Colore del glifo quando deve staccarsi dall'etichetta: nel design il
  /// "Avvia recupero" della card corrente ha il triangolo lime e il testo
  /// bianco. Null = lo stesso colore dell'etichetta.
  final Color? iconColor;

  /// Glifo non standard davanti all'etichetta (il quadrato di "Ferma"):
  /// alternativo a [icon], non aggiuntivo.
  final Widget? leading;

  final PillTone tone;

  /// True = occupa tutta la larghezza disponibile.
  final bool expand;

  final double height;

  bool get _compact => height < 48;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    final (background, foreground, border) = switch (tone) {
      PillTone.primary => (AppColors.ink, AppColors.surface, null),
      PillTone.accent => (AppColors.lime, AppColors.ink, null),
      PillTone.surface => (AppColors.surface, AppColors.ink, null),
      PillTone.outline => (Colors.transparent, AppColors.ink, AppColors.stroke),
      PillTone.danger => (
        Colors.transparent,
        AppColors.danger,
        AppColors.stroke,
      ),
      PillTone.dangerFilled => (AppColors.danger, AppColors.ink, null),
    };

    final style = (_compact ? AppTypography.buttonSmall : AppTypography.button)
        .copyWith(color: enabled ? foreground : AppColors.muted);

    final content = Row(
      mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (leading != null) ...[
          leading!,
          const SizedBox(width: AppSpacing.sm),
        ] else if (icon != null) ...[
          LinearIcon(
            icon!,
            size: _compact ? 18 : 20,
            color: enabled ? (iconColor ?? foreground) : AppColors.muted,
          ),
          const SizedBox(width: AppSpacing.sm),
        ],
        Flexible(
          child: Text(
            label,
            style: style,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );

    return Material(
      color: enabled ? background : AppColors.stroke.withValues(alpha: 0.4),
      shape: border == null
          ? const StadiumBorder()
          : StadiumBorder(side: BorderSide(color: border)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onPressed,
        customBorder: const StadiumBorder(),
        child: Container(
          height: height,
          width: expand ? double.infinity : null,
          padding: EdgeInsets.symmetric(
            horizontal: _compact ? AppSpacing.card : AppSpacing.xl,
          ),
          alignment: Alignment.center,
          child: content,
        ),
      ),
    );
  }
}

/// Riquadro con il raggio della pillola usato quando serve la forma senza il
/// comportamento (barra di avanzamento, indicatori).
class ProgressLine extends StatelessWidget {
  const ProgressLine({
    required this.value,
    this.track = AppColors.stroke,
    this.color = AppColors.ink,
    super.key,
  });

  /// 0…1.
  final double value;
  final Color track;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.pill),
      child: LinearProgressIndicator(
        value: value.clamp(0, 1),
        minHeight: 4,
        backgroundColor: track,
        color: color,
      ),
    );
  }
}
