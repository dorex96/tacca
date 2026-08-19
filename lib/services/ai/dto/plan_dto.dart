import 'package:freezed_annotation/freezed_annotation.dart';

part 'plan_dto.freezed.dart';
part 'plan_dto.g.dart';

/// DTO della scheda proposta dall'AI, ricalca lo schema §5.3 dell'analisi
/// funzionale. Esiste solo al confine AI (ADR-01): la conversione in entity
/// avviene in un unico punto, `PlanParser.toEntity`.
///
/// I campi numerici e testuali passano da convertitori tolleranti
/// ([flexInt]/[flexString]): i modelli a volte restituiscono `"sets": "4"`
/// o `"reps": 8`, e scartare l'intera risposta per questo violerebbe RNF-05.
@freezed
sealed class PlanDto with _$PlanDto {
  const factory PlanDto({
    @JsonKey(fromJson: flexString) String? name,
    @JsonKey(fromJson: flexString) String? description,
    @JsonKey(fromJson: flexString) String? notes,
    @Default(<DayDto>[]) List<DayDto> days,
  }) = _PlanDto;

  factory PlanDto.fromJson(Map<String, dynamic> json) =>
      _$PlanDtoFromJson(json);
}

@freezed
sealed class DayDto with _$DayDto {
  const factory DayDto({
    @JsonKey(fromJson: flexString) String? label,
    @JsonKey(fromJson: flexString) String? notes,
    @Default(<BlockDto>[]) List<BlockDto> blocks,
  }) = _DayDto;

  factory DayDto.fromJson(Map<String, dynamic> json) => _$DayDtoFromJson(json);
}

@freezed
sealed class BlockDto with _$BlockDto {
  const factory BlockDto({
    @JsonKey(fromJson: flexString) String? type,
    @JsonKey(fromJson: flexString) String? notes,
    @JsonKey(fromJson: flexInt) int? intervalSeconds,
    @JsonKey(fromJson: flexInt) int? totalMinutes,
    @JsonKey(fromJson: flexInt) int? durationSeconds,
    @JsonKey(fromJson: flexInt) int? workSeconds,
    @JsonKey(fromJson: flexInt) int? restSeconds,
    @JsonKey(fromJson: flexInt) int? rounds,
    @JsonKey(fromJson: flexInt) int? restBetweenRoundsSeconds,
    @JsonKey(fromJson: flexInt) int? timeCapSeconds,
    @JsonKey(fromJson: flexString) String? content,
    @Default(<ExerciseDto>[]) List<ExerciseDto> exercises,
  }) = _BlockDto;

  factory BlockDto.fromJson(Map<String, dynamic> json) =>
      _$BlockDtoFromJson(json);
}

@freezed
sealed class ExerciseDto with _$ExerciseDto {
  const factory ExerciseDto({
    @JsonKey(fromJson: flexString) String? name,
    @JsonKey(fromJson: flexInt) int? sets,
    @JsonKey(fromJson: flexString) String? reps,
    @JsonKey(fromJson: flexString) String? load,
    @JsonKey(fromJson: flexInt) int? restSeconds,
    @JsonKey(fromJson: flexInt) int? durationSeconds,
    @JsonKey(fromJson: flexString) String? notes,
  }) = _ExerciseDto;

  factory ExerciseDto.fromJson(Map<String, dynamic> json) =>
      _$ExerciseDtoFromJson(json);
}

/// `4`, `4.0`, `"4"` → 4; tutto il resto → null.
int? flexInt(Object? value) {
  if (value is int) return value;
  if (value is double) {
    final rounded = value.round();
    return rounded.toDouble() == value ? rounded : null;
  }
  if (value is String) return int.tryParse(value.trim());
  return null;
}

/// `"8-12"` → invariata, `8` → `"8"`; stringhe vuote → null.
String? flexString(Object? value) {
  if (value == null) return null;
  final text = value is String ? value : value.toString();
  return text.trim().isEmpty ? null : text;
}
