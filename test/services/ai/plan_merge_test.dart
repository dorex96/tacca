import 'package:tacca/services/ai/dto/plan_dto.dart';
import 'package:tacca/services/ai/plan_merge.dart';
import 'package:flutter_test/flutter_test.dart';

DayDto _day(String? label, List<String> exercises) => DayDto(
  label: label,
  blocks: [
    for (final name in exercises)
      BlockDto(
        type: 'standard',
        exercises: [ExerciseDto(name: name)],
      ),
  ],
);

void main() {
  group('mergePlanDtos', () {
    test('una sola parte torna invariata', () {
      final plan = PlanDto(
        name: 'Scheda',
        days: [
          _day('A', ['Panca']),
        ],
      );
      expect(mergePlanDtos([plan]), same(plan));
    });

    test(
      'giorni con la stessa etichetta si fondono nell\'ordine delle pagine',
      () {
        final merged = mergePlanDtos([
          PlanDto(
            name: 'Scheda',
            days: [
              _day('DAY 1 - Petto', ['Lat machine']),
            ],
          ),
          PlanDto(
            days: [
              _day('Day 1 – Petto', ['Pulley']),
            ],
          ),
        ]);

        expect(merged.days, hasLength(1));
        final names = [
          for (final block in merged.days.single.blocks)
            block.exercises.single.name,
        ];
        expect(names, ['Lat machine', 'Pulley']);
      },
    );

    test('giorni diversi restano distinti e in ordine', () {
      final merged = mergePlanDtos([
        PlanDto(
          days: [
            _day('Day 1', ['Panca']),
          ],
        ),
        PlanDto(
          days: [
            _day('Day 2', ['Squat']),
            _day('Day 3', ['Stacchi']),
          ],
        ),
      ]);

      expect(
        [for (final d in merged.days) d.label],
        ['Day 1', 'Day 2', 'Day 3'],
      );
    });

    test('name/description/notes prendono il primo valore non vuoto', () {
      final merged = mergePlanDtos([
        PlanDto(
          days: [
            _day('A', ['Panca']),
          ],
        ),
        const PlanDto(name: 'Scheda Dodo', notes: 'Bere acqua'),
      ]);

      expect(merged.name, 'Scheda Dodo');
      expect(merged.notes, 'Bere acqua');
    });

    test('lista vuota → scheda vuota (nessun crash)', () {
      expect(mergePlanDtos([]).days, isEmpty);
    });
  });
}
