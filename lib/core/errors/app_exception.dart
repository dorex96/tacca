/// Base per le eccezioni applicative tipizzate.
///
/// I sottotipi specifici (es. `AiException` e derivate) vengono introdotti
/// dalle rispettive feature; qui vive solo il contratto comune.
abstract class AppException implements Exception {
  final String message;
  final Object? cause;

  const AppException(this.message, {this.cause});

  @override
  String toString() => '$runtimeType: $message';
}
