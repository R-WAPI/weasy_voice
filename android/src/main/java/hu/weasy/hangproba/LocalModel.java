package hu.weasy.hangproba;

import android.content.Context;
import android.os.Handler;
import android.os.Looper;
import java.io.File;
import java.io.FileInputStream;
import java.io.FileOutputStream;
import java.io.InputStream;
import java.security.MessageDigest;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

/** One native context, one inference executor. No Android system recognizer or network. */
public final class LocalModel {
    static final ExecutorService inference = Executors.newSingleThreadExecutor(r -> new Thread(() -> {
        android.os.Process.setThreadPriority(android.os.Process.THREAD_PRIORITY_BACKGROUND);
        r.run();
    }, "weasy-whisper-cpu"));
    static final Handler ui = new Handler(Looper.getMainLooper());
    static volatile long handle;
    static volatile String failure;
    private static final String MODEL = "ggml-base-q5_1.bin";
    private static final String HASH = "a3733eda680ef76256db5fc5dd9de8629e62c5e7";
    public interface Ready { void result(boolean ready, String message); }
    static native long nativeLoad(String path);
    static native String nativeDecode(long handle, float[] audio);
    static native void nativeCancel(long handle);
    private static native void nativeFree(long handle);

    public static boolean ready() { return handle != 0; }
    public static void releaseModel() {
        inference.execute(() -> {
            long old = handle;
            handle = 0;
            if (old != 0) nativeFree(old);
        });
    }
    public static void initialize(Context context, Ready callback) {
        initialize(context, MODEL, callback);
    }
    public static void initialize(Context context, String assetPath, Ready callback) {
        final Context app = context.getApplicationContext();
        inference.execute(() -> {
            if (handle != 0) { ui.post(() -> callback.result(true, "Saját magyar Whisper felismerő: készen áll.")); return; }
            try {
                System.loadLibrary("weasy_whisper");
                File target = new File(app.getFilesDir(), MODEL);
                if (!target.exists() || !HASH.equals(sha1(target))) {
                    File temporary = new File(app.getFilesDir(), MODEL + ".tmp");
                    try (InputStream in = app.getAssets().open(assetPath); FileOutputStream out = new FileOutputStream(temporary)) {
                        byte[] buffer = new byte[65536]; int n;
                        while ((n = in.read(buffer)) > 0) out.write(buffer, 0, n);
                    }
                    if (!HASH.equals(sha1(temporary))) throw new Exception("A beépített modell ellenőrzőösszege hibás.");
                    if (target.exists() && !target.delete()) throw new Exception("A régi modell nem cserélhető.");
                    if (!temporary.renameTo(target)) throw new Exception("A modell nem menthető az alkalmazás tárhelyére.");
                }
                handle = nativeLoad(target.getAbsolutePath());
                if (handle == 0) throw new Exception("A modell betöltése sikertelen.");
                failure = null;
                ui.post(() -> callback.result(true, "Saját magyar Whisper felismerő kész. Indíthatod a Felvételt."));
            } catch (Throwable e) {
                failure = e.toString();
                ui.post(() -> callback.result(false, "Felismerő betöltési hiba: " + failure));
            }
        });
    }
    private static String sha1(File file) throws Exception {
        MessageDigest digest = MessageDigest.getInstance("SHA-1");
        try (FileInputStream in = new FileInputStream(file)) {
            byte[] buffer = new byte[65536]; int n;
            while ((n = in.read(buffer)) > 0) digest.update(buffer, 0, n);
        }
        StringBuilder hex = new StringBuilder();
        for (byte b : digest.digest()) hex.append(String.format(java.util.Locale.ROOT, "%02x", b & 255));
        return hex.toString();
    }
}
