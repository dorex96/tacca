import 'dart:convert';

import '../../core/errors/app_exception.dart';
import '../../data/entities/block.dart';
import '../../data/entities/exercise.dart';
import '../../data/entities/workout_day.dart';
import '../../data/entities/workout_plan.dart';
import 'dto/plan_dto.dart';
import 'plan_normalizer.dart';

/// Risposta AI non trasformabile in una [PlanDto] valida. Il messaggio è
/// pensato per essere rimandato al modello nel retry correttivo (§6.2).
class PlanParseException extends AppException {
  const PlanParseException(super.message, {super.cause});
}

/// Pipeline unica di parsing delle risposte AI (§6.2): estrazione del JSON,
/// decodifica in [PlanDto], validazione semantica, normalizzazione della forma
/// e mapping DTO → entity. Tutti i provider passano da qui.
class PlanParser {
  const PlanParser();

  /// Estrae, decodifica, valida e normalizza. Lancia [PlanParseException] con
  /// la lista dei problemi trovati.
  PlanDto parse(String raw) {
    final jsonText = _extractJsonPayload(raw);
    if (jsonText == null) {
      throw const PlanParseException(
        'Nessun oggetto JSON trovato nella risposta.',
      );
    }

    final Object? decoded;
    try {
      decoded = jsonDecode(jsonText);
    } on FormatException catch (e) {
      throw PlanParseException('JSON malformato: ${e.message}', cause: e);
    }
    if (decoded is! Map<String, dynamic>) {
      throw const PlanParseException(
        'La risposta JSON non è un oggetto scheda.',
      );
    }

    final PlanDto dto;
    try {
      dto = PlanDto.fromJson(decoded);
    } catch (e) {
      throw PlanParseException(
        'JSON non conforme allo schema della scheda: $e',
        cause: e,
      );
    }

    // Validazione sulla risposta così com'è: i riferimenti nei messaggi
    // d'errore ("giorno 2, blocco 3") devono corrispondere a ciò che il
    // modello ha scritto, perché è a lui che tornano nel retry.
    final issues = validate(dto);
    if (issues.isNotEmpty) {
      throw PlanParseException('Scheda non valida: ${issues.join('; ')}.');
    }
    return normalizePlanDto(dto);
  }

  /// Validazione semantica (§6.2 punto 3): tipi di blocco noti, parametri
  /// coerenti col tipo, almeno un giorno. Ritorna i problemi trovati.
  List<String> validate(PlanDto dto) {
    final issues = <String>[];
    if (dto.name == null || dto.name!.trim().isEmpty) {
      issues.add('campo "name" mancante o vuoto');
    }
    if (dto.days.isEmpty) {
      issues.add('la scheda deve avere almeno un giorno in "days"');
    }
    for (var d = 0; d < dto.days.length; d++) {
      final day = dto.days[d];
      final dayRef = 'giorno ${d + 1}';
      for (var b = 0; b < day.blocks.length; b++) {
        final block = day.blocks[b];
        final blockRef = '$dayRef, blocco ${b + 1}';
        final typeName = block.type;
        final type = typeName == null
            ? null
            : BlockType.values.asNameMap()[typeName];
        if (type == null) {
          issues.add('$blockRef: tipo di blocco sconosciuto "$typeName"');
          continue;
        }
        switch (type) {
          case BlockType.emom:
            if ((block.intervalSeconds ?? 0) <= 0) {
              issues.add('$blockRef: EMOM senza "intervalSeconds"');
            }
            if ((block.totalMinutes ?? 0) <= 0) {
              issues.add('$blockRef: EMOM senza "totalMinutes"');
            }
          case BlockType.amrap:
            if ((block.durationSeconds ?? 0) <= 0) {
              issues.add('$blockRef: AMRAP senza "durationSeconds"');
            }
          case BlockType.tabata:
            if ((block.workSeconds ?? 0) <= 0 ||
                (block.restSeconds ?? 0) <= 0) {
              issues.add('$blockRef: Tabata senza "workSeconds"/"restSeconds"');
            }
          case BlockType.freeText:
            if (block.content == null || block.content!.trim().isEmpty) {
              issues.add('$blockRef: blocco freeText senza "content"');
            }
          case BlockType.standard:
          case BlockType.superset:
          case BlockType.circuit:
          case BlockType.forTime:
            break;
        }
        for (var e = 0; e < block.exercises.length; e++) {
          final exercise = block.exercises[e];
          if (exercise.name == null || exercise.name!.trim().isEmpty) {
            issues.add('$blockRef, esercizio ${e + 1}: "name" mancante');
          }
        }
      }
    }
    return issues;
  }

