package androidx.camera.video;

import hu.weasy.camerax.TappedAudioEncoder;
import androidx.camera.video.internal.encoder.AudioEncoderConfig;
import androidx.camera.video.internal.encoder.EncoderImpl;

/** Version-bound CameraX 1.5.3 adapter. Same-package access avoids reflection. */
public final class WeasyRecorderFactory {
    private WeasyRecorderFactory() {}
    public static Recorder build(Recorder.Builder builder) {
        builder.setAudioEncoderFactory((executor, config, sessionType) -> {
            AudioEncoderConfig audio = (AudioEncoderConfig) config;
            return new TappedAudioEncoder(new EncoderImpl(executor, config, sessionType),
                    audio.getCaptureSampleRate(), audio.getChannelCount());
        });
        return builder.build();
    }
}
