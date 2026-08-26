import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Configurazione AI dell'utente (RF-08): provider scelto e, per ciascun
/// provider, API key e modello.
///
/// Key e modello sono per provider, non globali: chi ha configurato
/// OpenRouter e prova Anthropic non deve reinserire nulla tornando indietro.
/// Il repository non conosce i provider — riceve il loro id come stringa e lo
/// usa per comporre le chiavi di storage — così `data/` resta indipendente da
/// `services/ai/`.
///
/// Le key vivono esclusivamente nel secure storage nativo (Keychain / Android
/// Keystore), mai in log né negli export (RNF-03). Anche provider e modello
/// sono salvati qui: sono singole stringhe e non giustificano un secondo
/// meccanismo di persistenza.
abstract interface class SettingsRepository {
  /// Id del provider AI scelto; `null` se l'utente non ha mai scelto (si usa
  /// il default del catalogo).
  Future<String?> getAiProviderId();

  Future<void> setAiProviderId(String? providerId);

  Future<String?> getApiKey(String providerId);

  /// `null` o stringa vuota cancellano la key salvata.
  Future<void> setApiKey(String providerId, String? key);

  /// Id del modello scelto per [providerId]; `null` se l'utente non ha mai
  /// scelto (si usa il default del provider nel catalogo).
  Future<String?> getModelId(String providerId);

  Future<void> setModelId(String providerId, String? modelId);
}

class SecureSettingsRepository implements SettingsRepository {
  SecureSettingsRepository({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  static const _providerKey = 'ai.provider';

  /// Le chiavi per provider mantengono lo schema già in uso per OpenRouter
  /// (`ai.openrouter.apiKey`, `ai.openrouter.model`): chi aveva configurato
  /// l'app prima dell'arrivo di Anthropic ritrova la sua key al suo posto.
  static String _apiKeyKey(String providerId) => 'ai.$providerId.apiKey';

  static String _modelKey(String providerId) => 'ai.$providerId.model';

  @override
  Future<String?> getAiProviderId() => _read(_providerKey);

  @override
  Future<void> setAiProviderId(String? providerId) =>
      _write(_providerKey, providerId);

  @override
  Future<String?> getApiKey(String providerId) => _read(_apiKeyKey(providerId));

  @override
  Future<void> setApiKey(String providerId, String? key) =>
      _write(_apiKeyKey(providerId), key);

  @override
  Future<String?> getModelId(String providerId) => _read(_modelKey(providerId));

  @override
  Future<void> setModelId(String providerId, String? modelId) =>
      _write(_modelKey(providerId), modelId);

  Future<String?> _read(String key) async {
    final value = await _storage.read(key: key);
    return (value == null || value.isEmpty) ? null : value;
  }

  Future<void> _write(String key, String? value) async {
    if (value == null || value.trim().isEmpty) {
      await _storage.delete(key: key);
    } else {
      await _storage.write(key: key, value: value.trim());
    }
  }
}