  /// Fallback dopo il secondo fallimento (§6.2 punto 5, RNF-05): il testo
  /// grezzo della risposta diventa un blocco `freeText` editabile.
  PlanDto fallback(String raw, {String? planName}) {
    return PlanDto(
      name: planName == null || planName.trim().isEmpty
          ? 'Scheda importata'
          : planName.trim(),
      days: [
        DayDto(
          label: 'Giorno unico',
          blocks: [BlockDto(type: BlockType.freeText.name, content: raw)],
        ),
      ],
    );
  }

  /// Unico punto di conversione DTO → entity (§6.2 punto 6). Assegna i
  /// `sortOrder` e copia solo i parametri pertinenti al tipo di blocco.
  WorkoutPlan toEntity(PlanDto dto, {List<String> imagePaths = const []}) {
    final now = DateTime.now();
    final plan = WorkoutPlan(
      name: dto.name?.trim() ?? '',
      description: dto.description,
      notes: dto.notes,
      createdAt: now,
      updatedAt: now,
      imagePaths: List.of(imagePaths),
    );

    for (var d = 0; d < dto.days.length; d++) {
      final dayDto = dto.days[d];
      final day = WorkoutDay(
        label: dayDto.label?.trim().isNotEmpty ?? false
            ? dayDto.label!.trim()
            : 'Giorno ${d + 1}',
        notes: dayDto.notes,
        sortOrder: d,
      );
      for (var b = 0; b < dayDto.blocks.length; b++) {
        final blockDto = dayDto.blocks[b];
        final type =
            BlockType.values.asNameMap()[blockDto.type] ?? BlockType.freeText;
        final block = Block.ofType(type, sortOrder: b, notes: blockDto.notes);
        switch (type) {
          case BlockType.standard:
            break;
          case BlockType.superset:
            // Anche il superset ha un recupero fra un giro e l'altro: era il
            // dato che nella scheda sta in fondo alla riga ("... x4 1'").
            block
              ..rounds = blockDto.rounds
              ..restBetweenRoundsSeconds = blockDto.restBetweenRoundsSeconds;
          case BlockType.circuit:
            block
              ..rounds = blockDto.rounds
              ..restBetweenRoundsSeconds = blockDto.restBetweenRoundsSeconds;
          case BlockType.emom:
            block
              ..intervalSeconds = blockDto.intervalSeconds
              ..totalMinutes = blockDto.totalMinutes;
          case BlockType.amrap:
            block.durationSeconds = blockDto.durationSeconds;
          case BlockType.tabata:
            block
              ..workSeconds = blockDto.workSeconds
              ..restSeconds = blockDto.restSeconds
              ..rounds = blockDto.rounds;
          case BlockType.forTime:
            block.timeCapSeconds = blockDto.timeCapSeconds;
          case BlockType.freeText:
            block.freeTextContent = blockDto.content ?? '';
        }
        for (var e = 0; e < blockDto.exercises.length; e++) {
          final exerciseDto = blockDto.exercises[e];
          block.exercises.add(
            Exercise(
              name: exerciseDto.name?.trim() ?? '',
              sets: exerciseDto.sets,
              reps: exerciseDto.reps,
              load: exerciseDto.load,
              restSeconds: exerciseDto.restSeconds,
              durationSeconds: exerciseDto.durationSeconds,
              notes: exerciseDto.notes,
              sortOrder: e,
            ),
          );
        }
        day.blocks.add(block);
      }
      plan.days.add(day);
    }
    return plan;
  }

  /// Isola l'oggetto JSON dalla risposta: blocco ```json recintato, oppure
  /// il primo oggetto `{...}` bilanciato nel testo (fallback prompt-based).
  String? _extractJsonPayload(String raw) {
    final fence = RegExp(
      r'```(?:json)?\s*(\{[\s\S]*?\})\s*```',
      multiLine: true,
    ).firstMatch(raw);
    if (fence != null) return fence.group(1);

    final start = raw.indexOf('{');
    if (start < 0) return null;
    var depth = 0;
    var inString = false;
    var escaped = false;
    for (var i = start; i < raw.length; i++) {
      final char = raw[i];
      if (escaped) {
        escaped = false;
        continue;
      }
      if (char == r'\') {
        escaped = true;
        continue;
      }
      if (char == '"') inString = !inString;
      if (inString) continue;
      if (char == '{') depth++;
      if (char == '}') {
        depth--;
        if (depth == 0) return raw.substring(start, i + 1);
      }
    }
    return null;
  }
}
