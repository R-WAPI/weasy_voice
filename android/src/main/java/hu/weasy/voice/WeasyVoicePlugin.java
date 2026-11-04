package hu.weasy.voice;

import android.Manifest;
import android.app.Activity;
import android.content.Context;
import android.content.pm.PackageManager;
import android.os.Handler;
import android.os.Looper;
import hu.weasy.hangproba.AudioMux;
import hu.weasy.hangproba.LocalModel;
import io.flutter.embedding.engine.plugins.FlutterPlugin;
import io.flutter.embedding.engine.plugins.activity.ActivityAware;
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding;
import io.flutter.plugin.common.EventChannel;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;
import io.flutter.plugin.common.PluginRegistry.RequestPermissionsResultListener;
import java.io.File;
import java.util.HashMap;
import java.util.Map;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

public final class WeasyVoicePlugin implements FlutterPlugin, ActivityAware,
        MethodChannel.MethodCallHandler, EventChannel.StreamHandler, RequestPermissionsResultListener {
    private static final Object OWNERS = new Object();
    private static WeasyVoicePlugin microphoneOwner;
    private static int modelUsers;
    private final Handler ui = new Handler(Looper.getMainLooper());
    private final ExecutorService files = Executors.newSingleThreadExecutor();
    private FlutterPluginBinding binding;
    private ActivityPluginBinding activityBinding;
    private Context context;
    private MethodChannel methods;
    private EventChannel stream;
    private EventChannel.EventSink sink;
    private MethodChannel.Result permissionResult;
    private CaptureAudio session;
    private boolean attached, stopping;
    private File directory;

    @Override public void onAttachedToEngine(FlutterPluginBinding b) {
        binding = b; context = b.getApplicationContext(); attached = true;
        directory = new File(context.getCacheDir(), "weasy_voice");
        methods = new MethodChannel(b.getBinaryMessenger(), "weasy_voice/methods");
        stream = new EventChannel(b.getBinaryMessenger(), "weasy_voice/events");
        methods.setMethodCallHandler(this); stream.setStreamHandler(this);
        synchronized (OWNERS) { modelUsers++; }
    }
    private void emit(Map<String,Object> value) {
        ui.post(() -> { if (attached && sink != null) sink.success(value); });
    }
    private void error(MethodChannel.Result result, String code, Exception error) {
        if (attached) result.error(code, error.toString(), null);
    }
    @Override public void onMethodCall(MethodCall call, MethodChannel.Result result) {
        try {
            switch (call.method) {
                case "initialize": {
                    String asset = binding.getFlutterAssets().getAssetFilePathBySubpath("assets/ggml-base-q5_1.bin", "weasy_voice");
                    LocalModel.initialize(context, asset, (ready, message) -> {
                        if (!attached) return;
                        if (ready) result.success(message); else result.error("MODEL", message, null);
                    });
                    break;
                }
                case "microphonePermission": {
                    if (context.checkSelfPermission(Manifest.permission.RECORD_AUDIO) == PackageManager.PERMISSION_GRANTED) {
                        result.success(true); break;
                    }
                    if (activityBinding == null) { result.error("ACTIVITY", "Nincs aktív Android képernyő.", null); break; }
                    if (permissionResult != null) { result.error("BUSY", "Engedélykérés folyamatban.", null); break; }
                    permissionResult = result;
                    activityBinding.getActivity().requestPermissions(new String[]{Manifest.permission.RECORD_AUDIO}, 6173);
                    break;
                }
                case "startAudio": {
                    if (!LocalModel.ready()) throw new Exception("A magyar modell nincs betöltve.");
                    if (context.checkSelfPermission(Manifest.permission.RECORD_AUDIO) != PackageManager.PERMISSION_GRANTED)
                        throw new Exception("Hiányzó mikrofonengedély.");
                    if (session != null || stopping) throw new Exception("Már van aktív hangrögzítés.");
                    if (!directory.exists() && !directory.mkdirs()) throw new Exception("Nem hozható létre a hangkönyvtár.");
                    synchronized (OWNERS) {
                        if (microphoneOwner != null && microphoneOwner != this) throw new Exception("Másik Weasy-képernyő használja a mikrofont.");
                        microphoneOwner = this;
                    }
                    File target = new File(directory, "audio-" + System.nanoTime() + ".pcm");
                    CaptureAudio created = new CaptureAudio(context, target, System.nanoTime(), this::emit);
                    try { long revision = created.start(); session = created; result.success(revision); }
                    catch (Exception e) { synchronized (OWNERS) { microphoneOwner = null; } throw e; }
                    break;
                }
                case "pauseAudio": requireSession(); result.success(session.pause()); break;
                case "resumeAudio": requireSession(); result.success(session.resume()); break;
                case "resetRecognition": requireSession(); result.success(session.resetRecognizer()); break;
                case "suspendRecognition": requireSession(); result.success(session.suspendRecognizer()); break;
                case "stopAudio": {
                    requireSession(); stopping = true;
                    CaptureAudio current = session; current.closeRecognizer();
                    files.execute(() -> {
                        try {
                            Map<String,Object> stopped = current.stop();
                            ui.post(() -> {
                                if (session == current) session = null;
                                stopping = false;
                                synchronized (OWNERS) { if (microphoneOwner == this) microphoneOwner = null; }
                                if (attached) result.success(stopped);
                            });
                        } catch (Exception e) { ui.post(() -> { stopping = false; error(result, "STOP", e); }); }
                    });
                    break;
                }
                case "finalizeVideo": {
                    String videoPath = call.argument("videoPath");
                    String audioPath = call.argument("audioPath");
                    Number offset = call.argument("audioOffsetUs");
                    if (videoPath == null || audioPath == null) throw new Exception("Hiányzó videó- vagy hangfájl.");
                    File audio = managedFile(audioPath);
                    File video = new File(videoPath);
                    if (!video.isFile() || !audio.isFile()) throw new Exception("Hiányzó rögzített fájl.");
                    File output = new File(directory, "video-" + System.nanoTime() + ".mp4");
                    files.execute(() -> {
                        try {
                            AudioMux.create(video, audio, output, offset == null ? 0 : offset.longValue());
                            ui.post(() -> { if (attached) result.success(output.getAbsolutePath()); });
                        } catch (Exception e) { ui.post(() -> error(result, "MUX", e)); }
                    });
                    break;
                }
                case "deleteTemporary": {
                    if (session != null || stopping) throw new Exception("Rögzítés közben nem törölhető ideiglenes fájl.");
                    String path = call.argument("path");
                    if (path == null) throw new Exception("Hiányzó fájlútvonal.");
                    File file = managedFile(path);
                    if (file.exists() && !file.delete()) throw new Exception("Az ideiglenes fájl nem törölhető.");
                    result.success(null); break;
                }
                default: result.notImplemented();
            }
        } catch (Exception e) { result.error("WEASY", e.toString(), null); }
    }
    private void requireSession() throws Exception {
        if (session == null || stopping) throw new Exception("Nincs elérhető aktív hangrögzítés.");
    }
    private File managedFile(String path) throws Exception {
        File file = new File(path).getCanonicalFile();
        String root = directory.getCanonicalPath() + File.separator;
        if (!file.getPath().startsWith(root)) throw new Exception("Ez nem a Weasy ideiglenes fájlja.");
        return file;
    }
    @Override public void onListen(Object arguments, EventChannel.EventSink events) { sink = events; }
    @Override public void onCancel(Object arguments) { sink = null; }
    @Override public boolean onRequestPermissionsResult(int request, String[] p, int[] grants) {
        if (request != 6173 || permissionResult == null) return false;
        permissionResult.success(grants.length > 0 && grants[0] == PackageManager.PERMISSION_GRANTED);
        permissionResult = null; return true;
    }
    @Override public void onAttachedToActivity(ActivityPluginBinding b) {
        activityBinding = b; b.addRequestPermissionsResultListener(this);
    }
    private void detachActivity() {
        if (activityBinding != null) activityBinding.removeRequestPermissionsResultListener(this);
        activityBinding = null;
        if (permissionResult != null) { permissionResult.success(false); permissionResult = null; }
    }
    @Override public void onDetachedFromActivityForConfigChanges() { detachActivity(); }
    @Override public void onReattachedToActivityForConfigChanges(ActivityPluginBinding b) { onAttachedToActivity(b); }
    @Override public void onDetachedFromActivity() { detachActivity(); }
    @Override public void onDetachedFromEngine(FlutterPluginBinding b) {
        attached = false; sink = null; methods.setMethodCallHandler(null); stream.setStreamHandler(null);
        detachActivity();
        CaptureAudio current = session; session = null;
        if (current != null) {
            current.closeRecognizer();
            files.execute(() -> { try { current.stop(); } catch (Exception ignored) {}
                synchronized (OWNERS) { if (microphoneOwner == this) microphoneOwner = null; } });
        }
        files.shutdown();
        synchronized (OWNERS) { if (--modelUsers == 0) LocalModel.releaseModel(); }
    }
}
