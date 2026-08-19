import 'package:tacca/objectbox.g.dart';

import '../entities/block.dart';
import '../entities/exercise.dart';
import '../entities/log_entry.dart';
import '../entities/log_set.dart';
import '../entities/workout_day.dart';
import '../entities/workout_log.dart';
import '../entities/workout_plan.dart';

/// Punto di accesso unico allo [Store] ObjectBox.
///
/// Incapsula l'apertura del database e l'accesso ai [Box]. È l'unico posto,
/// insieme ai repository, in cui `Store`/`Box` possono comparire (ADR-01):
/// Cubit/Bloc e UI non lo toccano mai direttamente.
class ObjectBox {
  final Store store;

  late final Box<WorkoutPlan> planBox = store.box<WorkoutPlan>();
  late final Box<WorkoutDay> dayBox = store.box<WorkoutDay>();
  late final Box<Block> blockBox = store.box<Block>();
  late final Box<Exercise> exerciseBox = store.box<Exercise>();
  late final Box<WorkoutLog> logBox = store.box<WorkoutLog>();
  late final Box<LogEntry> logEntryBox = store.box<LogEntry>();
  late final Box<LogSet> logSetBox = store.box<LogSet>();

  ObjectBox._(this.store);

  /// Apre lo Store nella directory di default dell'app
  /// (`defaultStoreDirectory()` di objectbox_flutter_libs). Chiamare in
  /// `main()` prima di `runApp`.
  static Future<ObjectBox> open() async {
    final store = await openStore();
    return ObjectBox._(store);
  }

  /// Crea un'istanza attorno a uno [Store] già aperto (utile nei test).
  factory ObjectBox.fromStore(Store store) => ObjectBox._(store);

  void close() => store.close();
}
