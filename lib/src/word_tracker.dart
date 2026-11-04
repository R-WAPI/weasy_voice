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
  int _misses = 0;

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
    next = i; _last = ''; _misses = 0;
  }
  bool acceptWindow(String hypothesis) {
    final spoken = hypothesis.split(RegExp(r'\s+')).map(normalize).where((s) => s.isNotEmpty).toList();
    final signature = spoken.join(' ');
    if (signature == _last) return false;
    _last = signature;
    final start = next > 12 ? next - 12 : 0;
    final limit = (next + (_misses >= 2 && next > 0 ? 40 : 20)).clamp(0, words.length).toInt();
    var bestEnd = next;
    var bestScore = double.negativeInfinity;
    for (var s = 0; s < spoken.length; s++) {
      for (var p = start; p < limit; p++) {
        var pi = p, si = s, matched = 0, strong = 0, exact = 0, gaps = 0;
        while (pi < limit && si < spoken.length) {
          var match = _matchAt(spoken, pi, si, limit);
          if (match == null && matched > 0 && gaps == 0) {
            // A single inserted or omitted word is allowed only between anchors.
            final inserted = _matchAt(spoken, pi, si + 1, limit);
            final omitted = _matchAt(spoken, pi + 1, si, limit);
            if (inserted != null) { si++; match = inserted; gaps++; }
            else if (omitted != null) { pi++; match = omitted; gaps++; }
          }
          if (match == null) break;
          for (var k = pi; k < pi + match.scriptCount; k++) {
            if (words[k].length >= 4) strong++;
          }
          matched += match.scriptCount;
          if (match.quality == 2) exact += match.scriptCount;
          pi += match.scriptCount; si += match.spokenCount;
          if (pi <= next) continue;
          final singleExpected = matched == 1 && p == next && match.quality == 2;
          final anchored = matched >= 2 && strong >= 1 && (exact >= 1 || matched >= 3);
          final nearby = p <= next + 3;
          final recoveryPair = next > 0 && _misses >= 1 && matched == 2 && exact == 2 &&
              p > next && p <= next + 16 && pi == p + 2 &&
              words[p].length >= 5 && words[p + 1].length >= 5 &&
              _uniquePair(p);
          final reacquired = (matched >= 3 && strong >= 2) || recoveryPair;
          if (!(singleExpected || anchored) || !(nearby || reacquired)) continue;
          final distance = p > next ? p - next : 0;
          final score = strong * 3.0 + (matched - strong) + exact * 0.25 - gaps * 2 - distance * 0.12;
          if (score > bestScore || (score == bestScore && pi < bestEnd)) {
            bestEnd = pi; bestScore = score;
          }
        }
      }
    }
    final changed = next != bestEnd;
    _misses = changed ? 0 : _misses + 1;
    next = bestEnd;
    return changed;
  }

  bool _uniquePair(int position) {
    for (var i = 0; i + 1 < words.length; i++) {
      if (i != position && words[i] == words[position] && words[i + 1] == words[position + 1]) return false;
    }
    return true;
  }

  _WordMatch? _matchAt(List<String> spoken, int pi, int si, int limit) {
    if (pi >= limit || si >= spoken.length || words[pi].isEmpty) return null;
    final direct = _quality(words[pi], spoken[si]);
    if (direct == 2) return const _WordMatch(1, 1, 2);
    _WordMatch? best = direct == 1 ? const _WordMatch(1, 1, 1) : null;
    // ASR can split one written word or join two written words.
    var joined = spoken[si];
    for (var n = 2; n <= 3 && si + n <= spoken.length; n++) {
      joined += spoken[si + n - 1];
      final q = _quality(words[pi], joined);
      if (q > (best?.quality ?? 0)) best = _WordMatch(1, n, q);
    }
    if (pi + 1 < limit && words[pi + 1].isNotEmpty) {
      final q = _quality(words[pi] + words[pi + 1], spoken[si]);
      // A fuzzy join can swallow a short unspoken word and manufacture a
      // third anchor. Only exact joined spellings count as two script words.
      if (q == 2 && q > (best?.quality ?? 0)) best = _WordMatch(2, 1, q);
    }
    return best;
  }

  static int _quality(String expected, String actual) {
    if (expected == actual) return 2;
    if (expected.isEmpty || actual.isEmpty) return 0;
    final a = expected.replaceAll('x', 'ksz');
    final b = actual.replaceAll('x', 'ksz');
    if (a.length < 4 || b.length < 4) return 0;
    final longest = a.length > b.length ? a.length : b.length;
    if (longest < 5) return 0;
    final maximum = longest >= 8 ? 2 : 1;
    if ((a.length - b.length).abs() > maximum) return 0;
    var previous = List<int>.generate(b.length + 1, (i) => i);
    for (var i = 1; i <= a.length; i++) {
      final row = List<int>.filled(b.length + 1, 0); row[0] = i;
      for (var j = 1; j <= b.length; j++) {
        final insert = row[j - 1] + 1, delete = previous[j] + 1;
        final substitute = previous[j - 1] + (a.codeUnitAt(i - 1) == b.codeUnitAt(j - 1) ? 0 : 1);
        var value = insert < delete ? insert : delete;
        if (substitute < value) value = substitute;
        row[j] = value;
      }
      previous = row;
    }
    final distance = previous.last;
    return distance <= maximum && distance / longest <= 0.25 ? 1 : 0;
  }
}

class _WordMatch {
  const _WordMatch(this.scriptCount, this.spokenCount, this.quality);
  final int scriptCount, spokenCount, quality;
}
