import 'package:objectbox/objectbox.dart';

import 'exercise.dart';
import 'workout_day.dart';

/// Tipi di blocco supportati (§4.1). Persistiti come [String] (`.name`),
/// robusti al riordino dell'enum.
enum BlockType {
  standard,
  superset,
  circuit,
  emom,
  amrap,
  tabata,
  forTime,
  freeText,
}

/// Blocco di allenamento all'interno di un giorno.
///
/// Nessun polimorfismo: i parametri specifici del tipo sono campi nullable
/// piatti (§4). Solo i campi pertinenti al [type] vengono valorizzati.
@Entity()
class Block {
  @Id()
  int id = 0;

  int sortOrder;
  String? notes;

  /// Persistito come stringa; API pubblica tramite [type].
  String dbType;

  @Transient()
  BlockType get type => BlockType.values.byName(dbType);

  @Transient()
  set type(BlockType value) => dbType = value.name;

  // Parametri per tipo — piatti e nullable (§4).
  int? intervalSeconds; // emom
  int? totalMinutes; // emom
  int? durationSeconds; // amrap
  int? workSeconds; // tabata
  int? restSeconds; // tabata
  int? rounds; // superset, circuit, tabata
  int? restBetweenRoundsSeconds; // circuit
  int? timeCapSeconds; // forTime
  String? freeTextContent; // freeText

  final day = ToOne<WorkoutDay>();

  @Backlink('block')
  final exercises = ToMany<Exercise>();

  Block({required this.dbType, this.sortOrder = 0, this.notes});

  /// Costruttore comodo a partire dall'enum.
  Block.ofType(BlockType type, {int sortOrder = 0, String? notes})
    : this(dbType: type.name, sortOrder: sortOrder, notes: notes);
}
