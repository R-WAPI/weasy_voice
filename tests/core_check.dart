import '../lib/src/word_tracker.dart';
import '../lib/src/scroll_motion.dart';
import '../lib/src/line_scroll_plan.dart';
import '../lib/src/reading_rhythm.dart';
import '../lib/src/flow_motion.dart';

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
  final typo = WeasyWordTracker('A nagymacskákkal együtt dolgozott.');
  check(typo.acceptWindow('a nagymatskákkal együtt') && typo.next == 3);
  final names = WeasyWordTracker('Alberto szerkesztő Budapesten dolgozik.');
  check(names.acceptWindow('allbarto szerkezto buddapesten') && names.next == 3);
  final missingLetter = WeasyWordTracker('Hozott létre egy ablakot.');
  check(missingLetter.acceptWindow('hozott léte egy') && missingLetter.next == 3);
  final twoEdits = WeasyWordTracker('Kísérlet folytatódik.');
  check(twoEdits.acceptWindow('kisele folytatódik') && twoEdits.next == 2);
  final split = WeasyWordTracker('Szövegszerkesztő ablak nyílik.');
  check(split.acceptWindow('szöveg szerkesztő ablak') && split.next == 2);
  final joined = WeasyWordTracker('Kamera kép látszik.');
  check(joined.acceptWindow('kamerakép látszik') && joined.next == 3);
  final uncertain = WeasyWordTracker('Telefonon beszélgetünk.');
  check(!uncertain.acceptWindow('telefonom') && uncertain.next == 0);
  final inserted = WeasyWordTracker('Egy új ablak nyílik.');
  check(inserted.acceptWindow('egy kicsi új ablak') && inserted.next == 3);
  final omitted = WeasyWordTracker('A nagy ablak nyitva.');
  check(omitted.acceptWindow('a ablak nyitva') && omitted.next == 4);
  final common = WeasyWordTracker('Kezdet következik sorok között szöveggel egy az ablak végén.');
  check(!common.acceptWindow('egy az') && common.next == 0);
  check(!common.acceptWindow('ablak végén') && common.next == 0);
  final recover = WeasyWordTracker('Most elkezdjük. Itt néhány hibásan hallott szó következik aztán biztosan folytatjuk tovább.');
  check(recover.acceptWindow('most elkezdjük') && recover.next == 2);
  check(!recover.acceptWindow('érthetetlen zaj'));
  check(recover.acceptWindow('biztosan folytatjuk') && recover.next == 11);
  recover.resetAtCharacter(0);
  check(!recover.acceptWindow('biztosan folytatjuk')); // Reset discards recovery history.
  final repeated = WeasyWordTracker('Most elkezdjük. Egy kettő három négy öt biztosan folytatjuk majd biztosan folytatjuk.');
  check(repeated.acceptWindow('most elkezdjük'));
  check(!repeated.acceptWindow('érthetetlen zaj'));
  check(!repeated.acceptWindow('biztosan folytatjuk')); // Ambiguous repeated pair cannot jump.
  final late = WeasyWordTracker('Most elkezdjük. ${List.generate(25, (i) => 'elem$i').join(' ')} pontosan követhető folytatás.');
  check(late.acceptWindow('most elkezdjük'));
  check(!late.acceptWindow('hibás hang'));
  check(!late.acceptWindow('más hiba'));
  check(late.acceptWindow('pontosan követhető folytatás') && late.next == 30);
  typo.resetAtCharacter(0);
  check(typo.next == 0);
  check(typo.acceptWindow('a nagymatskákkal együtt') && typo.next == 3);
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
  check(lines.queuedLines(0) == 3 && lines.queuedLines(32) == 2);
  check(lines.nextStop(0) == 32); // Batched speech still moves one line at a time.
  check(lines.nextStop(32) == 64);
  check(lines.nextStop(64) == 96);
  check(lines.nextStop(96) == null);
  lines.reset(32); // A manual rewind discards every old queued target.
  check(lines.nextStop(32) == null);
  lines.aim(64); check(lines.nextStop(32) == 64);
  lines.reset(10); lines.aim(64); check(lines.nextStop(10) == 32);
  lines.reset(96); lines.aim(110); check(lines.nextStop(96) == 110);
  final rhythm = WeasyReadingRhythm();
  check(rhythm.durationForLine(3).inMilliseconds == 825);
  check(rhythm.durationForLine(1).inMilliseconds == 450);
  check(rhythm.durationForLine(20).inMilliseconds == 950);
  check(rhythm.durationForLine(20, queuedLines: 3).inMilliseconds == 650);
  final faster = WeasyReadingRhythm();
  for (var i = 0; i <= 24; i++) { faster.observe(i, i / 4); }
  check(faster.wordsPerSecond > rhythm.wordsPerSecond);
  check(faster.durationForLine(3) < rhythm.durationForLine(3));
  final slower = WeasyReadingRhythm();
  for (var i = 0; i <= 12; i++) { slower.observe(i, i.toDouble()); }
  check(slower.durationForLine(3) > rhythm.durationForLine(3));
  final learned = faster.wordsPerSecond;
  faster.observe(25, 100); // A pause or recognition stall does not slow the learned tempo.
  check(faster.wordsPerSecond == learned);
  faster.observe(90, 100.1); // A catch-up burst does not accelerate it either.
  check(faster.wordsPerSecond == learned);
  faster.clearHistory(); faster.observe(0, 102); // Manual rewind preserves the user's tempo.
  check(faster.wordsPerSecond == learned);
  final flow = WeasyFlowMotion()..lineHeight = 32;
  var movingFrames = 0;
  for (var frame = 0; frame < 360; frame++) {
    if (frame % 30 == 0) flow.observe(frame / 60 * 20, 20);
    final before = flow.position;
    flow.step(1/60, 1000);
    check(flow.position >= before && flow.position - before <= 96/60 + 0.001);
    if (frame > 60 && flow.position - before > 0.05) movingFrames++;
  }
  check(movingFrames > 280); // No repeated stops between half-second ASR updates.
  final burstStart = flow.position;
  flow.observe(burstStart + 160, 20);
  final burstVelocity = flow.velocity;
  flow.step(1/60, 1000);
  check(flow.position - burstStart <= 96/60 + 0.001);
  check((flow.velocity - burstVelocity).abs() <= 256/60 + 0.001);
  for (var i = 0; i < 600; i++) { flow.step(1/60, 1000); }
  check(flow.settled && flow.position <= burstStart + 160 + 12.801);
  final stopped = flow.position;
  flow.step(1/60, 1000); check((flow.position - stopped).abs() < 0.001);
  flow.reset(10); // Manual rewind must discard prediction and velocity.
  flow.step(1/60, 1000); check(flow.position == 10 && flow.settled);
  flow.observe(100, 20);
  for (var i = 0; i < 600; i++) { flow.step(1/60, 50); }
  check(flow.position == 50 && flow.settled);
  final flow30 = WeasyFlowMotion(), flow60 = WeasyFlowMotion();
  flow30.observe(100, 20); flow60.observe(100, 20);
  for (var i = 0; i < 30; i++) { flow30.step(1/30, 1000); }
  for (var i = 0; i < 60; i++) { flow60.step(1/60, 1000); }
  check((flow30.position - flow60.position).abs() < 0.1);
  final start = WeasyFlowMotion(predictionSeconds: 1.4, predictionLines: 0.85);
  start.armStartDelay();
  for (var i = 0; i < 180; i++) { start.step(1/60, 1000); }
  check(start.position == 0); // No speech: the startup clock has not started.
  start.reset(0); // Layout must not discard the startup delay.
  start.observe(32, 20);
  for (var i = 0; i < 78; i++) { start.step(1/60, 1000); }
  check(start.position == 0 && !start.settled); // 1.3 seconds.
  start.observe(48, 20); // New words must not restart the delay.
  for (var i = 0; i < 12; i++) { start.step(1/60, 1000); }
  check(start.position > 0); // Moving by 1.5 seconds.
  for (var i = 0; i < 600; i++) { start.step(1/60, 1000); }
  check(start.settled && start.position <= 48 + 32 * 0.85 + 0.001);
  start.reset(10); start.observe(30, 20); start.step(1/60, 1000);
  check(start.position > 10); // No repeated delay after a manual rewind/resume.
  start.reset(0); start.armStartDelay(); start.observe(32, 20);
  start.step(0.1, 1000); check(start.position == 0); // A new take re-arms it.
  final onset = WeasyFlowMotion(predictionSeconds: 1.4, predictionLines: 0.85);
  onset.armStartDelay();
  onset.speechStarted(0.12); onset.reset(0); onset.observe(0, 20);
  for (var i = 0; i < 70; i++) { onset.step(1/60, 1000); }
  check(onset.position == 0); // 1.286 seconds from physical energy onset.
  for (var i = 0; i < 15; i++) { onset.step(1/60, 1000); }
  check(onset.position > 0); // Begins before the first recognized word arrives.
  for (var i = 0; i < 600; i++) {
    onset.speechStarted(12); onset.step(1/60, 1000);
  }
  check(onset.settled && onset.position <= 32 * 0.85 + 0.001); // Activity alone cannot run away.
  onset.reset(0); onset.armStartDelay(); onset.speechStarted(2.5); onset.observe(32, 20);
  onset.step(1/60, 1000); check(onset.position > 0); // No extra 1.4 s after delayed ASR.
  print('Dart core checks passed');
}
