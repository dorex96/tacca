import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/design/app_radius.dart';
import '../../../core/design/app_spacing.dart';
import '../../../data/entities/log_set.dart';
import '../../../l10n/app_localizations.dart';

/// Esito del pannello di log rapido di una serie.
sealed class SetLogOutcome {
  const SetLogOutcome();
}

/// Valori confermati dall'utente.
class SetLogSaved extends SetLogOutcome {
  const SetLogSaved({this.weightKg, this.reps, this.notes});

  final double? weightKg;
  final String? reps;
  final String? notes;
}

/// La serie va tolta dal log (spunta annullata).
class SetLogRemoved extends SetLogOutcome {
  const SetLogRemoved();
}

/// Log rapido di una serie (RF-06): peso e ripetizioni effettivi, già
/// precompilati, con incrementi a portata di pollice per evitare la tastiera
/// quando basta ritoccare il carico.
Future<SetLogOutcome?> showSetLogSheet(
  BuildContext context, {
  required String exerciseName,
  required int setNumber,
  required LogSet? current,
  double? suggestedWeightKg,
  String? suggestedReps,
}) {
  return showModalBottomSheet<SetLogOutcome>(
    context: context,
    isScrollControlled: true,
    builder: (context) => Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: _SetLogSheet(
        exerciseName: exerciseName,
        setNumber: setNumber,
        weightKg: current?.weightKg ?? suggestedWeightKg,
        reps: current?.reps ?? suggestedReps,
        notes: current?.notes,
        canRemove: current != null,
      ),
    ),
  );
}

class _SetLogSheet extends StatefulWidget {
  const _SetLogSheet({
    required this.exerciseName,
    required this.setNumber,
    required this.weightKg,
    required this.reps,
    required this.notes,
    required this.canRemove,
  });

  final String exerciseName;
  final int setNumber;
  final double? weightKg;
  final String? reps;
  final String? notes;
  final bool canRemove;

  @override
  State<_SetLogSheet> createState() => _SetLogSheetState();
}

class _SetLogSheetState extends State<_SetLogSheet> {
  late final TextEditingController _weight = TextEditingController(
    text: _formatWeight(widget.weightKg),
  );
  late final TextEditingController _reps = TextEditingController(
    text: widget.reps ?? '',
  );
  late final TextEditingController _notes = TextEditingController(
    text: widget.notes ?? '',
  );

  static String _formatWeight(double? value) {
    if (value == null) return '';
    // I carichi in palestra sono mezzi chili: niente decimali inutili.
    return value == value.roundToDouble()
        ? value.toStringAsFixed(0)
        : value.toStringAsFixed(1);
  }

  double? get _parsedWeight {
    final raw = _weight.text.trim().replaceAll(',', '.');
    if (raw.isEmpty) return null;
    return double.tryParse(raw);
  }

  void _stepWeight(double delta) {
    final next = (_parsedWeight ?? 0) + delta;
    setState(() {
      _weight.text = _formatWeight(next < 0 ? 0 : next);
    });
  }

  @override
  void dispose() {
    _weight.dispose();
    _reps.dispose();
    _notes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          0,
          AppSpacing.lg,
          AppSpacing.lg,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              l10n.workoutSetSheetTitle(widget.exerciseName, widget.setNumber),
              style: theme.textTheme.titleLarge,
            ),
            const SizedBox(height: AppSpacing.xl),
            // Il peso si ritocca quasi sempre di uno scatto: i due pulsanti
            // evitano di aprire la tastiera con le mani sudate (RNF-04).
            Row(
              children: [
                _StepButton(
                  icon: Icons.remove,
                  tooltip: '-2,5',
                  onPressed: () => _stepWeight(-2.5),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: TextField(
                    key: const ValueKey('set-weight'),
                    controller: _weight,
                    autofocus: true,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.headlineSmall,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                    ],
                    decoration: InputDecoration(
                      labelText: l10n.workoutWeightLabel,
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                _StepButton(
                  icon: Icons.add,
                  tooltip: '+2,5',
                  onPressed: () => _stepWeight(2.5),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            TextField(
              key: const ValueKey('set-reps'),
              controller: _reps,
              textAlign: TextAlign.center,
              style: theme.textTheme.headlineSmall,
              decoration: InputDecoration(labelText: l10n.workoutRepsLabel),
            ),
            const SizedBox(height: AppSpacing.md),
            TextField(
              key: const ValueKey('set-notes'),
              controller: _notes,
              decoration: InputDecoration(labelText: l10n.workoutSetNotesLabel),
            ),
            const SizedBox(height: AppSpacing.xl),
            Row(
              children: [
                if (widget.canRemove)
                  TextButton.icon(
                    onPressed: () =>
                        Navigator.of(context).pop(const SetLogRemoved()),
                    icon: const Icon(Icons.undo),
                    label: Text(l10n.workoutRemoveSet),
                  ),
                const Spacer(),
                FilledButton(
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(140, 52),
                  ),
                  onPressed: () => Navigator.of(context).pop(
                    SetLogSaved(
                      weightKg: _parsedWeight,
                      reps: _blankToNull(_reps.text),
                      notes: _blankToNull(_notes.text),
                    ),
                  ),
                  child: Text(l10n.commonSave),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String? _blankToNull(String value) =>
      value.trim().isEmpty ? null : value.trim();
}

/// Pulsante di incremento/decremento del carico: quadrato e grande, si
/// centra col pollice senza guardare.
class _StepButton extends StatelessWidget {
  const _StepButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton.filledTonal(
      onPressed: onPressed,
      icon: Icon(icon),
      iconSize: 28,
      tooltip: tooltip,
      style: IconButton.styleFrom(
        minimumSize: const Size.square(56),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.lg),
        ),
      ),
    );
  }
}
