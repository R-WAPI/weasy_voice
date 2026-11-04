package hu.weasy.hangproba;

import android.content.Context;

/** Rolling-window Hungarian Whisper inference on the same captured PCM as the video. */
public final class SpeechInput {
    public interface Listener {
        void words(SpeechInput source, String text, boolean complete);
        void ended(SpeechInput source, String reason, boolean failed);
    }
    private final Listener listener;
    private final AudioWindow window = new AudioWindow(16000 * 3);
    private volatile boolean open = true;
    private boolean inputDone, queued, ended;
    private long lastProcessed, lastStartMs;
    private int decoderFailures;
    public volatile long inferenceMs;

    public SpeechInput(Context context, Listener listener) {
        if (!LocalModel.ready()) throw new IllegalStateException("A magyar felismerő még töltődik.");
        this.listener = listener;
    }
    public void start() { /* Audio comes only from offer(); no microphone is opened here. */ }
    public synchronized boolean offer(byte[] bytes, int count) {
        if (!open || inputDone) return false;
        window.offer(bytes, count);
        schedule(); return true;
    }
    public synchronized void finishInput() { inputDone = true; schedule(); }
    private synchronized void schedule() {
        if (!open || queued || ended) return;
        long total = window.total();
        if (total < 16000) { if (inputDone) finish(); return; }
        if (total == lastProcessed) { if (inputDone) finish(); return; }
        long now = android.os.SystemClock.elapsedRealtime();
        if (!inputDone && (total - lastProcessed < 4000 || now - lastStartMs < 180)) return;
        queued = true;
        LocalModel.inference.execute(this::decode);
    }
    private void decode() {
        AudioWindow.Snapshot snapshot;
        synchronized (this) {
            if (!open) { queued = false; return; }
            snapshot = window.snapshot();
            lastStartMs = android.os.SystemClock.elapsedRealtime();
        }
        try {
            // Voice activity is only an inference gate; it never advances the text.
            boolean pendingVoice = snapshot.lastVoice > lastProcessed &&
                snapshot.lastVoice > snapshot.total - snapshot.samples.length;
            String recognized = (snapshot.voiced || pendingVoice)
                ? LocalModel.nativeDecode(LocalModel.handle, snapshot.samples).trim() : "";
            long elapsed = android.os.SystemClock.elapsedRealtime() - lastStartMs;
            inferenceMs = elapsed;
            if (open && !recognized.isEmpty()) {
                final String words = recognized;
                LocalModel.ui.post(() -> { if (open) listener.words(this, words, false); });
            }
            if (open && elapsed > 12000) {
                LocalModel.ui.post(() -> { if (open) listener.ended(this, "A felismerés túl lassú ezen a telefonon (12 másodperc feletti feldolgozás).", true); });
                synchronized (this) { ended = true; }
            }
        } catch (Throwable e) {
            decoderFailures++;
            if (open && decoderFailures >= 2) {
                LocalModel.ui.post(() -> { if (open) listener.ended(this, "A saját magyar felismerő hibát adott: " + e, true); });
                synchronized (this) { ended = true; }
            }
        } finally {
            synchronized (this) {
                lastProcessed = snapshot.total;
                queued = false;
                if (open) schedule();
            }
        }
    }
    private synchronized void finish() {
        if (ended) return;
        ended = true;
        LocalModel.ui.post(() -> { if (open) listener.ended(this, "A magyar hangpróba feldolgozása befejeződött.", false); });
    }
    public synchronized void close() {
        if (!open) return;
        open = false;
        LocalModel.nativeCancel(LocalModel.handle);
    }
}
