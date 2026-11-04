library weasy_voice;

import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

export 'src/capture_controller.dart';
export 'src/word_tracker.dart';
export 'src/prompter.dart';

class WeasyVoiceEvent {
  WeasyVoiceEvent(Map<dynamic, dynamic> value)
      : type = value['type'] as String? ?? '',
        text = value['text'] as String? ?? '',
        message = value['message'] as String? ?? '',
        revision = (value['revision'] as num?)?.toInt() ?? -1,
        inferenceMs = (value['inferenceMs'] as num?)?.toInt() ?? 0,
        speechElapsedMs = (value['speechElapsedMs'] as num?)?.toInt() ?? -1;
  final String type, text, message;
  final int revision, inferenceMs, speechElapsedMs;
}

class WeasyAudioFile {
  WeasyAudioFile(Map<dynamic, dynamic> value)
      : path = value['audioPath'] as String,
        offsetUs = (value['audioOffsetUs'] as num?)?.toInt() ?? 0,
        durationUs = (value['durationUs'] as num?)?.toInt() ?? 0,
        warning = value['warning'] as String?;
  final String path;
  final int offsetUs, durationUs;
  final String? warning;
}

/// Low-level native bridge. Camera must not open its own audio recorder.
class WeasyVoice {
  WeasyVoice._();
  static final WeasyVoice instance = WeasyVoice._();
  static const _methods = MethodChannel('weasy_voice/methods');
  static const _stream = EventChannel('weasy_voice/events');
  Stream<WeasyVoiceEvent>? _events;
  bool get supported => !kIsWeb && Platform.isAndroid;

  void _check() {
    if (!supported) throw UnsupportedError('A Weasy magyar motor jelenleg csak Android ARM64, Android 13+ rendszeren érhető el.');
  }
  Stream<WeasyVoiceEvent> get events {
    _check();
    return _events ??= _stream.receiveBroadcastStream().map((value) =>
        WeasyVoiceEvent(Map<dynamic, dynamic>.from(value as Map))).asBroadcastStream();
  }
  Future<String> initialize() async {
    _check();
    return await _methods.invokeMethod<String>('initialize') ?? 'Magyar felismerő kész.';
  }
  Future<bool> requestMicrophonePermission() async {
    _check();
    return await _methods.invokeMethod<bool>('microphonePermission') ?? false;
  }
  Future<int> startAudio() async {
    _check(); return (await _methods.invokeMethod<num>('startAudio'))!.toInt();
  }
  Future<int> pauseAudio() async => (await _methods.invokeMethod<num>('pauseAudio'))!.toInt();
  Future<int> resumeAudio() async => (await _methods.invokeMethod<num>('resumeAudio'))!.toInt();
  Future<int> resetRecognition() async => (await _methods.invokeMethod<num>('resetRecognition'))!.toInt();
  Future<int> suspendRecognition() async => (await _methods.invokeMethod<num>('suspendRecognition'))!.toInt();
  Future<WeasyAudioFile> stopAudio() async =>
      WeasyAudioFile((await _methods.invokeMapMethod<dynamic,dynamic>('stopAudio'))!);
  Future<String> finalizeVideo(String silentVideo, WeasyAudioFile audio) async {
    return (await _methods.invokeMethod<String>('finalizeVideo', {
      'videoPath': silentVideo, 'audioPath': audio.path, 'audioOffsetUs': audio.offsetUs,
    }))!;
  }
  Future<void> deleteTemporary(String path) =>
      _methods.invokeMethod<void>('deleteTemporary', {'path': path});
}
