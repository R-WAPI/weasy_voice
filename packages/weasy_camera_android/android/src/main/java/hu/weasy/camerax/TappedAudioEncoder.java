package hu.weasy.camerax;

import androidx.camera.core.impl.Observable;
import androidx.camera.video.internal.BufferProvider;
import androidx.camera.video.internal.encoder.Encoder;
import androidx.camera.video.internal.encoder.EncoderCallback;
import androidx.camera.video.internal.encoder.EncoderInfo;
import androidx.camera.video.internal.encoder.InputBuffer;
import com.google.common.util.concurrent.Futures;
import com.google.common.util.concurrent.ListenableFuture;
import com.google.common.util.concurrent.MoreExecutors;
import java.nio.ByteBuffer;
import java.util.concurrent.Executor;

/** Copies PCM for STT. The original bytes, timestamps and recording lifecycle stay with CameraX. */
public final class TappedAudioEncoder implements Encoder {
    private final Encoder delegate;
    private final ByteBufferInput input;
    public TappedAudioEncoder(Encoder delegate, int rate, int channels) {
        this.delegate = delegate;
        ByteBufferInput original = (ByteBufferInput) delegate.getInput();
        input = new ByteBufferInput() {
            @Override public ListenableFuture<InputBuffer> acquireBuffer() {
                return Futures.transform(original.acquireBuffer(), buffer ->
                        new TappedBuffer(buffer, rate, channels), MoreExecutors.directExecutor());
            }
            @Override public ListenableFuture<BufferProvider.State> fetchData() { return original.fetchData(); }
            @Override public void addObserver(Executor executor, Observable.Observer<? super BufferProvider.State> observer) {
                original.addObserver(executor, observer);
            }
            @Override public void removeObserver(Observable.Observer<? super BufferProvider.State> observer) {
                original.removeObserver(observer);
            }
        };
    }
    static final class TappedBuffer implements InputBuffer {
        private final InputBuffer delegate;
        private final int rate, channels;
        private boolean finished, endOfStream;
        TappedBuffer(InputBuffer delegate, int rate, int channels) {
            this.delegate = delegate; this.rate = rate; this.channels = channels;
        }
        @Override public ByteBuffer getByteBuffer() { return delegate.getByteBuffer(); }
        @Override public void setPresentationTimeUs(long pts) { delegate.setPresentationTimeUs(pts); }
        @Override public void setEndOfStream(boolean eos) { endOfStream = eos; delegate.setEndOfStream(eos); }
        @Override public boolean submit() {
            if (finished) return false;
            finished = true;
            PcmTap.Listener listener = PcmTap.current();
            byte[] copy = null;
            // Copy before submit: CameraX/MediaCodec owns the buffer as soon as it is submitted.
            if (listener != null && !endOfStream) {
                try {
                    ByteBuffer view = delegate.getByteBuffer().asReadOnlyBuffer();
                    copy = new byte[view.remaining()]; view.get(copy);
                } catch (RuntimeException ignored) { /* STT must never break recorded audio. */ }
            }
            boolean accepted = delegate.submit();
            if (accepted && copy != null && copy.length > 0) {
                try { listener.offer(copy, rate, channels); }
                catch (RuntimeException ignored) { /* Recorder remains authoritative. */ }
            }
            return accepted;
        }
        @Override public boolean cancel() {
            if (finished) return false;
            finished = true; return delegate.cancel();
        }
        @Override public ListenableFuture<Void> getTerminationFuture() { return delegate.getTerminationFuture(); }
    }
    @Override public EncoderInput getInput() { return input; }
    @Override public EncoderInfo getEncoderInfo() { return delegate.getEncoderInfo(); }
    @Override public int getConfiguredBitrate() { return delegate.getConfiguredBitrate(); }
    @Override public void start() { delegate.start(); }
    @Override public void stop() { delegate.stop(); }
    @Override public void stop(long timestamp) { delegate.stop(timestamp); }
    @Override public void pause() { delegate.pause(); }
    @Override public void release() { delegate.release(); }
    @Override public ListenableFuture<Void> getReleasedFuture() { return delegate.getReleasedFuture(); }
    @Override public void setEncoderCallback(EncoderCallback callback, Executor executor) { delegate.setEncoderCallback(callback, executor); }
    @Override public void requestKeyFrame() { delegate.requestKeyFrame(); }
}
