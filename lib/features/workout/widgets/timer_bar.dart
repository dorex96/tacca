import 'package:flutter/material.dart';

import '../../../core/design/app_radius.dart';
import '../../../core/design/app_spacing.dart';
import '../../../core/extensions/duration_format.dart';
import '../../../l10n/app_localizations.dart';
import '../../../services/timer/timer_engine.dart';

/// Barra del timer attivo: numeri grandi, leggibili con il telefono
/// appoggiato a distanza (RNF-04).
///
/// È l'unico elemento a piena tinta della sessione: quando c'è un timer in
/// corso deve essere la prima cosa che si vede entrando nella schermata.
class TimerBar extends StatelessWidget {
  const TimerBar({required this.timer, required this.onStop, super.key});

  final TimerState timer;
  final VoidCallback onStop;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    final finished = timer.isFinished;
    final background = finished ? scheme.tertiaryContainer : scheme.primary;
    final foreground = finished ? scheme.onTertiaryContainer : scheme.onPrimary;

    // Nel countdown conta il tempo che manca; nel cronometro senza time cap
    // conta quello trascorso.
    final display = timer.spec.isCountUp
        ? timer.elapsed
        : (timer.remaining ?? Duration.zero);

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.md,
        AppSpacing.lg,
        AppSpacing.xs,
      ),
      child: Material(
        color: background,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _caption(l10n),
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: foreground.withValues(alpha: 0.85),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      finished ? l10n.workoutTimerFinished : display.clock,
                      style: theme.textTheme.displaySmall?.copyWith(
                        color: foreground,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                    if (!timer.spec.isCountUp) ...[
                      const SizedBox(height: AppSpacing.md),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(AppRadius.sm),
                        child: LinearProgressIndicator(
                          value: timer.progress,
                          color: foreground,
                          backgroundColor: foreground.withValues(alpha: 0.24),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              FilledButton.icon(
                onPressed: onStop,
                icon: const Icon(Icons.stop_rounded),
                label: Text(l10n.workoutStopTimer),
                style: FilledButton.styleFrom(
                  backgroundColor: foreground.withValues(alpha: 0.18),
                  foregroundColor: foreground,
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.lg,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _caption(AppLocalizations l10n) {
    final parts = <String>[
      if ((timer.spec.label ?? '').isNotEmpty) timer.spec.label!,
      if (timer.totalRounds > 1)
        l10n.workoutTimerRound(timer.round, timer.totalRounds),
      if (timer.spec.kind == TimerKind.tabata)
        timer.phase == TimerPhase.work
            ? l10n.workoutTimerWork
            : l10n.workoutTimerRest
      else if (timer.spec.kind == TimerKind.rest)
        l10n.workoutTimerRest,
    ];
    return parts.join(' · ');
  }
}
