package hu.weasy.voice;

/** Lightweight energy gate on the existing PCM stream; not a speech recognizer. */
final class SpeechOnset {
    private double samples, loudSamples, onset = -1;
    private double noise = 120;
    void reset() { samples = 0; loudSamples = 0; onset = -1; noise = 120; }
    int offer(byte[] pcm, int length) {
        int count = length / 2;
        if (count == 0) return elapsedMs();
        double energy = 0;
        for (int i = 0; i < count; i++) {
            int value = (short)((pcm[2*i] & 255) | (pcm[2*i+1] << 8));
            energy += (double)value * value;
        }
        double rms = Math.sqrt(energy / count);
        samples += count;
        if (onset < 0) {
            if (rms > Math.max(450, noise * 3)) {
                loudSamples += count;
                if (loudSamples >= 1920) onset = samples - loudSamples; // 120 ms, reject clicks.
            } else {
                loudSamples = 0;
                noise += (Math.min(rms, 450) - noise) * 0.02;
            }
        }
        return elapsedMs();
    }
    private int elapsedMs() { return onset < 0 ? -1 : (int)((samples - onset) / 16); }
}
