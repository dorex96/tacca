/// Formattazione delle durate per timer e riepiloghi.
///
/// Non passa dagli ARB: sono formati numerici, identici in ogni lingua.
extension DurationFormat on Duration {
  /// `mm:ss`, oppure `h:mm:ss` oltre l'ora. Le durate negative diventano zero
  /// (il countdown non va sotto lo zero).
  String get clock {
    final total = isNegative ? Duration.zero : this;
    final seconds = total.inSeconds % 60;
    final minutes = total.inMinutes % 60;
    final hours = total.inHours;
    final mm = minutes.toString().padLeft(2, '0');
    final ss = seconds.toString().padLeft(2, '0');
    return hours > 0 ? '$hours:$mm:$ss' : '$mm:$ss';
  }

  /// Durata compatta per i riepiloghi: `1h 12m` oppure `47m`, `35s`.
  String get compact {
    final total = isNegative ? Duration.zero : this;
    if (total.inHours > 0) {
      return '${total.inHours}h ${total.inMinutes % 60}m';
    }
    if (total.inMinutes > 0) return '${total.inMinutes}m';
    return '${total.inSeconds}s';
  }
}
