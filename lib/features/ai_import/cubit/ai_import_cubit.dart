import 'dart:typed_data';

import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/errors/ai_exception.dart';
import '../../../data/repositories/settings_repository.dart';
import '../../../services/ai/ai_provider.dart';
import '../../../services/ai/model_catalog.dart';
import '../../../services/ai/plan_parser.dart';
import '../../../services/images/image_input.dart';
import '../../../services/images/ocr_service.dart';
import '../../../services/images/plan_image_store.dart';
import 'ai_import_state.dart';

/// Import di una scheda via AI (RF-03): foto da fotocamera, immagini dalla
/// galleria e/o testo incollato → proposta strutturata da rivedere
/// nell'editor. Nessuna chiamata parte senza il tap esplicito su
/// "Digitalizza" (RNF-07); in caso di errore foto e testo restano nello
/// stato per riprovare (RNF-05).
class AiImportCubit extends Cubit<AiImportState> {
  AiImportCubit({
    required AiProvider provider,
    required ImageInput imageInput,
    required PlanImageStore imageStore,
    required SettingsRepository settings,
    required AiModelCatalog catalog,
    required OcrService ocr,
    PlanParser parser = const PlanParser(),
  }) : _provider = provider,
       _imageInput = imageInput,
       _imageStore = imageStore,
       _settings = settings,
       _catalog = catalog,
       _ocr = ocr,
       _parser = parser,
       super(const AiImportState()) {
    _checkConfiguration();
  }

  final AiProvider _provider;
  final ImageInput _imageInput;
  final PlanImageStore _imageStore;
  final SettingsRepository _settings;
  final AiModelCatalog _catalog;
  final OcrService _ocr;
  final PlanParser _parser;

  Future<void> _checkConfiguration() async {
    final apiKey = await _settings.getOpenRouterApiKey();
    emit(state.copyWith(configChecked: true, isConfigured: apiKey != null));
  }

  /// Da richiamare al ritorno dalle impostazioni.
  Future<void> refreshConfiguration() => _checkConfiguration();

  Future<void> addFromCamera() async {
    final bytes = await _imageInput.takePhoto();
    if (bytes == null) return;
    emit(
      state.copyWith(
        images: [...state.images, bytes],
        status: AiImportStatus.input,
        errorMessage: null,
      ),
    );
  }

  Future<void> addFromGallery() async {
    final picked = await _imageInput.pickFromGallery();
    if (picked.isEmpty) return;
    emit(
      state.copyWith(
        images: [...state.images, ...picked],
        status: AiImportStatus.input,
        errorMessage: null,
      ),
    );
  }

  void removeImage(int index) {
    if (index < 0 || index >= state.images.length) return;
    final images = [...state.images]..removeAt(index);
    emit(state.copyWith(images: images));
  }

  void updateText(String text) => emit(state.copyWith(text: text));

  void updateHint(String hint) => emit(state.copyWith(hint: hint));

  Future<void> submit() async {
    if (!state.hasInput || state.status == AiImportStatus.processing) return;

    emit(state.copyWith(status: AiImportStatus.processing, errorMessage: null));
    try {
      var images = state.images;
      var text = _blankToNull(state.text);
      var usedOcr = false;

      if (images.isNotEmpty) {
        final modelId =
            await _settings.getOpenRouterModelId() ?? _catalog.defaultModelId;
        final model = _catalog.byId(modelId);
        if (model != null && !model.supportsVision) {
          // Il modello non accetta immagini: le leggiamo noi via OCR
          // on-device e mandiamo solo testo, invece di bloccare l'import.
          final ocrText = await _recognizeText(images);
          if (ocrText.isEmpty) {
            emit(
              state.copyWith(
                status: AiImportStatus.failure,
                errorMessage:
                    'Il modello selezionato non supporta le immagini e '
                    'l\'OCR non ha trovato testo leggibile nelle foto: '
                    'scegli un modello con supporto immagini nelle '
                    'impostazioni, o riprova con foto più nitide.',
              ),
            );
            return;
          }
          usedOcr = true;
          text = [ocrText, if (text != null) text].join('\n\n');
          images = const [];
        }
      }

      // Compressione prima dell'upload (§6.4); gli originali restano a piena
      // risoluzione su disco, allegati alla scheda (RF-03).
      final compressed = <AiImage>[
        for (final bytes in images)
          AiImage(await _imageStore.compressForUpload(bytes)),
      ];
      final extraction = await _provider.extractPlan(
        images: compressed,
        text: text,
        userHint: _blankToNull(state.hint),
      );

      final imagePaths = <String>[
        for (final bytes in state.images) await _imageStore.saveOriginal(bytes),
      ];
      final draft = _parser.toEntity(extraction.plan, imagePaths: imagePaths);
      if (draft.name.trim().isEmpty) draft.name = 'Scheda importata';

      emit(
        state.copyWith(
          status: AiImportStatus.review,
          draft: draft,
          usedFallback: extraction.usedFallback,
          usedOcr: usedOcr,
        ),
      );
    } on AiConfigurationException {
      emit(state.copyWith(status: AiImportStatus.input, isConfigured: false));
    } on AiException catch (e) {
      emit(
        state.copyWith(status: AiImportStatus.failure, errorMessage: e.message),
      );
    } catch (e) {
      emit(
        state.copyWith(
          status: AiImportStatus.failure,
          errorMessage: e.toString(),
        ),
      );
    }
  }

  void dismissError() {
    emit(state.copyWith(status: AiImportStatus.input, errorMessage: null));
  }

  String? _blankToNull(String value) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  /// OCR pagina per pagina: un'immagine illeggibile non deve far fallire le
  /// altre, quindi un errore locale diventa pagina vuota invece di
  /// interrompere l'import (RNF-05).
  Future<String> _recognizeText(List<Uint8List> images) async {
    final pageCount = images.length > 1 ? images.length : null;
    final parts = <String>[];
    for (var i = 0; i < images.length; i++) {
      String recognized;
      try {
        recognized = await _ocr.recognizeText(images[i]);
      } catch (_) {
        recognized = '';
      }
      recognized = recognized.trim();
      if (recognized.isEmpty) continue;
      parts.add(
        pageCount == null
            ? recognized
            : '--- Pagina ${i + 1} di $pageCount ---\n$recognized',
      );
    }
    return parts.join('\n\n');
  }
}
