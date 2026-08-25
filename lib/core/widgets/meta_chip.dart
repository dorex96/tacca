import 'package:flutter/material.dart';

import '../design/app_colors.dart';
import '../design/app_radius.dart';
import '../design/app_spacing.dart';
import '../design/app_typography.dart';
import '../design/linear_icons.dart';
import 'linear_icon.dart';

/// Tono di una [MetaChip].
enum ChipTone {
  /// Grigia su bianco: il dato secondario dentro una card.
  neutral,

  /// Bianca su grigio: lo stesso dato quando la chip sta sul fondo pagina.
  onBackground,

  /// Lime: l'unico dato in evidenza della schermata ("In uso").
  accent,

  /// Inchiostro trasparente: la chip sopra una card lime.
  onAccent,

  /// Rosa: sessione interrotta.
  danger,
}

/// Etichetta compatta per un dato secondario (durata, numero di serie, tipo
/// di blocco, parametri).
///
/// È volutamente *non* tappabile: sostituisce le stringhe concatenate con
/// " · ", che a colpo d'occhio sono un blocco di testo unico e illeggibile.
class MetaChip extends StatelessWidget {
  const MetaChip({
    required this.label,
    this.icon,
    this.tone = ChipTone.neutral,
    this.small = true,
    super.key,
  });

  final String label;
  final LinearIconData? icon;
  final ChipTone tone;

  /// Chip piccola (26, testo 12): quella che sta *dentro* una card. False =
  /// chip grande (32, testo 13) usata sotto il titolo di una schermata.
  final bool small;

  @override
  Widget build(BuildContext context) {
    final (background, foreground, strong) = switch (tone) {
      ChipTone.neutral => (AppColors.fill, AppColors.muted, false),
      ChipTone.onBackground => (AppColors.surface, AppColors.ink, false),
      ChipTone.accent => (AppColors.lime, AppColors.ink, true),
      ChipTone.onAccent => (
        AppColors.ink.withValues(alpha: 0.16),
        AppColors.ink,
        true,
      ),
      ChipTone.danger => (AppColors.dangerSurface, AppColors.danger, true),
    };

    final style =
        (small
                ? (strong ? AppTypography.chipStrong : AppTypography.chip)
                : (strong ? AppTypography.metaStrong : AppTypography.meta))
            .copyWith(color: foreground);

    return Container(
      height: small ? 26 : 32,
      padding: EdgeInsets.symmetric(
        horizontal: small ? AppSpacing.sm + 2 : AppSpacing.lg - 2,
      ),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(AppRadius.chip),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            LinearIcon(icon!, size: small ? 14 : 16, color: foreground),
            const SizedBox(width: AppSpacing.sm),
          ],
          Text(label, style: style),
        ],
      ),
    );
  }
}
