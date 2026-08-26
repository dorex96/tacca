import 'dart:typed_data';

import 'package:tacca/core/errors/ai_exception.dart';
import 'package:tacca/data/entities/block.dart';
import 'package:tacca/features/ai_import/cubit/ai_import_cubit.dart';
import 'package:tacca/features/ai_import/cubit/ai_import_state.dart';
import 'package:tacca/services/ai/ai_provider.dart';
import 'package:tacca/services/ai/dto/plan_dto.dart';
import 'package:tacca/services/ai/ai_selection.dart';
import 'package:tacca/services/ai/model_catalog.dart';
import 'package:tacca/services/images/image_input.dart';
import 'package:tacca/services/images/ocr_service.dart';
import 'package:tacca/services/images/plan_image_store.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/fakes.dart';

class _FakeAiProvider implements AiProvider {
  PlanExtraction? result;
  Object? error;
  List<AiImage>? lastImages;
  String? lastText;
  String? lastHint;
  int calls = 0;

  @override
  Future<PlanExtraction> extractPlan({
    List<AiImage> images = const [],
    String? text,
    String? userHint,
  }) async {
    calls++;
    lastImages = images;
    lastText = text;
    lastHint = userHint;
    final pending = error;
    if (pending != null) throw pending;
    return result!;
  }

  @override
  Future<void> testConnection() async {}
}

class _FakeOcrService implements OcrService {
  final texts = <Uint8List, String>{};
  final failing = <Uint8List>{};
  final calls = <Uint8List>[];

  @override
  Future<String> recognizeText(Uint8List bytes) async {
    calls.add(bytes);
    if (failing.contains(bytes)) throw Exception('OCR fallito');
    return texts[bytes] ?? '';
  }
}

class _FakeImageInput implements ImageInput {
  Uint8List? cameraResult;
  List<Uint8List> galleryResult = const [];

  @override
  Future<Uint8List?> takePhoto() async => cameraResult;

  @override
  Future<List<Uint8List>> pickFromGallery() async => galleryResult;
}

/// Niente plugin nei test: la "compressione" è un marker e il salvataggio
/// registra i path senza toccare il disco.
class _FakeImageStore extends PlanImageStore {
  final saved = <Uint8List>[];

  @override
  Future<Uint8List> compressForUpload(Uint8List bytes) async =>
      Uint8List.fromList([...bytes, 99]);

  @override
  Future<String> saveOriginal(Uint8List bytes) async {
    saved.add(bytes);
    return 'plan_images/img_${saved.length}.jpg';
  }
}

const _catalog = AiModelCatalog(
  defaultProviderId: AiProviderId.openRouter,
  providers: [
    AiProviderOption(
      id: AiProviderId.openRouter,
      label: 'OpenRouter',
      defaultModelId: 'vision/model',
      models: [
        AiModelOption(
          id: 'vision/model',
          label: 'Vision',
          supportsVision: true,
        ),
        AiModelOption(id: 'text/only', label: 'Solo testo'),
      ],
    ),
  ],
);

PlanExtraction _extraction({
  String? name = 'Scheda AI',
  bool fallback = false,
}) {
  return PlanExtraction(
    plan: PlanDto(
      name: name,
      days: const [
        DayDto(
          label: 'Giorno A',
          blocks: [
            BlockDto(
              type: 'standard',
              exercises: [ExerciseDto(name: 'Panca', sets: 4, reps: '8')],
            ),
          ],
        ),
      ],
    ),
    usedFallback: fallback,
    rawResponse: 'raw',
  );
}

