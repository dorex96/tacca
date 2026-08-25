import 'package:flutter/material.dart';

import '../design/app_colors.dart';
import '../design/app_radius.dart';
import '../design/app_spacing.dart';

/// La forma dell'app: superficie bianca, raggio 26, nessun bordo e nessuna
/// ombra.
///
/// Usarla ovunque serva "un pezzo di contenuto sopra il fondo" — card di un
/// blocco, riga di lista, banner, riquadro di testo. Le pagine non
/// costruiscono più [Container] con `BoxDecoration` a mano: è così che negli
/// stessi elenchi finivano raggi diversi.
class SurfaceCard extends StatelessWidget {
  const SurfaceCard({
    required this.child,
    this.onTap,
    this.padding = const EdgeInsets.all(AppSpacing.card),
    this.color = AppColors.surface,
    this.radius = AppRadius.lg,
    super.key,
  });

  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry padding;

  /// Lime per l'unico elemento in evidenza della schermata; [AppColors.fill]
  /// per un riquadro *dentro* una card bianca.
  final Color color;

  final double radius;

  @override
  Widget build(BuildContext context) {
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(radius),
    );

    return Material(
      color: color,
      shape: shape,
      clipBehavior: Clip.antiAlias,
      child: onTap == null
          ? Padding(padding: padding, child: child)
          : InkWell(
              onTap: onTap,
              customBorder: shape,
              child: Padding(padding: padding, child: child),
            ),
    );
  }
}
