import 'dart:typed_data';

import 'dto/plan_dto.dart';

/// Immagine pronta per l'invio al provider: già compressa (§6.4).
class AiImage {
  final Uint8List bytes;
  final String mimeType;

  const AiImage(this.bytes, {this.mimeType = 'image/jpeg'});
}

/// Esito di un'estrazione: la [PlanDto] proposta e, se il parsing è fallito
/// due volte, il segnale che la scheda è il fallback `freeText` (§6.2).
class PlanExtraction {
  final PlanDto plan;

  /// `true` se [plan] è il fallback con la risposta grezza in un blocco
  /// `freeText`: la UI lo segnala in revisione.
  final bool usedFallback;

  /// Ultima risposta testuale del modello (mai loggata con la key).
  final String rawResponse;

  const PlanExtraction({
    required this.plan,
    required this.usedFallback,
    required this.rawResponse,
  });
}

/// Contratto dei provider AI (§6.1). In v1 l'unica implementazione è
/// OpenRouter; l'interfaccia resta il punto di aggancio per Anthropic e
/// Gemini quando verranno aggiunti.
abstract interface class AiProvider {
  /// Estrae una scheda strutturata da immagini e/o testo. Nessuna chiamata
  /// avviene senza un'azione esplicita dell'utente (RNF-07).
  Future<PlanExtraction> extractPlan({
    List<AiImage> images = const [],
    String? text,
    String? userHint,
  });

  /// Verifica che la key salvata sia valida ("test connessione", RF-08).
  /// Completa senza errori se la key è accettata; altrimenti lancia le
  /// eccezioni tipizzate di `ai_exception.dart`.
  Future<void> testConnection();
}
