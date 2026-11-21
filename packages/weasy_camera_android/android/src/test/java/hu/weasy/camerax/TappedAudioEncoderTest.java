package hu.weasy.camerax;

import static org.junit.Assert.*;
import androidx.camera.video.internal.encoder.InputBuffer;
import com.google.common.util.concurrent.Futures;
import com.google.common.util.concurrent.ListenableFuture;
import java.nio.ByteBuffer;
import java.util.concurrent.atomic.AtomicReference;
import org.junit.After;
import org.junit.Test;

public class TappedAudioEncoderTest {
    private PcmTap.Listener listener;
    @After public void detach() { PcmTap.detach(listener); }
    static final class Buffer implements InputBuffer {
        final ByteBuffer data = ByteBuffer.allocateDirect(16);
        long pts; boolean eos; int submissions, cancellations;
        @Override public ByteBuffer getByteBuffer() { return data; }
        @Override public void setPresentationTimeUs(long value) { pts = value; }
        @Override public void setEndOfStream(boolean value) { eos = value; }
        @Override public boolean submit() { submissions++; return true; }
        @Override public boolean cancel() { cancellations++; return true; }
        @Override public ListenableFuture<Void> getTerminationFuture() { return Futures.immediateFuture(null); }
    }
    @Test public void copiesWithoutChangingOriginalBytesOrTimestamps() {
        Buffer original = new Buffer();
        original.data.put(new byte[]{9, 8, 1, 2, 3, 4, 7});
        original.data.position(2); original.data.limit(6);
        AtomicReference<byte[]> observed = new AtomicReference<>();
        listener = (pcm, rate, channels) -> {
            assertEquals(48000, rate); assertEquals(2, channels); observed.set(pcm);
        };
        PcmTap.attach(listener);
        InputBuffer tapped = new TappedAudioEncoder.TappedBuffer(original, 48000, 2);
        tapped.setPresentationTimeUs(987654321L);
        assertTrue(tapped.submit()); assertFalse(tapped.submit());
        assertEquals(1, original.submissions); assertEquals(987654321L, original.pts);
        assertEquals(2, original.data.position()); assertEquals(6, original.data.limit());
        assertArrayEquals(new byte[]{1, 2, 3, 4}, observed.get());
        observed.get()[0] = 99;
        assertEquals(1, original.data.get(2));
    }
    @Test public void cancelledAndEosBuffersNeverFeedRecognition() {
        listener = (pcm, rate, channels) -> fail("Must not feed STT"); PcmTap.attach(listener);
        Buffer a = new Buffer(); a.data.putInt(12).flip();
        InputBuffer cancelled = new TappedAudioEncoder.TappedBuffer(a, 16000, 1);
        assertTrue(cancelled.cancel()); assertFalse(cancelled.submit());
        assertEquals(1, a.cancellations); assertEquals(0, a.submissions);
        Buffer b = new Buffer(); b.data.putInt(34).flip();
        InputBuffer eos = new TappedAudioEncoder.TappedBuffer(b, 16000, 1);
        eos.setEndOfStream(true); assertTrue(eos.submit()); assertTrue(b.eos);
    }
    @Test public void recognitionFailureCannotPreventRecording() {
        listener = (pcm, rate, channels) -> { throw new IllegalStateException("STT failed"); };
        PcmTap.attach(listener);
        Buffer original = new Buffer(); original.data.putInt(12).flip();
        assertTrue(new TappedAudioEncoder.TappedBuffer(original, 16000, 1).submit());
        assertEquals(1, original.submissions);
    }
}
