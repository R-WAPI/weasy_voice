package hu.weasy.camerax;

/** Single, non-blocking observer of CameraX's encoder input. Never opens a microphone. */
public final class PcmTap {
    public interface Listener {
        void offer(byte[] pcm, int sampleRate, int channels);
    }
    private static volatile Listener listener;
    private PcmTap() {}
    public static synchronized void attach(Listener next) {
        if (listener != null && listener != next) throw new IllegalStateException("A hangkövető már foglalt.");
        listener = next;
    }
    public static synchronized void detach(Listener current) {
        if (listener == current) listener = null;
    }
    public static Listener current() { return listener; }
}
