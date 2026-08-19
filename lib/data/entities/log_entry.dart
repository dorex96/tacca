import 'package:objectbox/objectbox.dart';

import 'log_set.dart';
import 'workout_log.dart';

/// Riga di log per un esercizio all'interno di una sessione.
///
/// Conserva il nome dell'esercizio (snapshot), non solo il riferimento (§4).
@Entity()
class LogEntry {
  @Id()
  int id = 0;

  String exerciseNameSnapshot;
  int sortOrder;

  final log = ToOne<WorkoutLog>();

  @Backlink('entry')
  final sets = ToMany<LogSet>();

  LogEntry({required this.exerciseNameSnapshot, this.sortOrder = 0});
}
