import 'dart:io';

import 'package:app_palestra/data/db/object_box.dart';
import 'package:app_palestra/data/entities/block.dart';
import 'package:app_palestra/data/entities/exercise.dart';
import 'package:app_palestra/data/entities/workout_day.dart';
import 'package:app_palestra/data/entities/workout_plan.dart';
import 'package:app_palestra/objectbox.g.dart';
import 'package:flutter_test/flutter_test.dart';

import 'objectbox_test_support.dart';

// Verifica che "ObjectBox è inizializzato": apertura di uno Store reale su
// directory temporanea e round-trip di una scheda con relazioni annidate.
void main() {
  final skip = objectBoxNativeLibSkipReason();

  group('ObjectBox', () {
    late Directory tempDir;
    late ObjectBox obx;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('obx-palestra-test-');
      final store = Store(getObjectBoxModel(), directory: tempDir.path);
      obx = ObjectBox.fromStore(store);
    });

    tearDown(() {
      obx.close();
      tempDir.deleteSync(recursive: true);
    });

    test('round-trip: scheda con giorno, blocco ed esercizio', () {
      final plan = WorkoutPlan(
        name: 'Push / Pull / Legs',
        createdAt: DateTime(2026, 1, 1),
        updatedAt: DateTime(2026, 1, 1),
      );
      final day = WorkoutDay(label: 'Giorno A - Spinta', sortOrder: 0);
      final block = Block.ofType(BlockType.standard, sortOrder: 0);
      block.exercises.add(Exercise(name: 'Panca piana', sets: 4, reps: '8-12'));
      day.blocks.add(block);
      plan.days.add(day);

      final id = obx.planBox.put(plan);

      final loaded = obx.planBox.get(id)!;
      expect(loaded.name, 'Push / Pull / Legs');
      expect(loaded.days.length, 1);

      final loadedDay = loaded.days.single;
      expect(loadedDay.label, 'Giorno A - Spinta');
      expect(loadedDay.blocks.single.type, BlockType.standard);
      expect(loadedDay.blocks.single.exercises.single.name, 'Panca piana');
      expect(loadedDay.blocks.single.exercises.single.reps, '8-12');
    });
  }, skip: skip);
}
