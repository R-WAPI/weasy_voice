import 'dart:math' as math;

/// Continuous, acceleration-limited following of speech anchors.
/// Prediction affects display only, never the confirmed/read word cursor.
class WeasyFlowMotion {
  double position = 0, velocity = 0;
  double _anchor = 0, _age = 10, _pace = 0;
  bool _atEnd = false;
  double lineHeight = 32;
  bool get settled => _atEnd || (_age >= 0.65 && velocity < 0.05 &&
      (_target - position).abs() < 0.05);

  void reset(double value) {
    position = value; _anchor = value; velocity = 0; _pace = 0; _age = 10; _atEnd = false;
  }

  void observe(double anchor, double pixelsPerSecond) {
    _anchor = math.max(position, anchor);
    _pace = pixelsPerSecond.clamp(0.0, lineHeight * 2).toDouble();
    _age = 0;
    _atEnd = false;
  }

  double get _target => _anchor + math.min(_pace * math.min(_age, 0.65), lineHeight * 0.4);

  double step(double seconds, double maximum) {
    if (seconds <= 0) return position;
    // Substeps keep acceleration consistent across 30/60/120 Hz screens.
    var remaining = seconds.clamp(0.0, 0.1).toDouble();
    while (remaining > 0.000001) {
      final dt = math.min(remaining, 1 / 120);
      remaining -= dt; _age += dt;
      final target = math.min(maximum, _target);
      final distance = math.max(0.0, target - position);
      final acceleration = lineHeight * 8;
      final cruise = _age < 0.65 ? _pace : 0.0;
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
