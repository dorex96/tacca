import 'package:flutter/foundation.dart';

import '../../../core/errors/ai_exception.dart';
import '../ai_provider.dart';
import '../ai_selection.dart';
import '../plan_merge.dart';
import '../plan_normalizer.dart';
import '../plan_parser.dart';
import '../prompts.dart';

/// Chi ha scritto un turno della conversazione con il modello.
enum AiChatRole { user, assistant }

/// Un turno neutro rispetto al provider: del testo e, nella fase di
/// trascrizione, l'immagine da leggere. Ogni implementazione lo traduce nel
/// formato della propria API (`messages` OpenAI-compatible, blocchi di
/// contenuto Anthropic, …).
class AiChatTurn {
  final AiChatRole role;
  final String text;
  final AiImage? image;

  const AiChatTurn.user(this.text, {this.image}) : role = AiChatRole.user;

  const AiChatTurn.assistant(this.text)
    : role = AiChatRole.assistant,
      image = null;
}

/// Esito normalizzato di una singola chiamata al modello: il testo e il
/// segnale che la generazione si è fermata per budget esaurito.
class AiChatResult {
  final String content;

  /// La risposta è stata tagliata dal tetto di token di output (OpenRouter:
  /// `finish_reason: length`; Anthropic: `stop_reason: max_tokens`).
  final bool isTruncated;

  const AiChatResult(this.content, {this.isTruncated = false});
}

/// Venti cifre uguali di fila non esistono in una scheda: è il loop del
/// sampler sotto grammatica vincolata.
final _degenerateDigits = RegExp(r'(\d)\1{19,}');

/// La pipeline §6.2 condivisa da tutti i provider basati su chat.
///
/// Qui sta tutto ciò che non dipende dal protocollo: le due fasi per pagina
/// (prima leggere, poi strutturare), il retry correttivo, il fallback
/// `freeText`, la fusione delle pagine e i controlli sulle risposte
/// degenerate. Alle sottoclassi resta il solo [sendChat]: tradurre i turni
/// nella richiesta della loro API, mandarla e riportare testo e troncamento.
///
/// La key viene letta dalle impostazioni a ogni chiamata e finisce solo negli
/// header: mai nei log, mai nelle eccezioni (RNF-03).
abstract class ChatPlanProvider implements AiProvider {
  ChatPlanProvider({
    required AiSelectionResolver selection,
    PlanParser parser = const PlanParser(),
  }) : _selection = selection,
       _parser = parser;

  final AiSelectionResolver _selection;
  final PlanParser _parser;

  /// Quale provider è questo: serve a risolvere key e modello suoi, anche
  /// mentre nelle impostazioni è selezionato un altro.
  AiProviderId get id;

  /// Manda una richiesta al modello e riporta il testo della risposta.
  ///
  /// [structured] chiede lo structured output nativo del provider; se il
  /// modello lo rifiuta a runtime (rischio S-02) l'implementazione ritenta
  /// senza, e il JSON viene poi estratto dal testo dal [PlanParser].
  @protected
  Future<AiChatResult> sendChat({
    required AiSelection selection,
    required String system,
    required List<AiChatTurn> turns,
    required bool structured,
  });

  /// La selezione (provider, modello, key) di *questo* provider, con la key
  /// obbligatoria: senza, la chiamata non parte.
  @protected
  Future<AiSelection> requireSelection() async {
    final selection = await _selection.resolveFor(id);
    selection.requireApiKey();
    return selection;
  }

  @override
  Future<PlanExtraction> extractPlan({
    List<AiImage> images = const [],
    String? text,
    String? userHint,
  }) async {
    final selection = await requireSelection();

    if (images.isEmpty) {
      return _structure(selection, sourceText: text ?? '', userHint: userHint);
    }

    // Una richiesta per pagina, e due fasi per pagina: prima leggere, poi
    // strutturare. Una sola chiamata su più foto costringe il modello a
    // produrre in un colpo il JSON dell'intera scheda, ed è lì che le schede
    // lunghe si accorciano. Le parti si fondono dopo.
    final pageCount = images.length > 1 ? images.length : null;
    final parts = <PlanExtraction>[];
    for (var i = 0; i < images.length; i++) {
      final transcript = await _transcribe(
        selection,
        image: images[i],
        pageIndex: pageCount == null ? null : i + 1,
        pageCount: pageCount,
      );
      // Il testo incollato appartiene alla scheda intera: va unito a una
      // pagina sola, altrimenti ogni pagina ne ripeterebbe i giorni.
      final source = (i == 0 && text != null && text.trim().isNotEmpty)
          ? '$transcript\n\n${text.trim()}'
          : transcript;
      parts.add(
        await _structure(
          selection,
          sourceText: source,
          userHint: userHint,
          pageIndex: pageCount == null ? null : i + 1,
          pageCount: pageCount,
        ),
      );
    }

    if (parts.length == 1) return parts.single;
    // La fusione riaccosta blocchi che venivano da pagine diverse (un giorno
    // che prosegue sulla pagina dopo): la forma va rinormalizzata dopo,
    // altrimenti il taglio della pagina resta visibile come blocco a parte.
    return PlanExtraction(
      plan: normalizePlanDto(
        mergePlanDtos([for (final part in parts) part.plan]),
      ),
      usedFallback: parts.any((part) => part.usedFallback),
      rawResponse: [for (final part in parts) part.rawResponse].join('\n\n'),
    );
  }

