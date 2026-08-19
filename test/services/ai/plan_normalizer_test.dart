import 'package:app_palestra/services/ai/dto/plan_dto.dart';
import 'package:app_palestra/services/ai/plan_normalizer.dart';
import 'package:flutter_test/flutter_test.dart';

BlockDto _standard(List<String> names, {String? notes}) => BlockDto(
  type: 'standard',
  notes: notes,
  exercises: [for (final name in names) ExerciseDto(name: name)],
);

List<String?> _names(BlockDto block) => [
  for (final exercise in block.exercises) exercise.name,
];

void main() {
  group('normalizeBlocks', () {
    test('blocchi standard consecutivi diventano un blocco solo', () {
      final blocks = normalizeBlocks([
        _standard(['Panca piana']),
        _standard(['Croci ai cavi']),
        _standard(['Lat machine']),
        _standard(['Pulley']),
        _standard(['Crunch']),
      ]);

      expect(blocks, hasLength(1));
      expect(_names(blocks.single), [
        'Panca piana',
        'Croci ai cavi',
        'Lat machine',
        'Pulley',
        'Crunch',
      ]);
    });

    test('i parametri del blocco che assorbe restano i suoi', () {
      final blocks = normalizeBlocks([
        BlockDto(
          type: 'standard',
          exercises: [const ExerciseDto(name: 'Panca', sets: 4, reps: '8')],
        ),
        BlockDto(
          type: 'standard',
          exercises: [const ExerciseDto(name: 'Croci', sets: 3, reps: '12')],
        ),
      ]);

      final exercises = blocks.single.exercises;
      expect(exercises.map((e) => e.sets), [4, 3]);
      expect(exercises.map((e) => e.reps), ['8', '12']);
    });

    test('i blocchi di altro tipo non si fondono e spezzano la sequenza', () {
      final blocks = normalizeBlocks([
        _standard(['Panca']),
        _standard(['Croci']),
        const BlockDto(type: 'superset', rounds: 4),
        _standard(['Curl']),
        _standard(['French press']),
        const BlockDto(type: 'freeText', content: 'Defaticamento libero'),
      ]);

      expect(blocks.map((b) => b.type), [
        'standard',
        'superset',
        'standard',
        'freeText',
      ]);
      expect(_names(blocks[0]), ['Panca', 'Croci']);
      expect(_names(blocks[2]), ['Curl', 'French press']);
    });

    test('due superset consecutivi restano due blocchi distinti', () {
      final blocks = normalizeBlocks([
        BlockDto(
          type: 'superset',
          rounds: 4,
          exercises: [const ExerciseDto(name: 'Curl')],
        ),
        BlockDto(
          type: 'superset',
          rounds: 3,
          exercises: [const ExerciseDto(name: 'Dip')],
        ),
      ]);

      expect(blocks, hasLength(2));
    });

    test('una nota di gruppo apre un nuovo blocco e assorbe ciò che segue', () {
      final blocks = normalizeBlocks([
        _standard(['Tapis roulant', 'Mobilità'], notes: 'Riscaldamento'),
        _standard(['Panca']),
        _standard(['Croci', 'Lat machine'], notes: 'Parte centrale'),
        _standard(['Pulley']),
      ]);

      expect(blocks, hasLength(2));
      expect(blocks[0].notes, 'Riscaldamento');
      expect(_names(blocks[0]), ['Tapis roulant', 'Mobilità', 'Panca']);
      expect(blocks[1].notes, 'Parte centrale');
      expect(_names(blocks[1]), ['Croci', 'Lat machine', 'Pulley']);
    });

    test(
      'la nota di uno standard con un solo esercizio scende sull\'esercizio, '
      'e il blocco si fonde lo stesso',
      () {
        final blocks = normalizeBlocks([
          _standard(['Panca']),
          _standard(['Croci ai cavi'], notes: 'presa neutra'),
        ]);

        expect(blocks, hasLength(1));
        final exercises = blocks.single.exercises;
        expect(blocks.single.notes, isNull);
        expect(exercises[1].name, 'Croci ai cavi');
        expect(exercises[1].notes, 'presa neutra');
      },
    );

    test(
      'se l\'esercizio ha già una nota propria non si sovrascrive nulla',
      () {
        final blocks = normalizeBlocks([
          _standard(['Panca']),
          BlockDto(
            type: 'standard',
            notes: 'Superserie con il prossimo',
            exercises: [
              const ExerciseDto(name: 'Croci', notes: 'presa neutra'),
            ],
          ),
        ]);

        expect(blocks, hasLength(2));
        expect(blocks[1].notes, 'Superserie con il prossimo');
        expect(blocks[1].exercises.single.notes, 'presa neutra');
      },
    );

    test('un blocco standard vuoto sparisce dentro il precedente', () {
      final blocks = normalizeBlocks([
        _standard(['Panca']),
        _standard([]),
      ]);

      expect(blocks, hasLength(1));
      expect(_names(blocks.single), ['Panca']);
    });

    test('lista vuota e blocco singolo restano invariati', () {
      expect(normalizeBlocks([]), isEmpty);
      expect(
        normalizeBlocks([
          _standard(['Panca']),
        ]),
        hasLength(1),
      );
    });
  });

  group('normalizePlanDto', () {
    test('normalizza ogni giorno senza toccare l\'ordine né i metadati', () {
      final normalized = normalizePlanDto(
        PlanDto(
          name: 'Scheda',
          notes: 'Settimane 1-4',
          days: [
            DayDto(
              label: 'Giorno A',
              notes: 'Petto',
              blocks: [
                _standard(['Panca']),
                _standard(['Croci']),
              ],
            ),
            DayDto(
              label: 'Giorno B',
              blocks: [
                _standard(['Squat']),
                _standard(['Affondi']),
                _standard(['Leg curl']),
              ],
            ),
          ],
        ),
      );

      expect(normalized.name, 'Scheda');
      expect(normalized.notes, 'Settimane 1-4');
      expect(normalized.days.map((d) => d.label), ['Giorno A', 'Giorno B']);
      expect(normalized.days.first.notes, 'Petto');
      expect(_names(normalized.days[0].blocks.single), ['Panca', 'Croci']);
      expect(_names(normalized.days[1].blocks.single), [
        'Squat',
        'Affondi',
        'Leg curl',
      ]);
    });
  });
}
