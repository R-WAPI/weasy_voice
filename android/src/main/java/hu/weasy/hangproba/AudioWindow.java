package hu.weasy.hangproba;

/** Fixed-size PCM16 ring. Caller serializes access. */
public final class AudioWindow {
    private final float[] ring;
    private long total, lastVoice;
    private int cursor, count;
    public AudioWindow(int capacity) { ring = new float[capacity]; }
    public long total() { return total; }
    public void offer(byte[] bytes, int length) {
        if (length < 0 || length > bytes.length || (length & 1) != 0) throw new IllegalArgumentException("PCM16 length");
        double energy = 0;
        for (int i = 0; i < length; i += 2) {
            short pcm = (short)((bytes[i] & 255) | (bytes[i + 1] << 8));
            // Recognition-only +40% amplitude; original PCM/video audio is untouched.
            float value = Math.max(-1f, Math.min(1f, (pcm / 32768f) * 1.40f));
            ring[cursor] = value;
            cursor = (cursor + 1) % ring.length;
            count = Math.min(count + 1, ring.length); total++;
            energy += value * value;
        }
        if (length > 0 && Math.sqrt(energy / (length / 2)) > 0.003) lastVoice = total;
    }
    public Snapshot snapshot() {
        float[] samples = new float[count];
        int start = (cursor - count + ring.length) % ring.length;
        for (int i = 0; i < count; i++) samples[i] = ring[(start + i) % ring.length];
        return new Snapshot(samples, total, lastVoice, lastVoice > 0 && total - lastVoice < 24000);
    }
    public static final class Snapshot {
        public final float[] samples;
        public final long total;
        public final long lastVoice;
        public final boolean voiced;
        Snapshot(float[] samples, long total, long lastVoice, boolean voiced) { this.samples = samples; this.total = total; this.lastVoice = lastVoice; this.voiced = voiced; }
    }
}
