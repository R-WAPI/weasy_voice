import '../lib/src/word_tracker.dart';
import '../lib/src/scroll_motion.dart';

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
  print('Dart core checks passed');
}
