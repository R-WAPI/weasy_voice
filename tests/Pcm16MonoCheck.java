package hu.weasy.voice;

import java.io.ByteArrayOutputStream;
import java.util.Arrays;

public final class Pcm16MonoCheck {
    static void check(boolean condition, String message) { if (!condition) throw new AssertionError(message); }
    public static void main(String[] args) {
        for (int rate : new int[]{8000, 16000, 44100, 48000}) {
            byte[] pcm = new byte[rate * 4];
            for (int i = 0; i < rate; i++) {
                // Stereo channels 1000 and 3000 must become mono 2000 at every output rate.
                pcm[i * 4] = (byte) 1000; pcm[i * 4 + 1] = (byte) (1000 >> 8);
                pcm[i * 4 + 2] = (byte) 3000; pcm[i * 4 + 3] = (byte) (3000 >> 8);
            }
            byte[] before = pcm.clone();
            byte[] all = new Pcm16Mono().convert(pcm, rate, 2);
            check(all.length == 32000, "one second at " + rate);
            check(Arrays.equals(pcm, before), "recorded PCM must not change");
            for (int p = 0; p < all.length; p += 2)
                check((short)((all[p] & 255) | ((all[p + 1] & 255) << 8)) == 2000, "mono amplitude");
            Pcm16Mono streaming = new Pcm16Mono();
            ByteArrayOutputStream chunks = new ByteArrayOutputStream();
            for (int p = 0; p < pcm.length; p += 404) {
                byte[] part = streaming.convert(Arrays.copyOfRange(pcm, p, Math.min(p + 404, pcm.length)), rate, 2);
                chunks.write(part, 0, part.length);
            }
            check(Arrays.equals(all, chunks.toByteArray()), "buffer boundaries at " + rate);
            streaming.reset();
            check(Arrays.equals(all, streaming.convert(pcm, rate, 2)), "reset phase");
        }
        byte[] mono = new byte[32000];
        new java.util.Random(17).nextBytes(mono);
        check(Arrays.equals(mono, new Pcm16Mono().convert(mono, 16000, 1)), "16k identity");
        System.out.println("PCM copy conversion: rates, channels, chunk boundaries, reset and identity OK");
    }
}
