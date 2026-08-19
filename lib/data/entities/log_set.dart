import 'package:objectbox/objectbox.dart';

import 'log_entry.dart';

/// Singola serie registrata durante l'allenamento.
///
/// Il peso è un numero (`weightKg`) per alimentare "ultima volta" e i futuri
/// grafici; le ripetizioni restano stringa libera (§4).
@Entity()
class LogSet {
  @Id()
  int id = 0;

  int setNumber;
  String? reps;
  double? weightKg;
  String? notes;

  @Property(type: PropertyType.date)
  DateTime completedAt;

  final entry = ToOne<LogEntry>();

  LogSet({
    required this.setNumber,
    this.reps,
    this.weightKg,
    this.notes,
    required this.completedAt,
  });
}
