import 'dart:math' as math;

/// Continuous, acceleration-limited following of speech anchors.
/// Prediction affects display only, never the confirmed/read word cursor.
class WeasyFlowMotion {
  WeasyFlowMotion({this.predictionSeconds = 0.65, this.predictionLines = 0.4});
  final double predictionSeconds, predictionLines;
  double _startRemaining = 0;
  bool _hasObservation = false;
  void armStartDelay([double seconds = 1.4]) {
    _startRemaining = seconds; _hasObservation = false; velocity = 0;
  }
  double position = 0, velocity = 0;
  double _anchor = 0, _age = 10, _pace = 0;
  bool _atEnd = false;
  double lineHeight = 32;
  bool get settled => _startRemaining > 0 ? !_hasObservation : _atEnd || (_age >= predictionSeconds && velocity < 0.05 &&
      (_target - position).abs() < 0.05);

  void reset(double value) {
    position = value; _anchor = value; velocity = 0; _pace = 0; _age = 10; _atEnd = false;
    _hasObservation = false;
  }

  void observe(double anchor, double pixelsPerSecond) {
    _anchor = math.max(position, anchor);
    _pace = pixelsPerSecond.clamp(0.0, lineHeight * 2).toDouble();
    _age = 0;
    _hasObservation = true;
    _atEnd = false;
  }

  double get _target => _anchor + math.min(_pace * math.min(_age, predictionSeconds), lineHeight * predictionLines);

  double step(double seconds, double maximum) {
    if (seconds <= 0) return position;
    // Substeps keep acceleration consistent across 30/60/120 Hz screens.
    var remaining = seconds.clamp(0.0, 0.1).toDouble();
    while (remaining > 0.000001) {
      final dt = math.min(remaining, 1 / 120);
      remaining -= dt;
      if (_startRemaining > 0) {
        if (_hasObservation) _startRemaining = math.max(0, _startRemaining - dt);
        continue;
      }
      _age += dt;
      final target = math.min(maximum, _target);
      final distance = math.max(0.0, target - position);
      if (distance < 0.01 && velocity < 0.05 && _age >= predictionSeconds) {
        position = target; velocity = 0;
        continue;
      }
      final acceleration = lineHeight * 8;
      final cruise = _age < predictionSeconds ? _pace : 0.0;
      final desired = math.min(lineHeight * 3,
          math.min(cruise + distance * 3, math.sqrt(2 * acceleration * distance)));
      final oldVelocity = velocity;
      velocity += (desired - velocity).clamp(-acceleration * dt, acceleration * dt);
      final movement = (oldVelocity + velocity) * 0.5 * dt;
      if (movement >= distance) {
        position += distance; velocity = 0;
      } else {
        position += movement;
      }
    }
    _atEnd = position >= maximum;
    return position;
  }
}
