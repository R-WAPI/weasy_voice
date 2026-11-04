import 'dart:async';
import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import '../weasy_voice.dart';

enum WeasyCapturePhase { idle, starting, recording, paused, finalizing, complete, failed, closed }

/// Keep this object in the camera session store when navigating to the editor.
/// The camera is intentionally silent: the native plugin owns the single audio stream.
class WeasyCaptureController with WidgetsBindingObserver {
  WeasyCaptureController._(this.camera) {
    WidgetsBinding.instance.addObserver(this);
    _subscription = _voice.events.listen(_event, onError: (Object e) {
      lastError = e.toString();
    });
  }
  final CameraController camera;
  final _voice = WeasyVoice.instance;
  final phase = ValueNotifier(WeasyCapturePhase.idle);
  final _events = StreamController<WeasyVoiceEvent>.broadcast();
  late final StreamSubscription<WeasyVoiceEvent> _subscription;
  Future<void> _tail = Future<void>.value();
  int _revision = -1;
  String? _silentPath, _outputPath;
  WeasyAudioFile? _audio;
  bool _audioStarted = false, _closed = false;
  String? lastError;
  Stream<WeasyVoiceEvent> get events => _events.stream;
  int get revision => _revision;
  bool get hasPendingRecording => const [WeasyCapturePhase.recording, WeasyCapturePhase.paused,
    WeasyCapturePhase.finalizing, WeasyCapturePhase.failed].contains(phase.value);

  static Future<WeasyCaptureController> create(CameraDescription description,
      {ResolutionPreset resolution = ResolutionPreset.high}) async {
    final voice = WeasyVoice.instance;
    if (!await voice.requestMicrophonePermission()) throw StateError('A videóhanghoz mikrofonengedély szükséges.');
    await voice.initialize();
    final camera = CameraController(description, resolution, enableAudio: false);
    try { await camera.initialize(); }
    catch (_) { await camera.dispose(); rethrow; }
    return WeasyCaptureController._(camera);
  }
  Future<T> _run<T>(Future<T> Function() action) {
    final result = _tail.then((_) {
      if (_closed) throw StateError('A felvételi munkamenet már bezárult.');
      return action();
    });
    _tail = result.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return result;
  }
  void _event(WeasyVoiceEvent event) {
    if (_closed) return;
    if (event.type == 'captureError' && _audioStarted) {
      lastError = event.message; phase.value = WeasyCapturePhase.failed;
      if (camera.value.isRecordingVideo && !camera.value.isRecordingPaused) {
        unawaited(camera.pauseVideoRecording().catchError((Object _) {}));
      }
      _events.add(event);
    } else if (event.revision == _revision) {
      if (event.type == 'recognitionError') lastError = event.message;
      if (event.type != 'transcript' || phase.value == WeasyCapturePhase.recording) _events.add(event);
    }
  }
  Future<void> start() => _run(() async {
    if (phase.value != WeasyCapturePhase.idle) throw StateError('Előbb zárd le az előző felvételt.');
    lastError = null; phase.value = WeasyCapturePhase.starting;
    try {
      await camera.startVideoRecording();
      try {
        _revision = await _voice.startAudio();
        _audioStarted = true;
      } catch (_) {
        final failed = await camera.stopVideoRecording();
        final file = File(failed.path);
        if (await file.exists()) await file.delete();
        rethrow;
      }
      phase.value = WeasyCapturePhase.recording;
    } catch (e) { lastError = e.toString(); phase.value = WeasyCapturePhase.idle; rethrow; }
  });
  Future<void> pause() => _run(() async {
    if (phase.value == WeasyCapturePhase.paused) return;
    if (phase.value != WeasyCapturePhase.recording) return;
    await camera.pauseVideoRecording();
    try { _revision = await _voice.pauseAudio(); }
    catch (_) { await camera.resumeVideoRecording(); rethrow; }
    phase.value = WeasyCapturePhase.paused;
  });
  Future<void> resume() => _run(() async {
    if (phase.value != WeasyCapturePhase.paused) throw StateError('A felvétel nincs szüneteltetve.');
    await camera.resumeVideoRecording();
    try { _revision = await _voice.resumeAudio(); }
    catch (_) { await camera.pauseVideoRecording(); rethrow; }
    phase.value = WeasyCapturePhase.recording;
  });
  Future<int> resetRecognition() => _run(() async {
    if (!_audioStarted) return _revision;
    return _revision = await _voice.resetRecognition();
  });
  Future<int> suspendRecognition() => _run(() async {
    if (!_audioStarted) return _revision;
    return _revision = await _voice.suspendRecognition();
  });
  Future<String> finish() => _run(() async {
    if (phase.value == WeasyCapturePhase.complete && _outputPath != null) return _outputPath!;
    if (!hasPendingRecording) throw StateError('Nincs lezárható felvétel.');
    phase.value = WeasyCapturePhase.finalizing;
    try {
      final operations = <Future<void>>[];
      if (_silentPath == null && camera.value.isRecordingVideo) {
        operations.add(camera.stopVideoRecording().then((file) { _silentPath = file.path; }));
      }
      if (_audio == null && _audioStarted) {
        operations.add(_voice.stopAudio().then((audio) {
          _audio = audio; _audioStarted = false;
          if (audio.warning != null) lastError = audio.warning;
        }));
      }
      await Future.wait(operations, eagerError: false);
      if (_silentPath == null || _audio == null) throw StateError('A felvétel egyik sávja hiányzik; az elérhető fájlokat megőriztük.');
      _outputPath = await _voice.finalizeVideo(_silentPath!, _audio!);
      phase.value = WeasyCapturePhase.complete;
      return _outputPath!;
    } catch (e) { lastError = e.toString(); phase.value = WeasyCapturePhase.failed; rethrow; }
  });
  /// Call only after confirmed gallery save OR confirmed discard, with player disposed.
  Future<void> cleanupAfterDecision() => _run(() async {
    if (phase.value != WeasyCapturePhase.complete) throw StateError('Előbb véglegesítsd a videót.');
    if (_audio != null) await _voice.deleteTemporary(_audio!.path);
    if (_outputPath != null) await _voice.deleteTemporary(_outputPath!);
    if (_silentPath != null) {
      final silent = File(_silentPath!);
      if (await silent.exists()) await silent.delete();
    }
    _audio = null; _silentPath = null; _outputPath = null; lastError = null;
    phase.value = WeasyCapturePhase.idle;
  });
  @override void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed &&
        (phase.value == WeasyCapturePhase.recording || phase.value == WeasyCapturePhase.starting)) {
      unawaited(pause().catchError((Object e) { lastError = e.toString(); }));
    }
  }
  Future<void> dispose() => _run(() async {
    if (hasPendingRecording) throw StateError('A folytatható felvétel miatt a kontrollert még nem szabad eldobni.');
    _closed = true; WidgetsBinding.instance.removeObserver(this);
    await _subscription.cancel(); await _events.close(); await camera.dispose();
    phase.value = WeasyCapturePhase.closed; phase.dispose();
  });
}