  /// Fase 1: l'immagine diventa testo, senza structured output.
  ///
  /// Senza la grammatica dello schema addosso il modello si limita a copiare,
  /// che è il compito in cui è affidabile.
  Future<String> _transcribe(
    AiSelection selection, {
    required AiImage image,
    int? pageIndex,
    int? pageCount,
  }) async {
    final result = await sendChat(
      selection: selection,
      system: transcriptionSystemPrompt,
      structured: false,
      turns: [
        AiChatTurn.user(
          transcriptionUserText(pageIndex: pageIndex, pageCount: pageCount),
          image: image,
        ),
      ],
    );
    _guardTruncation(result, incomplete: 'La trascrizione della foto');
    return result.content;
  }

  /// Fase 2: dal testo al JSON, pipeline §6.2 con retry e fallback.
  ///
  /// Se la strutturazione fallisce due volte il blocco `freeText` conserva la
  /// trascrizione, non la risposta malformata: è il contenuto che serve
  /// davvero all'utente in editor (RNF-05).
  Future<PlanExtraction> _structure(
    AiSelection selection, {
    required String sourceText,
    String? userHint,
    int? pageIndex,
    int? pageCount,
  }) async {
    final structured = selection.model.supportsJsonSchema;
    final turns = <AiChatTurn>[
      AiChatTurn.user(
        extractionUserText(
          text: sourceText,
          userHint: userHint,
          pageIndex: pageIndex,
          pageCount: pageCount,
        ),
      ),
    ];

    // Pipeline §6.2: prima chiamata → parse; errore di parsing → 1 retry con
    // messaggio correttivo; secondo fallimento → fallback freeText (RNF-05).
    final first = await sendChat(
      selection: selection,
      system: extractionSystemPrompt,
      turns: turns,
      structured: structured,
    );
    _guardResponse(first);
    try {
      return PlanExtraction(
        plan: _parser.parse(first.content),
        usedFallback: false,
        rawResponse: first.content,
      );
    } on PlanParseException catch (firstError) {
      turns
        ..add(AiChatTurn.assistant(first.content))
        ..add(AiChatTurn.user(retryUserText(firstError.message)));
      final retry = await sendChat(
        selection: selection,
        system: extractionSystemPrompt,
        turns: turns,
        structured: structured,
      );
      _guardResponse(retry);
      try {
        return PlanExtraction(
          plan: _parser.parse(retry.content),
          usedFallback: false,
          rawResponse: retry.content,
        );
      } on PlanParseException {
        return PlanExtraction(
          plan: _parser.fallback(sourceText),
          usedFallback: true,
          rawResponse: retry.content,
        );
      }
    }
  }

  void _guardResponse(AiChatResult result) {
    _guardTruncation(result, incomplete: 'La scheda');
    _guardDegenerate(result);
  }

  /// Una risposta troncata non va né riparsata né ritentata: il JSON
  /// incompleto fallisce il parse e il retry correttivo spinge il modello a
  /// rispondere con una scheda *più corta ma valida*, perdendo silenziosamente
  /// giorni ed esercizi. Meglio fermarsi e dirlo.
  void _guardTruncation(AiChatResult result, {required String incomplete}) {
    if (!result.isTruncated) return;
    throw AiResponseException(
      '$incomplete è stata troncata: supera il budget di output del modello. '
      'Riprova con una foto alla volta, o alza "maxOutputTokens" per il '
      'modello selezionato.',
    );
  }

  /// Sotto structured output capita che il modello si incastri ripetendo una
  /// cifra dentro un intero ("sets": 44444…): il JSON resta sintatticamente
  /// plausibile ma il numero non entra in un `int`, il parse fallisce e il
  /// retry ripiega su una scheda più corta. Riconosciuto qui, prima del retry.
  void _guardDegenerate(AiChatResult result) {
    if (!_degenerateDigits.hasMatch(result.content)) return;
    throw const AiResponseException(
      'Il modello ha prodotto una risposta anomala e la scheda risulterebbe '
      'incompleta. Riprova: se capita di nuovo, cambia modello nelle '
      'impostazioni AI.',
    );
  }

  /// Diagnostica di sviluppo: senza il motivo di terminazione e il conteggio
  /// token una scheda che arriva amputata è indistinguibile da una che il
  /// modello ha semplicemente letto male. Mai la API key, solo la risposta.
  @protected
  void logResponse({
    required String content,
    String? stopReason,
    Object? usage,
  }) {
    if (!kDebugMode) return;
    debugPrint(
      '[AI] ${id.value} stop=$stopReason usage=$usage '
      'chars=${content.length}',
    );
    debugPrint('[AI] risposta grezza:\n$content');
  }
}
