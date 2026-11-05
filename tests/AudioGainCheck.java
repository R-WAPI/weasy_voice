package hu.weasy.hangproba;
import java.util.Arrays;
public final class AudioGainCheck {
    private static void check(boolean ok) { if (!ok) throw new AssertionError(); }
    private static byte[] pcm(int... values) {
        byte[] data = new byte[values.length * 2];
        for (int i = 0; i < values.length; i++) {
            data[2*i] = (byte)values[i]; data[2*i+1] = (byte)(values[i] >> 8);
        }
        return data;
    }
    public static void main(String[] args) {
        AudioWindow window = new AudioWindow(16);
        byte[] input = pcm(1000, -1000, 32767, -32768, 0);
        byte[] original = input.clone();
        window.offer(input, input.length);
        float[] out = window.snapshot().samples;
        check(Math.abs(out[0] - 1400f/32768f) < 0.000001f);
        check(Math.abs(out[1] + 1400f/32768f) < 0.000001f);
        check(out[2] == 1f && out[3] == -1f && out[4] == 0f);
        check(Arrays.equals(input, original)); // Video PCM is never modified.
        AudioWindow quiet = new AudioWindow(16);
        quiet.offer(pcm(0, 0), 4); check(!quiet.snapshot().voiced);
        // Previously below the recognition activity gate; the modest gain now reaches it.
        quiet.offer(pcm(94, -94), 4); check(quiet.snapshot().voiced);
        System.out.println("Recognition gain checks passed");
    }
}
