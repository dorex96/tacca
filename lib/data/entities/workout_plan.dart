import 'package:objectbox/objectbox.dart';

import 'workout_day.dart';

/// Scheda di allenamento: aggregato radice dell'archivio (RF-01).
///
/// È un semplice POJO Dart che funge anche da modello di dominio (ADR-01,
/// opzione C). L'accesso al [Box] avviene solo dai repository in `data/`.
@Entity()
class WorkoutPlan {
  @Id()
  int id = 0;

  String name;
  String? description;
  String? notes;

  @Property(type: PropertyType.date)
  DateTime createdAt;

  @Property(type: PropertyType.date)
  DateTime updatedAt;

  bool isArchived;

  /// Scheda "in uso": al più una attiva alla volta (vincolo applicato dai repository).
  bool isActive;

  /// Path relativi delle immagini originali salvate su disco (§4 nota "Immagini").
  List<String> imagePaths;

  /// I giorni sono ordinati per `sortOrder`: i repository restituiscono liste già ordinate.
  @Backlink('plan')
  final days = ToMany<WorkoutDay>();

  WorkoutPlan({
    required this.name,
    this.description,
    this.notes,
    required this.createdAt,
    required this.updatedAt,
    this.isArchived = false,
    this.isActive = false,
    this.imagePaths = const [],
  });
}
