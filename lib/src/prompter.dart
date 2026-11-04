import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import '../weasy_voice.dart';
import 'flow_motion.dart';
import 'reading_rhythm.dart';

/// Place over CameraPreview. It is never drawn into the camera's video track.
class WeasyPrompter extends StatefulWidget {
  const WeasyPrompter({super.key, required this.controller, required this.text,
    this.fontFamily = 'Inter', this.fontSize = 24, this.height = 230,
    this.onError, this.onPositionChanged});
  final WeasyCaptureController controller;
  final String text, fontFamily;
  final double fontSize, height;
  final ValueChanged<String>? onError;
  final ValueChanged<int>? onPositionChanged;
  @override State<WeasyPrompter> createState() => _WeasyPrompterState();
}

class _WeasyPrompterState extends State<WeasyPrompter> with SingleTickerProviderStateMixin {
  final _scroll = ScrollController();
  final _textKey = GlobalKey();
  final _flow = WeasyFlowMotion();
  final List<double> _wordTops = [];
  double _lineHeight = 32;
  final _rhythm = WeasyReadingRhythm();
  final _clock = Stopwatch()..start();
  double _layoutWidth = -1, _layoutHeight = -1, _firstLineTop = 0;
  late WeasyWordTracker _tracker;
  late Ticker _ticker;
  StreamSubscription<WeasyVoiceEvent>? _subscription;
  Timer? _settle;
  bool _touching = false, _manual = false, _accept = true;
  int _generation = 0;
  Duration _previous = Duration.zero;
  late WeasyCapturePhase _lastPhase;

