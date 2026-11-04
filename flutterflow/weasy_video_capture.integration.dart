// Automatic FlutterFlow imports
import '/backend/schema/structs/index.dart';
import '/flutter_flow/ff_builtin_enums.dart';
import '/flutter_flow/flutter_flow_theme.dart';
import '/flutter_flow/flutter_flow_util.dart';
import '/custom_code/widgets/index.dart'; // Imports other custom widgets
import 'package:flutter/material.dart' hide RepeatMode;
// Begin custom widget code
// DO NOT REMOVE OR MODIFY THE CODE ABOVE!

import 'dart:io';
import 'package:weasy_voice/weasy_voice.dart';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:gal/gal.dart';
import 'package:video_player/video_player.dart';

class WeasyVideoCapture extends StatefulWidget {
  const WeasyVideoCapture({
    super.key,
    this.width,
    this.height,
    this.review = false,
    this.promptText,
    this.promptFont,
    this.promptSize,
  });

  final double? width;
  final double? height;
  final bool review;
  final String? promptText;
  final String? promptFont;
  final double? promptSize;

  @override
  State<WeasyVideoCapture> createState() => _WeasyVideoCaptureState();
}

class _WeasyVideoCaptureState extends State<WeasyVideoCapture>
    with WidgetsBindingObserver {
  WeasyCaptureController? _session = WeasyVideoCaptureStore.session;
  CameraController? get _camera => _session?.camera;
  VideoPlayerController? _player;
  String? _videoPath;
  String? _error;
  bool _recording = false;
  bool _paused = false;
  bool _busy = false;
  bool _finished = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final camera = WeasyVideoCaptureStore.camera;
    if (!widget.review && camera != null) {
      _recording = camera.value.isRecordingVideo;
      _paused = camera.value.isRecordingPaused;
    }
    if (widget.review) {
      _videoPath = WeasyVideoCaptureStore.path;
      if (_videoPath == null) {
        _error = 'Nem található elkészült felvétel.';
      } else {
        _initPlayer(_videoPath!);
      }
    } else {
      _initCamera();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed && _recording && !_paused) {
      _pauseForInterruption();
    }
  }

  Future<void> _pauseForInterruption() async {
    final camera = _camera;
    if (camera == null || _busy || !_recording || _paused) return;
    setState(() => _busy = true);
    try {
      await _session!.pause();
      if (mounted) setState(() => _paused = true);
    } catch (error) {
      if (mounted) {
        setState(() => _error =
            'A kamera megszakította a felvételt. A rögzítés folytatása nem biztosítható: $error');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _handleBack() async {
    if (_busy) return;
    if (_recording && !_paused) {
      final camera = _camera;
      if (camera == null || !camera.value.isRecordingVideo) return;
      setState(() => _busy = true);
      try {
        await _session!.pause();
        if (mounted) setState(() => _paused = true);
      } catch (error) {
        if (mounted) {
          setState(
              () => _error = 'A felvétel szüneteltetése nem sikerült: $error');
        }
        return;
      } finally {
        if (mounted) setState(() => _busy = false);
      }
    }
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _initCamera() async {
    try {
      var session = WeasyVideoCaptureStore.session;
      if (session == null) {
        final cameras = await availableCameras();
        if (cameras.isEmpty) throw StateError('Nem található kamera.');
        final description = cameras.firstWhere(
          (item) => item.lensDirection == CameraLensDirection.front,
          orElse: () => cameras.first,
        );
        session = await WeasyCaptureController.create(description);
        WeasyVideoCaptureStore.session = session;
      }
      if (!mounted) return;
      _session = session;
      session.phase.removeListener(_syncPhase);
      session.phase.addListener(_syncPhase);
      _syncPhase();
    } catch (error) {
      if (mounted) setState(() => _error = 'A kamera vagy a magyar motor nem indítható: $error');
    }
  }

  void _syncPhase() {
    if (!mounted || _session == null) return;
    final phase = _session!.phase.value;
    setState(() {
      _recording = _session!.hasPendingRecording;
      _paused = phase == WeasyCapturePhase.paused;
      if (_session!.lastError != null) _error = _session!.lastError;
    });
  }

  Future<void> _startRecording() async {
    final camera = _camera;
    if (camera == null || !camera.value.isInitialized || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (_recording && _paused) {
        await _session!.resume();
      } else {
        await _session!.start();
      }
      if (mounted) {
        setState(() {
          _recording = true;
          _paused = false;
        });
      }
    } catch (error) {
      if (mounted)
        setState(() => _error = 'A felvétel nem indítható el: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pauseRecording() async {
    final camera = _camera;
    if (camera == null || !_recording || _paused || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _session!.pause();
      if (mounted) setState(() => _paused = true);
    } catch (error) {
      if (mounted) {
        setState(
            () => _error = 'A felvétel szüneteltetése nem sikerült: $error');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _stopRecording() async {
    final session = _session;
    if (session == null || !session.hasPendingRecording || _busy) return;
    setState(() { _busy = true; _error = null; });
    try {
      final path = await session.finish(); // Audio + video, never the silent camera file.
      WeasyVideoCaptureStore.path = path;
      if (!mounted) return;
      setState(() { _videoPath = path; _recording = false; _paused = false; _finished = true; });
      final decision = await Navigator.of(context).push<bool>(
        MaterialPageRoute<bool>(builder: (_) => _WeasyReviewScreen(path: path)),
      );
      if (decision != null) {
        await session.cleanupAfterDecision();
        WeasyVideoCaptureStore.path = null;
        if (mounted) setState(() { _videoPath = null; _finished = false; });
      }
    } catch (error) {
      if (mounted) setState(() => _error = 'A véglegesítés nem sikerült; a fájlokat megőriztük: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _initPlayer(String path) async {
    try {
      final player = VideoPlayerController.file(File(path));
      await player.initialize();
      if (!mounted) {
        await player.dispose();
        return;
      }
      setState(() => _player = player);
    } catch (error) {
      if (mounted) setState(() => _error = 'A videó nem nyitható meg: $error');
    }
  }

  Future<void> _deleteCurrentRecording() async {
    final path = WeasyVideoCaptureStore.path;
    final player = _player;
    if (player != null) {
      await player.pause();
      await player.dispose();
      _player = null;
      _player = null;
    }
    if (path != null) {
      final file = File(path);
      if (await file.exists()) await file.delete();
    }
    WeasyVideoCaptureStore.path = null;
    _videoPath = null;
    _finished = false;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _session?.phase.removeListener(_syncPhase);
    _player?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final camera = _camera;
    final player = _player;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) _handleBack();
      },
      child: SizedBox(
        width: widget.width,
        height: widget.height,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (widget.review && player != null && player.value.isInitialized)
              GestureDetector(
                onTap: () => setState(() =>
                    player.value.isPlaying ? player.pause() : player.play()),
                child: Center(
                  child: AspectRatio(
                    aspectRatio: player.value.aspectRatio,
                    child: VideoPlayer(player),
                  ),
                ),
              )
            else if (!widget.review && camera?.value.isInitialized == true)
              CameraPreview(camera!)
            else
              const Center(child: CircularProgressIndicator()),
            if (!widget.review && _session != null)
              Positioned(
                left: 12, right: 56, top: 8,
                child: SafeArea(bottom: false, child: WeasyPrompter(
                  controller: _session!, text: widget.promptText ?? '',
                  fontFamily: widget.promptFont?.isNotEmpty == true ? widget.promptFont! : 'Inter',
                  fontSize: (widget.promptSize ?? 24).clamp(10, 96).toDouble(),
                  height: 230,
                  onError: (message) { if (mounted) setState(() => _error = message); },
                )),
              ),
            if (!widget.review)
              Positioned(right: 4, top: 8, child: SafeArea(bottom: false,
                child: IconButton(onPressed: _busy ? null : _handleBack,
                  tooltip: 'Vissza', icon: const Icon(Icons.arrow_back, color: Colors.white, size: 22)))),

            if (!widget.review)
              Positioned(
                left: 0,
                right: 0,
                bottom: 24,
                child: Center(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextButton.icon(
                        onPressed: _busy || !_recording
                            ? null
                            : (_paused ? _startRecording : _pauseRecording),
                        icon: Icon(_paused
                            ? Icons.play_arrow_rounded
                            : Icons.pause_rounded),
                        label: Text(_paused ? 'Folytatás' : 'Szünet'),
                      ),
                      const SizedBox(width: 8),
                      FilledButton.icon(
                        onPressed: _busy
                            ? null
                            : (_recording ? _stopRecording : _startRecording),
                        icon: Icon(_recording
                            ? Icons.stop_rounded
                            : Icons.fiber_manual_record_rounded),
                        label: Text(_recording ? 'Befejezés' : 'FELVÉTEL'),
                      ),
                    ],
                  ),
                ),
              ),
            if (_error != null)
              Positioned(
                left: 16,
                right: 16,
                bottom: 8,
                child: Material(
                  color: Colors.black87,
                  borderRadius: BorderRadius.circular(8),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(_error!,
                        style: const TextStyle(color: Colors.white)),
                  ),
                ),
              ),
            if (widget.review && player != null && player.value.isInitialized)
              Positioned(
                left: 12,
                right: 12,
                bottom: 12,
                child: VideoProgressIndicator(player, allowScrubbing: true),
              ),
          ],
        ),
      ),
    );
  }
}

class WeasyVideoCaptureStore {
  static String? path;
  static WeasyCaptureController? session;
  static CameraController? get camera => session?.camera;
}

class _WeasyReviewScreen extends StatefulWidget {
  const _WeasyReviewScreen({required this.path});

  final String path;

  @override
  State<_WeasyReviewScreen> createState() => _WeasyReviewScreenState();
}

class _WeasyReviewScreenState extends State<_WeasyReviewScreen> {
  VideoPlayerController? _player;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _initPlayer();
  }

  Future<void> _initPlayer() async {
    try {
      final player = VideoPlayerController.file(File(widget.path));
      await player.initialize();
      if (!mounted) {
        await player.dispose();
        return;
      }
      setState(() => _player = player);
    } catch (error) {
      if (mounted) setState(() => _error = 'A videó nem nyitható meg: $error');
    }
  }

  Future<void> _discard() async {
    if (_busy) return;
    final confirmed = await showDialog<bool>(context: context, builder: (dialog) => AlertDialog(
      title: const Text('Biztosan elveted a felvételt?'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(dialog, false), child: const Text('Mégse')),
        TextButton(onPressed: () => Navigator.pop(dialog, true), child: const Text('Elvetés')),
      ],
    ));
    if (confirmed != true || !mounted) return;
    setState(() => _busy = true);
    final player = _player;
    if (player != null) {
      await player.pause();
      await player.dispose();
      _player = null;
    }
    final file = File(widget.path);
    if (await file.exists()) await file.delete();
    WeasyVideoCaptureStore.path = null;
    if (mounted) Navigator.of(context).pop(true);
  }

  Future<void> _save() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (!await Gal.hasAccess()) await Gal.requestAccess();
      await Gal.putVideo(widget.path, album: 'Weasy');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('A felvétel elmentve a galériába.')),
      );
      await _player?.pause();
      await _player?.dispose();
      _player = null;
      WeasyVideoCaptureStore.path = null;
      final savedFile = File(widget.path);
      if (await savedFile.exists()) await savedFile.delete();
      Navigator.of(context).pop(false);
    } catch (error) {
      if (mounted)
        setState(() =>
            _error = 'A galériamentés nem sikerült. Próbáld újra. ($error)');
    } finally {
      if (mounted && _player != null) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _player?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final player = _player;
    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: const Color(0xFF041622),
        appBar: AppBar(
          automaticallyImplyLeading: false,
          backgroundColor: const Color(0xFF1A1A1A),
          foregroundColor: Colors.white,
          title: const Text('Felvétel ellenőrzése'),
        ),
        body: SafeArea(
          child: Column(
            children: [
              Expanded(
                child: player != null && player.value.isInitialized
                    ? GestureDetector(
                        onTap: () => setState(() => player.value.isPlaying
                            ? player.pause()
                            : player.play()),
                        child: Center(
                          child: AspectRatio(
                            aspectRatio: player.value.aspectRatio,
                            child: VideoPlayer(player),
                          ),
                        ),
                      )
                    : Center(
                        child: _error == null
                            ? const CircularProgressIndicator()
                            : Text(_error!,
                                style: const TextStyle(color: Colors.white)),
                      ),
              ),
              if (player != null && player.value.isInitialized)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: VideoProgressIndicator(player, allowScrubbing: true),
                ),
              const Padding(
                padding: EdgeInsets.all(20),
                child: Text(
                  'Megtartod a felvételt?',
                  style: TextStyle(color: Colors.white, fontSize: 20),
                ),
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Text(_error!,
                      style: const TextStyle(color: Colors.redAccent)),
                ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    OutlinedButton.icon(
                      onPressed: _busy ? null : _discard,
                      icon: const Icon(Icons.delete_outline),
                      label: const Text('Elvetés'),
                    ),
                    const SizedBox(width: 12),
                    FilledButton.icon(
                      onPressed: _busy ? null : _save,
                      icon: const Icon(Icons.save_alt),
                      label: Text(_busy ? 'Mentés...' : 'Mentés'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
