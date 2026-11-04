/// Actual wrapped-line stops. Recognition chooses the target; each animation
/// consumes at most one line, even if a result contains several spoken lines.
class WeasyLineScrollPlan {
  List<double> _stops = [0];
  double target = 0;
  void layout(Iterable<double> tops, double maxExtent) {
    final values = tops.map((y) => y.clamp(0.0, maxExtent).toDouble()).toList()..sort();
    _stops = [0];
    for (final y in values) {
      if (y - _stops.last > 0.5) _stops.add(y);
    }
    target = target.clamp(0.0, maxExtent).toDouble();
  }
  void aim(double value) { if (value > target) target = value; }
  void reset(double position) { target = position; }
  int queuedLines(double position) {
    if (target <= position + 0.25) return 0;
    final count = _stops.where((y) => y > position + 0.25 && y <= target + 0.25).length;
    return count == 0 ? 1 : count;
  }
  double? nextStop(double position) {
    if (target <= position + 0.25) return null;
    for (final stop in _stops) {
      if (stop > position + 0.25 && stop <= target + 0.25) return stop;
    }
    return target;
  }
}
