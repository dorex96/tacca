import 'package:objectbox/objectbox.dart';

import 'block.dart';
import 'workout_plan.dart';

/// Giorno / seduta di una scheda (es. "Giorno A - Petto").
@Entity()
class WorkoutDay {
  @Id()
  int id = 0;

  String label;
  String? notes;

  /// `ToMany` non garantisce l'ordine → ordinamento esplicito (§4).
  int sortOrder;

  final plan = ToOne<WorkoutPlan>();

  @Backlink('day')
  final blocks = ToMany<Block>();

  WorkoutDay({required this.label, this.notes, this.sortOrder = 0});
}
