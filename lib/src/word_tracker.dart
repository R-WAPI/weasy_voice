/// Matches only recognized words; elapsed time never advances this cursor.
class WeasyWordTracker {
  WeasyWordTracker(this.text) {
    for (final match in RegExp(r'\S+').allMatches(text)) {
      starts.add(match.start);
      words.add(normalize(match.group(0)!));
    }
  }
  final String text;
  final List<int> starts = [];
  final List<String> words = [];
  int next = 0;
  String _last = '';

  static String normalize(String word) {
    const accents = {'á':'a','é':'e','í':'i','ó':'o','ö':'o','ő':'o','ú':'u','ü':'u','ű':'u'};
    var value = word.toLowerCase();
    for (final entry in accents.entries) { value = value.replaceAll(entry.key, entry.value); }
    return value.replaceAll(RegExp('[^a-z0-9]'), '');
  }
  int get readCharacterEnd => next >= starts.length ? text.length : starts[next];
  void resetAtCharacter(int character) {
    var i = 0;
    while (i < starts.length && starts[i] < character) { i++; }
    next = i; _last = '';
  }
  bool acceptWindow(String hypothesis) {
    final spoken = hypothesis.split(RegExp(r'\s+')).map(normalize).where((s) => s.isNotEmpty).toList();
    final signature = spoken.join(' ');
    if (signature == _last) return false;
    _last = signature;
    final start = next > 12 ? next - 12 : 0;
    final limit = (next + 20).clamp(0, words.length).toInt();
    var bestEnd = next, bestRun = 0;
    for (var s = 0; s < spoken.length; s++) {
      for (var p = start; p < limit; p++) {
        var run = 0;
        while (s + run < spoken.length && p + run < limit && words[p + run].isNotEmpty && words[p + run] == spoken[s + run]) { run++; }
        final end = p + run;
        final safe = run >= 2 || (run == 1 && p == next);
        if (safe && end > next && (run > bestRun || (run == bestRun && end < bestEnd))) {
          bestEnd = end; bestRun = run;
        }
      }
    }
    final changed = next != bestEnd;
    next = bestEnd;
    return changed;
  }
}
