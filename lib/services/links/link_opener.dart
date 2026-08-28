import 'package:url_launcher/url_launcher.dart';

/// Apertura di un indirizzo web **fuori** dall'app.
///
/// Esiste come servizio, e non come chiamata diretta a `url_launcher` dentro
/// le pagine, per due motivi: nei widget test il plugin di piattaforma non
/// c'è (lo sostituisce una fake) e nessuna pagina deve poter scegliere una
/// modalità di apertura diversa da quella esterna.
abstract interface class LinkOpener {
  /// Apre [url] nel browser di sistema. Torna `false` se non è stato
  /// possibile: chi chiama deve avere un piano B (copiare il link).
  Future<bool> open(Uri url);
}

class UrlLauncherLinkOpener implements LinkOpener {
  const UrlLauncherLinkOpener();

  @override
  Future<bool> open(Uri url) async {
    try {
      // `externalApplication` e non `platformDefault`: su Android il default
      // per http/https è la Custom Tab, cioè un browser *dentro* l'app. Qui
      // si esce dall'app apposta — nessuna WebView incorporata, niente da
      // dichiarare oltre alla voce <queries> del manifest.
      return await launchUrl(url, mode: LaunchMode.externalApplication);
    } on Exception {
      return false;
    }
  }
}