void main() {
  late _FakeAiProvider provider;
  late _FakeImageInput imageInput;
  late _FakeImageStore imageStore;
  late _FakeOcrService ocr;
  late FakeSettingsRepository settings;

  setUp(() {
    provider = _FakeAiProvider();
    imageInput = _FakeImageInput();
    imageStore = _FakeImageStore();
    ocr = _FakeOcrService();
    settings = FakeSettingsRepository(apiKey: 'sk-or-test');
  });

  AiImportCubit buildCubit() => AiImportCubit(
    provider: provider,
    imageInput: imageInput,
    imageStore: imageStore,
    selection: AiSelectionResolver(settings: settings, catalog: _catalog),
    ocr: ocr,
  );

  test(
    'senza key: isConfigured false (funzioni AI spiegate, non nascoste)',
    () async {
      settings.apiKey = null;
      final cubit = buildCubit();
      await pumpEventQueue();

      expect(cubit.state.configChecked, isTrue);
      expect(cubit.state.isConfigured, isFalse);
    },
  );

  test(
    'foto e galleria si accumulano; removeImage toglie la voce giusta',
    () async {
      final cubit = buildCubit();
      imageInput.cameraResult = Uint8List.fromList([1]);
      await cubit.addFromCamera();
      imageInput.galleryResult = [
        Uint8List.fromList([2]),
        Uint8List.fromList([3]),
      ];
      await cubit.addFromGallery();

      expect(cubit.state.images, hasLength(3));

      cubit.removeImage(1);
      expect(cubit.state.images.map((b) => b.first), [1, 3]);
    },
  );

  test(
    'submit con solo testo: il provider riceve il testo, niente immagini',
    () async {
      provider.result = _extraction();
      final cubit = buildCubit();
      await pumpEventQueue();

      cubit.updateText('Panca 4x8, rec 2\'');
      cubit.updateHint('è una scheda push');
      await cubit.submit();

      expect(provider.lastImages, isEmpty);
      expect(provider.lastText, 'Panca 4x8, rec 2\'');
      expect(provider.lastHint, 'è una scheda push');
      expect(cubit.state.status, AiImportStatus.review);
      expect(cubit.state.draft!.name, 'Scheda AI');
      expect(
        cubit.state.draft!.days.single.blocks.single.type,
        BlockType.standard,
      );
    },
  );

  test('submit con immagini: comprime per l\'upload, salva gli originali e li '
      'allega alla bozza (RF-03)', () async {
    provider.result = _extraction();
    final cubit = buildCubit();
    imageInput.cameraResult = Uint8List.fromList([1, 2]);
    await cubit.addFromCamera();

    await cubit.submit();

    // Al provider arriva la versione compressa (marker 99 in coda)...
    expect(provider.lastImages!.single.bytes.last, 99);
    // ...su disco finisce l'originale, e il path relativo va nella bozza.
    expect(imageStore.saved.single, [1, 2]);
    expect(cubit.state.draft!.imagePaths, ['plan_images/img_1.jpg']);
  });

  test('una proposta senza nome riceve un nome di default', () async {
    provider.result = _extraction(name: null);
    final cubit = buildCubit();
    await pumpEventQueue();

    cubit.updateText('qualcosa');
    await cubit.submit();

    expect(cubit.state.draft!.name, 'Scheda importata');
  });

  test('il flag usedFallback della pipeline arriva alla UI (RNF-05)', () async {
    provider.result = _extraction(fallback: true);
    final cubit = buildCubit();
    await pumpEventQueue();

    cubit.updateText('testo');
    await cubit.submit();

    expect(cubit.state.status, AiImportStatus.review);
    expect(cubit.state.usedFallback, isTrue);
  });

  test('errore AI: failure con messaggio, input preservato (RNF-05)', () async {
    provider.error = const AiQuotaException('Quota esaurita.');
    final cubit = buildCubit();
    imageInput.cameraResult = Uint8List.fromList([7]);
    await cubit.addFromCamera();
    cubit.updateText('testo prezioso');

    await cubit.submit();

    expect(cubit.state.status, AiImportStatus.failure);
    expect(cubit.state.errorMessage, 'Quota esaurita.');
    expect(cubit.state.images, hasLength(1));
    expect(cubit.state.text, 'testo prezioso');

    // dismissError torna all'input senza perdere nulla.
    cubit.dismissError();
    expect(cubit.state.status, AiImportStatus.input);
    expect(cubit.state.images, hasLength(1));
  });

  test('immagini con modello senza vision: OCR converte in testo, niente '
      'immagini al provider (RF-03)', () async {
    settings.modelId = 'text/only';
    provider.result = _extraction();
    final cubit = buildCubit();
    final photo = Uint8List.fromList([7]);
    ocr.texts[photo] = 'Panca 4x8';
    imageInput.cameraResult = photo;
    await cubit.addFromCamera();

    await cubit.submit();

    expect(ocr.calls, [photo]);
    expect(provider.lastImages, isEmpty);
    expect(provider.lastText, 'Panca 4x8');
    expect(cubit.state.status, AiImportStatus.review);
    expect(cubit.state.usedOcr, isTrue);
    // L'originale resta comunque allegato alla bozza.
    expect(cubit.state.draft!.imagePaths, ['plan_images/img_1.jpg']);
  });

  test('immagini con modello senza vision, testo incollato in aggiunta: il '
      'testo OCR e quello utente arrivano entrambi al provider', () async {
    settings.modelId = 'text/only';
    provider.result = _extraction();
    final cubit = buildCubit();
    final photo = Uint8List.fromList([7]);
    ocr.texts[photo] = 'Panca 4x8';
    imageInput.cameraResult = photo;
    await cubit.addFromCamera();
    cubit.updateText('nota utente');

    await cubit.submit();

    expect(provider.lastText, 'Panca 4x8\n\nnota utente');
  });

  test('modello senza vision, OCR senza testo leggibile: failure, provider mai '
      'chiamato', () async {
    settings.modelId = 'text/only';
    final cubit = buildCubit();
    imageInput.cameraResult = Uint8List.fromList([7]);
    await cubit.addFromCamera();

    await cubit.submit();

    expect(cubit.state.status, AiImportStatus.failure);
    expect(provider.calls, 0);
  });

  test('modello senza vision, OCR che fallisce su una foto: le altre pagine '
      'restano nel testo inviato', () async {
    settings.modelId = 'text/only';
    provider.result = _extraction();
    final cubit = buildCubit();
    final bad = Uint8List.fromList([1]);
    final good = Uint8List.fromList([2]);
    ocr.failing.add(bad);
    ocr.texts[good] = 'Squat 4x8';
    imageInput.cameraResult = bad;
    await cubit.addFromCamera();
    imageInput.galleryResult = [good];
    await cubit.addFromGallery();

    await cubit.submit();

    expect(provider.lastText, contains('Squat 4x8'));
    expect(cubit.state.status, AiImportStatus.review);
  });

  test('senza input il submit non parte', () async {
    final cubit = buildCubit();
    await pumpEventQueue();

    await cubit.submit();

    expect(provider.calls, 0);
    expect(cubit.state.status, AiImportStatus.input);
  });

  test('AiConfigurationException riporta allo stato non configurato', () async {
    provider.error = const AiConfigurationException('Nessuna key.');
    final cubit = buildCubit();
    await pumpEventQueue();

    cubit.updateText('testo');
    await cubit.submit();

    expect(cubit.state.status, AiImportStatus.input);
    expect(cubit.state.isConfigured, isFalse);
  });
}
