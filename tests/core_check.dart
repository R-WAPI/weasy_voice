import '../lib/src/word_tracker.dart';
import '../lib/src/scroll_motion.dart';
import '../lib/src/line_scroll_plan.dart';

void check(bool condition) { if (!condition) throw StateError('Core check failed'); }
void main() {
  final t = WeasyWordTracker('Ez egy magyar próba. Most folytatom a szöveget.');
  check(t.acceptWindow('Ez egy magyar') && t.next == 3);
  check(t.acceptWindow('egy magyar próba most') && t.next == 5);
  check(t.acceptWindow('próba most folytatom a szöveget') && t.next == 8);
  t.resetAtCharacter(t.text.indexOf('Most'));
  check(t.next == 4);
  check(t.acceptWindow('most folytatom') && t.next == 6);
  check(!t.acceptWindow('most folytatom') && t.next == 6);
  check(!t.acceptWindow('teljesen más mondat') && t.next == 6);
  check(WeasyWordTracker.normalize('ÁRVÍZTŰRŐ!') == 'arvizturo');
  final m = WeasyScrollMotion(150);
  m.aim(100);
  var previous = 0.0;
  for (var i = 0; i < 240; i++) {
    final current = m.step(1/60);
    check(current >= previous && current <= 100);
    check(current - previous <= 2.501);
    previous = current;
  }
  check(m.settled);
  m.reset(30); check(m.position == 30 && m.settled);
  final thirty = WeasyScrollMotion(500), sixty = WeasyScrollMotion(500);
  thirty.aim(80); sixty.aim(80);
  for (var i = 0; i < 15; i++) { thirty.step(1/30); }
  for (var i = 0; i < 30; i++) { sixty.step(1/60); }
  check((thirty.position - sixty.position).abs() < 0.01);
  check(sixty.position > 78); // No extra one-second easing lag.
  sixty.aim(200);
  previous = sixty.position;
  for (var i = 0; i < 120; i++) {
    final current = sixty.step(1/60);
    check(current >= previous && current <= 200);
    previous = current;
  }
  check(sixty.settled);
  final before = sixty.position;
  check(sixty.step(0) == before);
  sixty.reset(12); sixty.aim(4); check(sixty.step(1/60) == 12);
  final lines = WeasyLineScrollPlan();
  lines.layout([0, 32, 32, 64, 96, 128], 110);
  check(lines.nextStop(0) == null); // No speech: no autonomous scrolling.
  lines.aim(96);
  check(lines.nextStop(0) == 32); // Batched speech still moves one line at a time.
  check(lines.nextStop(32) == 64);
  check(lines.nextStop(64) == 96);
  check(lines.nextStop(96) == null);
  lines.reset(32); // A manual rewind discards every old queued target.
  check(lines.nextStop(32) == null);
  lines.aim(64); check(lines.nextStop(32) == 64);
  lines.reset(10); lines.aim(64); check(lines.nextStop(10) == 32);
  lines.reset(96); lines.aim(110); check(lines.nextStop(96) == 110);
  print('Dart core checks passed');
}
