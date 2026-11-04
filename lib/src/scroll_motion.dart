import 'dart:math' as math;

/// Smooths recognized targets; does not advance any reading cursor itself.
class WeasyScrollMotion {
  WeasyScrollMotion(this.maxSpeed);
  double maxSpeed;
  double position = 0, target = 0, velocity = 0;
  bool get settled => target - position < 0.3 && velocity < 0.5;
  void reset(double value) { position = value; target = value; velocity = 0; }
  void aim(double value) { if (value > target) target = value; }
  double step(double seconds) {
    final dt = seconds.clamp(0.0, 0.05).toDouble();
    final distance = (target - position).clamp(0.0, double.infinity).toDouble();
    if (dt == 0) return position;
    // Exact critically damped spring: quick response without the old long tail.
    const omega = 14.0;
    final displacement = position - target;
    final coefficient = velocity + omega * displacement;
    final decay = math.exp(-omega * dt);
    final proposed = target + (displacement + coefficient * dt) * decay;
    final movement = (proposed - position).clamp(0.0, math.min(distance, maxSpeed * dt)).toDouble();
    final proposedVelocity = (velocity - omega * coefficient * dt) * decay;
    velocity = proposed - position > maxSpeed * dt
        ? movement / dt : proposedVelocity.clamp(0.0, maxSpeed).toDouble();
    position += movement;
    if (distance < 0.3 && velocity < 0.5) { position = target; velocity = 0; }
    return position;
  }
}
