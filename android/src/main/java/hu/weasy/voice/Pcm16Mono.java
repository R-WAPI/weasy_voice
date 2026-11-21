package hu.weasy.voice;

import java.io.ByteArrayOutputStream;

/** Streaming area resampler for the STT copy only. Preserves phase across input buffers. */
final class Pcm16Mono {
    private int rate, channels, filled;
    private double weighted;
    void reset() { rate = channels = filled = 0; weighted = 0; }
    byte[] convert(byte[] input, int inputRate, int inputChannels) {
        if (inputRate <= 0 || inputChannels <= 0 || input.length % (2 * inputChannels) != 0)
            throw new IllegalArgumentException("Érvénytelen PCM formátum.");
        if (rate != inputRate || channels != inputChannels) {
            reset(); rate = inputRate; channels = inputChannels;
        }
        ByteArrayOutputStream output = new ByteArrayOutputStream();
        for (int offset = 0; offset < input.length; offset += channels * 2) {
            double mono = 0;
            for (int channel = 0; channel < channels; channel++) {
                int p = offset + channel * 2;
                mono += (short) ((input[p] & 255) | ((input[p + 1] & 255) << 8));
            }
            mono /= channels;
            int remaining = 16000;
            while (remaining > 0) {
                int used = Math.min(remaining, rate - filled);
                weighted += mono * used; filled += used; remaining -= used;
                if (filled == rate) {
                    int sample = (int) Math.round(weighted / rate);
                    output.write(sample & 255); output.write((sample >> 8) & 255);
                    filled = 0; weighted = 0;
                }
            }
        }
        return output.toByteArray();
    }
}