  @override void initState() {
    super.initState(); _tracker = WeasyWordTracker(widget.text);
    _ticker = createTicker(_frame); _listen();
    _lastPhase = widget.controller.phase.value;
    widget.controller.phase.addListener(_phaseChanged);
  }
  void _phaseChanged() {
    final current = widget.controller.phase.value;
    if (current != WeasyCapturePhase.recording) {
      _ticker.stop(); _rhythm.clearHistory();
      if (_scroll.hasClients) _flow.reset(_scroll.offset);
    }
    if (_lastPhase == WeasyCapturePhase.complete && current == WeasyCapturePhase.idle) {
      _tracker = WeasyWordTracker(widget.text);
      _flow.reset(0);
      if (_scroll.hasClients) _scroll.jumpTo(0);
      setState(() {});
    }
    _lastPhase = current;
    if (current == WeasyCapturePhase.recording) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _aimAtReadingPoint());
    }
  }
  void _listen() {
    _subscription = widget.controller.events.listen((event) {
      if (!mounted) return;
      if (event.type == 'recognitionError' || event.type == 'captureError') {
        widget.onError?.call(event.message); return;
      }
      if (!_accept || _manual || event.type != 'transcript' ||
          event.revision != widget.controller.revision) return;
      if (_tracker.acceptWindow(event.text)) {
        _rhythm.observe(_tracker.next, _clock.elapsedMicroseconds / 1000000.0);
        setState(() {});
        widget.onPositionChanged?.call(_tracker.readCharacterEnd);
        WidgetsBinding.instance.addPostFrameCallback((_) => _aimAtReadingPoint());
      }
    });
  }
  @override void didUpdateWidget(WeasyPrompter old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      old.controller.phase.removeListener(_phaseChanged);
      _lastPhase = widget.controller.phase.value;
      widget.controller.phase.addListener(_phaseChanged);
      _subscription?.cancel(); _listen();
    }
    if (old.text != widget.text) {
      _generation++; _accept = false; _ticker.stop();
      _rhythm.clearHistory();
      _layoutWidth = -1;
      _tracker = WeasyWordTracker(widget.text);
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!mounted) return;
        if (_scroll.hasClients) { _scroll.jumpTo(0); _flow.reset(0); }
        await _resetRecognition();
      });
    }
    if (old.fontSize != widget.fontSize || old.fontFamily != widget.fontFamily) {
      _layoutWidth = -1;
      WidgetsBinding.instance.addPostFrameCallback((_) => _aimAtReadingPoint());
    }
  }
  RenderParagraph? get _paragraph {
    final object = _textKey.currentContext?.findRenderObject();
    return object is RenderParagraph ? object : null;
  }
  void _aimAtReadingPoint() {
    if (!mounted || _manual || !_accept || !_scroll.hasClients || widget.text.isEmpty ||
        widget.controller.phase.value != WeasyCapturePhase.recording) return;
    final paragraph = _paragraph;
    if (paragraph == null) return;
    if (_layoutWidth != paragraph.size.width || _layoutHeight != paragraph.size.height) {
      _ticker.stop();
      final lines = paragraph.getBoxesForSelection(TextSelection(baseOffset: 0, extentOffset: widget.text.length));
      if (lines.isEmpty) return;
      _firstLineTop = lines.first.top;
      final tops = lines.map((box) => box.top).toSet().toList()..sort();
      _lineHeight = tops.length > 1 ? tops[1] - tops[0] : widget.fontSize * 1.3;
      _wordTops.clear();
      for (final start in _tracker.starts) {
        final box = paragraph.getBoxesForSelection(TextSelection(baseOffset: start,
            extentOffset: math.min(start + 1, widget.text.length)));
        _wordTops.add(box.isEmpty ? (_wordTops.isEmpty ? 0 : _wordTops.last)
            : box.first.top - _firstLineTop);
      }
      _flow.lineHeight = _lineHeight;
      _flow.reset(_scroll.offset);
      _layoutWidth = paragraph.size.width; _layoutHeight = paragraph.size.height;
    }
    if (_wordTops.isEmpty || _tracker.next == 0) return;
    final index = math.min(_tracker.next, _wordTops.length - 1);
    final top = _wordTops[index];
    var first = index, last = index + 1;
    while (first > 0 && (_wordTops[first - 1] - top).abs() < 1) { first--; }
    while (last < _wordTops.length && (_wordTops[last] - top).abs() < 1) { last++; }
    final count = last - first;
    final fraction = ((_tracker.next - first) / count).clamp(0.0, 1.0);
    // Advance within a wrapped line, keeping the current word below the lens.
    final target = (top + fraction * _lineHeight - _lineHeight * 0.75)
        .clamp(0.0, _scroll.position.maxScrollExtent).toDouble();
    final pace = _rhythm.wordsPerSecond * _lineHeight / count;
    _flow.observe(target, _tracker.next >= _wordTops.length ? 0 : pace);
    if (!_ticker.isActive) { _previous = Duration.zero; _ticker.start(); }
  }
  void _frame(Duration time) {
    if (!mounted || _manual || !_scroll.hasClients ||
        widget.controller.phase.value != WeasyCapturePhase.recording) { _ticker.stop(); return; }
    final dt = _previous == Duration.zero ? 1.0/60 : (time - _previous).inMicroseconds / 1000000.0;
    _previous = time;
    final y = _flow.step(dt, _scroll.position.maxScrollExtent);
    if ((y - _scroll.offset).abs() > 0.001) _scroll.jumpTo(y);
    if (_flow.settled) _ticker.stop();
  }
  void _touchStart() {
    _generation++; _touching = true; _manual = true; _accept = false;
    _rhythm.clearHistory();
    _ticker.stop(); _settle?.cancel();
    if (_scroll.hasClients) _flow.reset(_scroll.offset);
    unawaited(widget.controller.suspendRecognition().catchError((Object e) {
      if (mounted) widget.onError?.call(e.toString()); return -1;
    }));
  }
  void _scheduleSettle() {
    if (!_manual || _touching) return;
    _settle?.cancel(); _settle = Timer(const Duration(milliseconds: 240), _manualSettled);
  }
  Future<void> _manualSettled() async {
    if (!mounted || _touching || !_scroll.hasClients) return;
    final paragraph = _paragraph;
    if (paragraph == null) return;
    final y = math.max(0.0, _scroll.offset - 8);
    final position = paragraph.getPositionForOffset(Offset(0, y));
    // Map the viewport top to the first word on that visual line.
    _tracker.resetAtCharacter(position.offset);
    _flow.reset(_scroll.offset);
    _manual = false; setState(() {});
    widget.onPositionChanged?.call(_tracker.readCharacterEnd);
    await _resetRecognition();
  }
  Future<void> _resetRecognition() async {
    final generation = _generation;
    try {
      await widget.controller.resetRecognition();
      if (mounted && generation == _generation && !_touching) _accept = true;
    } catch (e) { if (mounted) widget.onError?.call(e.toString()); }
  }
  @override Widget build(BuildContext context) {
    final end = _tracker.readCharacterEnd;
    final style = TextStyle(fontFamily: widget.fontFamily, fontSize: widget.fontSize,
        fontWeight: FontWeight.w700, height: 1.3, color: Colors.white);
    return Container(
      height: widget.height,
      decoration: BoxDecoration(color: const Color(0xFF041622).withOpacity(0.31),
          borderRadius: BorderRadius.circular(8)),
      child: Listener(
        onPointerDown: (_) => _touchStart(),
        onPointerUp: (_) { _touching = false; _scheduleSettle(); },
        onPointerCancel: (_) { _touching = false; _scheduleSettle(); },
        child: NotificationListener<ScrollNotification>(
          onNotification: (_) { _scheduleSettle(); return false; },
          child: SingleChildScrollView(
            controller: _scroll,
            padding: EdgeInsets.fromLTRB(12, 8, 12, widget.height),
            child: RepaintBoundary(child: RichText(key: _textKey, textScaler: MediaQuery.textScalerOf(context),
              text: TextSpan(style: style, children: [
                if (end > 0) TextSpan(text: widget.text.substring(0, end),
                    style: const TextStyle(color: Color(0xFF91918B))),
                TextSpan(text: widget.text.substring(end)),
              ]))),
          ),
        ),
      ),
    );
  }
  @override void dispose() {
    widget.controller.phase.removeListener(_phaseChanged);
    _generation++; _settle?.cancel(); _subscription?.cancel();
    _ticker.dispose(); _scroll.dispose(); super.dispose();
  }
}
