package hu.weasy.voice;
public final class SpeechOnsetCheck {
    private static void check(boolean ok) { if (!ok) throw new AssertionError(); }
    public static void main(String[] args) {
        SpeechOnset gate = new SpeechOnset();
        byte[] quiet = new byte[640], loud = new byte[640];
        for (int i = 0; i < 320; i++) { loud[i*2] = (byte)0xd0; loud[i*2+1] = 7; }
        for (int i = 0; i < 100; i++) check(gate.offer(quiet, quiet.length) == -1);
        check(gate.offer(loud, loud.length) == -1);
        check(gate.offer(quiet, quiet.length) == -1); // One click does not start.
        for (int i = 0; i < 5; i++) check(gate.offer(loud, loud.length) == -1);
        check(gate.offer(loud, loud.length) == 120);
        check(gate.offer(quiet, quiet.length) == 140);
        gate.reset(); check(gate.offer(quiet, quiet.length) == -1);
        System.out.println("Speech onset checks passed");
    }
}
