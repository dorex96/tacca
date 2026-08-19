import 'package:objectbox/objectbox.dart';

import 'log_entry.dart';
import 'workout_day.dart';
import 'workout_plan.dart';

/// Stato di una sessione di allenamento registrata.
enum WorkoutStatus { inProgress, completed, aborted }

/// Registro di una sessione di allenamento (RF-06/RF-07).
///
/// Snapshot-based: conserva il nome della scheda e del giorno, così lo storico
/// resta leggibile anche dopo modifica o eliminazione della scheda (§4).
@Entity()
class WorkoutLog {
  @Id()
  int id = 0;

  @Property(type: PropertyType.date)
  DateTime startedAt;

  @Property(type: PropertyType.date)
  DateTime? finishedAt;

  /// Persistito come stringa; API pubblica tramite [status].
  String dbStatus;

  @Transient()
  WorkoutStatus get status => WorkoutStatus.values.byName(dbStatus);

  @Transient()
  set status(WorkoutStatus value) => dbStatus = value.name;

  String? notes;

  // Snapshot: la scheda potrebbe non esistere più al momento della lettura.
  String planNameSnapshot;
  String dayLabelSnapshot;

  /// Riferimento debole alla scheda: può non esistere più (§4).
  final plan = ToOne<WorkoutPlan>();

  /// Riferimento debole al giorno svolto: serve a ricostruire la struttura
  /// prescritta quando si riprende una sessione interrotta (RF-06). Come per
  /// [plan] può risultare vuoto se la scheda è stata modificata o eliminata:
  /// in quel caso restano gli snapshot testuali e le entry già registrate.
  final day = ToOne<WorkoutDay>();

  @Backlink('log')
  final entries = ToMany<LogEntry>();

  WorkoutLog({
    required this.startedAt,
    this.finishedAt,
    required this.dbStatus,
    this.notes,
    required this.planNameSnapshot,
    required this.dayLabelSnapshot,
  });

  WorkoutLog.start({
    required DateTime startedAt,
    required String planNameSnapshot,
    required String dayLabelSnapshot,
  }) : this(
         startedAt: startedAt,
         dbStatus: WorkoutStatus.inProgress.name,
         planNameSnapshot: planNameSnapshot,
         dayLabelSnapshot: dayLabelSnapshot,
       );

  /// Durata della sessione: fino a [finishedAt] se conclusa, altrimenti fino a
  /// [now] (default: adesso) per la sessione ancora in corso.
  Duration duration({DateTime? now}) =>
      (finishedAt ?? now ?? DateTime.now()).difference(startedAt);
}
