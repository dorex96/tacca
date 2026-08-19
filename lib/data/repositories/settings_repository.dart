import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Configurazione AI dell'utente (RF-08): API key OpenRouter e modello scelto.
///
/// La key vive esclusivamente nel secure storage nativo (Keychain / Android
/// Keystore), mai in log né negli export (RNF-03). Anche il modello è salvato
/// qui: è una singola stringa e non giustifica un secondo meccanismo di
/// persistenza.
abstract interface class SettingsRepository {
  Future<String?> getOpenRouterApiKey();

  /// `null` o stringa vuota cancellano la key salvata.
  Future<void> setOpenRouterApiKey(String? key);

  /// Id del modello OpenRouter scelto; `null` se l'utente non ha mai scelto
  /// (si usa il default del catalogo).
  Future<String?> getOpenRouterModelId();

  Future<void> setOpenRouterModelId(String? modelId);
}

class SecureSettingsRepository implements SettingsRepository {
  SecureSettingsRepository({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  static const _apiKeyKey = 'ai.openrouter.apiKey';
  static const _modelKey = 'ai.openrouter.model';

  @override
  Future<String?> getOpenRouterApiKey() => _read(_apiKeyKey);

  @override
  Future<void> setOpenRouterApiKey(String? key) => _write(_apiKeyKey, key);

  @override
  Future<String?> getOpenRouterModelId() => _read(_modelKey);

  @override
  Future<void> setOpenRouterModelId(String? modelId) =>
      _write(_modelKey, modelId);

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
