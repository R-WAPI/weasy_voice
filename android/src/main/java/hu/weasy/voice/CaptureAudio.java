package hu.weasy.voice;

import android.content.Context;
import android.media.AudioFormat;
import android.media.AudioRecord;
import android.media.MediaRecorder;
import hu.weasy.hangproba.SpeechInput;
import java.io.BufferedOutputStream;
import java.io.File;
import java.io.FileOutputStream;
import java.util.HashMap;
import java.util.Map;

/** The single microphone owner. Flutter's camera must record with enableAudio=false. */
final class CaptureAudio implements SpeechInput.Listener {
    interface Events { void event(Map<String,Object> data); }
    private final Context context;
    private final Events events;
    private final Object lock = new Object();
    private final File path;
    private final long videoStartNs;
    private AudioRecord microphone;
    private Thread reader;
    private volatile boolean running, paused;
    private volatile SpeechInput speech;
    private volatile String failure;
    private volatile long firstSampleNs, bytesWritten;
    private long revision;

    CaptureAudio(Context context, File path, long videoStartNs, Events events) {
        this.context = context; this.path = path; this.videoStartNs = videoStartNs; this.events = events;
    }
    long start() throws Exception {
        int minimum = AudioRecord.getMinBufferSize(16000, AudioFormat.CHANNEL_IN_MONO, AudioFormat.ENCODING_PCM_16BIT);
        if (minimum <= 0) throw new Exception("A 16 kHz PCM16 formátum nem támogatott.");
        microphone = new AudioRecord(MediaRecorder.AudioSource.MIC, 16000, AudioFormat.CHANNEL_IN_MONO,
            AudioFormat.ENCODING_PCM_16BIT, Math.max(minimum * 2, 6400));
        if (microphone.getState() != AudioRecord.STATE_INITIALIZED) {
            microphone.release(); microphone = null; throw new Exception("A mikrofon nem inicializálható.");
        }
        BufferedOutputStream opened = null;
        try {
            opened = new BufferedOutputStream(new FileOutputStream(path), 65536);
            microphone.startRecording();
        } catch (Exception e) {
            if (opened != null) try { opened.close(); } catch (Exception ignored) {}
            microphone.release(); microphone = null; throw e;
        }
        final BufferedOutputStream out = opened;
        running = true;
        try { resetRecognizer(); }
        catch (Exception e) {
            running = false;
            try { microphone.stop(); } catch (Exception ignored) {}
            microphone.release(); microphone = null;
            try { out.close(); } catch (Exception ignored) {}
            throw e;
        }
        final AudioRecord source = microphone;
        reader = new Thread(() -> {
            android.os.Process.setThreadPriority(android.os.Process.THREAD_PRIORITY_AUDIO);
            try (BufferedOutputStream output = out) {
                byte[] buffer = new byte[640];
                while (running) {
                    int n = source.read(buffer, 0, buffer.length, AudioRecord.READ_BLOCKING);
                    if (n < 0 && !running) break;
                    if (n < 0) throw new Exception("AudioRecord.read: " + n);
                    if (n == 0) continue;
                    synchronized (lock) {
                        if (!running || paused) continue;
                        if (firstSampleNs == 0) firstSampleNs = System.nanoTime() - n * 1_000_000_000L / 32000;
                        output.write(buffer, 0, n); bytesWritten += n;
                        SpeechInput current = speech;
                        if (current != null) current.offer(buffer, n);
                    }
                }
            } catch (Exception e) {
                failure = e.toString(); running = false;
                Map<String,Object> data = new HashMap<>();
                data.put("type", "captureError"); data.put("message", failure); events.event(data);
            }
        }, "weasy-voice-microphone");
        reader.start();
        return revision;
    }
    long pause() {
        SpeechInput old;
        synchronized (lock) { paused = true; old = speech; speech = null; revision++; }
        if (old != null) old.close();
        return revision;
    }
    long resume() {
        synchronized (lock) { paused = false; }
        long result = resetRecognizer();
        return result;
    }
    long resetRecognizer() {
        SpeechInput old;
        synchronized (lock) { old = speech; speech = null; revision++; }
        if (old != null) old.close();
        if (running && !paused) {
            SpeechInput replacement = new SpeechInput(context, this);
            synchronized (lock) { speech = replacement; }
            replacement.start();
        }
        return revision;
    }
    Map<String,Object> stop() throws Exception {
        running = false;
        if (microphone != null) { try { microphone.stop(); } catch (Exception ignored) {} }
        if (reader != null) {
            reader.join(5000);
            if (reader.isAlive()) throw new Exception("A mikrofon leállítása nem fejeződött be.");
        }
        if (microphone != null) microphone.release();
        microphone = null;
        Map<String,Object> result = new HashMap<>();
        result.put("audioPath", path.getAbsolutePath());
        result.put("audioOffsetUs", firstSampleNs == 0 ? 0 : Math.max(0, (firstSampleNs - videoStartNs) / 1000));
        result.put("durationUs", bytesWritten * 1_000_000L / 32000);
        if (failure != null) result.put("warning", failure);
        return result;
    }
    void closeRecognizer() {
        SpeechInput old;
        synchronized (lock) { old = speech; speech = null; revision++; }
        if (old != null) old.close();
    }
    long suspendRecognizer() { closeRecognizer(); return revision; }
    @Override public void words(SpeechInput source, String text, boolean complete) {
        Map<String,Object> data = new HashMap<>();
        synchronized (lock) {
            if (source != speech || paused || !running) return;
            data.put("type", "transcript"); data.put("text", text);
            data.put("revision", revision); data.put("inferenceMs", source.inferenceMs);
        }
        events.event(data);
    }
    @Override public void ended(SpeechInput source, String reason, boolean failed) {
        if (source != speech) return;
        synchronized (lock) { speech = null; }
        source.close();
        Map<String,Object> data = new HashMap<>();
        data.put("type", "recognitionError"); data.put("message", reason);
        data.put("revision", revision); events.event(data);
    }
}
