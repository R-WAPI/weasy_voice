/// Learns a conservative reading tempo from matched speech progress.
/// It controls animation duration only; it never advances the reading cursor.
class WeasyReadingRhythm {
  WeasyReadingRhythm({double initialWordsPerSecond = 2.0})
      : wordsPerSecond = initialWordsPerSecond.clamp(0.8, 5.0).toDouble();
  double wordsPerSecond;
  final List<_ReadingSample> _samples = [];
  double _lastEstimate = double.negativeInfinity;

  void clearHistory() { _samples.clear(); _lastEstimate = double.negativeInfinity; }
  void observe(int readWords, double seconds) {
    if (!seconds.isFinite || seconds < 0 || readWords < 0) return;
    if (_samples.isNotEmpty) {
      final last = _samples.last;
      if (seconds <= last.seconds) return;
      if (readWords < last.words || seconds - last.seconds > 4 || readWords - last.words > 20) {
        clearHistory();
      } else if (readWords == last.words) { return; }
    }
    _samples.add(_ReadingSample(readWords, seconds));
    while (_samples.length > 2 && _samples[1].seconds < seconds - 7) { _samples.removeAt(0); }
    final span = seconds - _samples.first.seconds;
    final advance = readWords - _samples.first.words;
    if (span < 2.5 || advance < 4 || seconds - _lastEstimate < 1) return;
    final measured = advance / span;
    // A recognition catch-up burst is not evidence that the reader sped up.
    if (measured < 0.8 || measured > 5) return;
    wordsPerSecond += (measured - wordsPerSecond) * 0.2;
    _lastEstimate = seconds;
  }

  Duration durationForLine(int wordCount, {int queuedLines = 1}) {
    var seconds = (0.55 * wordCount / wordsPerSecond).clamp(0.45, 0.95).toDouble();
    if (queuedLines > 1 && seconds > 0.65) seconds = 0.65;
    return Duration(microseconds: (seconds * 1000000).round());
  }
}

class _ReadingSample {
  const _ReadingSample(this.words, this.seconds);
  final int words;
  final double seconds;
}
