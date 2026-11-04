/// Smooths recognized targets; does not advance any reading cursor itself.
class WeasyScrollMotion {
  WeasyScrollMotion(this.maxSpeed);
  final double maxSpeed;
  double position = 0, target = 0, velocity = 0;
  bool get settled => target - position < 0.3 && velocity < 0.5;
  void reset(double value) { position = value; target = value; velocity = 0; }
  void aim(double value) { if (value > target) target = value; }
  double step(double seconds) {
    final dt = seconds.clamp(0.0, 0.05).toDouble();
    final distance = (target - position).clamp(0.0, double.infinity).toDouble();
    final desired = (distance * 5).clamp(0.0, maxSpeed).toDouble();
    // Stable approximation to 1-exp(-dt/0.1), bounded for frame stalls.
    final response = dt / (0.1 + dt);
    velocity += (desired - velocity) * response;
    position += (velocity * dt).clamp(0.0, distance).toDouble();
    if (distance < 0.3 && velocity < 0.5) { position = target; velocity = 0; }
    return position;
  }
}
