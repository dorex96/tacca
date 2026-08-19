import 'package:objectbox/objectbox.dart';

import 'block.dart';

/// Esercizio prescritto all'interno di un blocco.
///
/// `reps` e `load` restano stringhe libere (`"8-12"`, `"max"`, `"70% 1RM"`):
/// in scheda il carico prescritto non è un numero (§4 nota "Peso come numero").
@Entity()
class Exercise {
  @Id()
  int id = 0;

  String name;
  int? sets;
  String? reps;
  String? load;
  int? restSeconds;
  int? durationSeconds;
  String? notes;
  int sortOrder;

  final block = ToOne<Block>();

  Exercise({
    required this.name,
    this.sets,
    this.reps,
    this.load,
    this.restSeconds,
    this.durationSeconds,
    this.notes,
    this.sortOrder = 0,
  });
}
