package hu.weasy.voice;

import android.content.Context;
import hu.weasy.camerax.PcmTap;
import hu.weasy.hangproba.SpeechInput;
import java.util.HashMap;
import java.util.Map;
import java.util.concurrent.ArrayBlockingQueue;
import java.util.concurrent.TimeUnit;

/** Consumes a bounded copy queue. CameraX alone owns the microphone and saved A/V file. */
final class SharedRecognition implements PcmTap.Listener, SpeechInput.Listener {
    private final Context context;
    private final CaptureAudio.Events events;
    private final ArrayBlockingQueue<Packet> queue = new ArrayBlockingQueue<>(32);
    private final Object lock = new Object();
    private final Pcm16Mono converter = new Pcm16Mono();
    private final SpeechOnset onset = new SpeechOnset();
    private volatile boolean running = true, paused;
    private volatile long revision = 1;
    private volatile SpeechInput speech;
    private volatile boolean overflow;
    private int lastOnsetReport = -1000;
    private Thread worker;
    private static final class Packet {
        final byte[] data; final int rate, channels; final long revision;
        Packet(byte[] data, int rate, int channels, long revision) {
            this.data = data; this.rate = rate; this.channels = channels; this.revision = revision;
        }
    }
    SharedRecognition(Context context, CaptureAudio.Events events) {
        this.context = context; this.events = events;
    }
    long start() {
        speech = new SpeechInput(context, this); speech.start();
        PcmTap.attach(this);
        worker = new Thread(this::consume, "weasy-shared-recognition");
        worker.start(); return revision;
    }
    @Override public void offer(byte[] pcm, int rate, int channels) {
        // Called on CameraX's audio thread: no inference, resampling, file IO or blocking here.
        if (running && !paused && speech != null && !queue.offer(new Packet(pcm, rate, channels, revision)))
            overflow = true;
    }
    private void consume() {
        long processedRevision = -1;
        try {
            while (running) {
                Packet packet = queue.poll(100, TimeUnit.MILLISECONDS);
                if (packet == null) continue;
                synchronized (lock) {
                    if (!running || paused || packet.revision != revision || speech == null) continue;
                    if (overflow) {
                        // Drop stale recognition history rather than joining words across a gap.
                        overflow = false; queue.clear(); speech.close();
                        speech = new SpeechInput(context, this); speech.start();
                        converter.reset(); onset.reset(); lastOnsetReport = -1000;
                        continue;
                    }
                    if (processedRevision != revision) {
                        converter.reset(); onset.reset(); lastOnsetReport = -1000;
                        processedRevision = revision;
                    }
                    byte[] mono = converter.convert(packet.data, packet.rate, packet.channels);
                    if (mono.length == 0) continue;
                    int elapsed = onset.offer(mono, mono.length);
                    if (elapsed >= 0 && elapsed <= 3000 && elapsed - lastOnsetReport >= 100) {
                        lastOnsetReport = elapsed;
                        Map<String,Object> data = event("speechOnset");
                        data.put("speechElapsedMs", elapsed); events.event(data);
                    }
                    speech.offer(mono, mono.length);
                }
            }
        } catch (InterruptedException ignored) {
            Thread.currentThread().interrupt();
        } catch (Exception e) {
            Map<String,Object> data = event("recognitionError");
            data.put("message", e.toString()); events.event(data);
        }
    }
    private Map<String,Object> event(String type) {
        Map<String,Object> data = new HashMap<>();
        data.put("type", type); data.put("revision", revision); return data;
    }
    long pause() { synchronized (lock) { paused = true; return reset(false); } }
    long resume() { synchronized (lock) { paused = false; return reset(true); } }
    long resetRecognition() { synchronized (lock) { return reset(!paused); } }
    long suspendRecognition() { synchronized (lock) { return reset(false); } }
    private long reset(boolean start) {
        revision++; queue.clear(); overflow = false;
        if (speech != null) speech.close();
        speech = null;
        if (running && start) { speech = new SpeechInput(context, this); speech.start(); }
        return revision;
    }
    void stop() {
        PcmTap.detach(this);
        synchronized (lock) { running = false; reset(false); }
        if (worker != null) worker.interrupt();
    }
    @Override public void words(SpeechInput source, String text, boolean complete) {
        synchronized (lock) {
            if (!running || paused || source != speech) return;
            Map<String,Object> data = event("transcript"); data.put("text", text);
            data.put("inferenceMs", source.inferenceMs); events.event(data);
        }
    }
    @Override public void ended(SpeechInput source, String reason, boolean failed) {
        synchronized (lock) {
            if (!running || source != speech) return;
            speech = null; source.close();
            Map<String,Object> data = event("recognitionError"); data.put("message", reason); events.event(data);
        }
    }
}
