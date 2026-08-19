import '../data/entities/block.dart';
import '../l10n/app_localizations.dart';

/// Etichetta localizzata per un [BlockType], condivisa tra editor e dettaglio.
String blockTypeLabel(AppLocalizations l10n, BlockType type) {
  switch (type) {
    case BlockType.standard:
      return l10n.blockTypeStandard;
    case BlockType.superset:
      return l10n.blockTypeSuperset;
    case BlockType.circuit:
      return l10n.blockTypeCircuit;
    case BlockType.emom:
      return l10n.blockTypeEmom;
    case BlockType.amrap:
      return l10n.blockTypeAmrap;
    case BlockType.tabata:
      return l10n.blockTypeTabata;
    case BlockType.forTime:
      return l10n.blockTypeForTime;
    case BlockType.freeText:
      return l10n.blockTypeFreeText;
  }
}
