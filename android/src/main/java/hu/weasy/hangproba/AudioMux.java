package hu.weasy.hangproba;

import android.media.MediaCodec;
import android.media.MediaCodecInfo;
import android.media.MediaExtractor;
import android.media.MediaFormat;
import android.media.MediaMetadataRetriever;
import android.media.MediaMuxer;
import java.io.File;
import java.io.FileInputStream;
import java.nio.ByteBuffer;

/** Encodes the exact captured PCM and combines it with the silent camera track. */
public final class AudioMux {
    public static void create(File silentVideo, File pcm, File output, long audioOffsetUs) throws Exception {
        if (pcm.length() < 3200 || (pcm.length() & 1) != 0) throw new Exception("Hiányos mikrofonhang.");
        MediaExtractor extractor = new MediaExtractor();
        MediaMuxer muxer = null;
        MediaCodec encoder = null;
        boolean started = false;
        try (FileInputStream in = new FileInputStream(pcm)) {
            extractor.setDataSource(silentVideo.getAbsolutePath());
            int sourceTrack = -1;
            for (int i = 0; i < extractor.getTrackCount(); i++) {
                if (extractor.getTrackFormat(i).getString(MediaFormat.KEY_MIME).startsWith("video/")) {
                    sourceTrack = i; break;
                }
            }
            if (sourceTrack < 0) throw new Exception("Hiányzó videósáv.");
            MediaFormat video = extractor.getTrackFormat(sourceTrack);
            muxer = new MediaMuxer(output.getAbsolutePath(), MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4);
            MediaMetadataRetriever metadata = new MediaMetadataRetriever();
            try {
                metadata.setDataSource(silentVideo.getAbsolutePath());
                String rotation = metadata.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_ROTATION);
                if (rotation != null) muxer.setOrientationHint(Integer.parseInt(rotation));
            } finally { metadata.release(); }
            int videoTrack = muxer.addTrack(video);
            MediaFormat audio = MediaFormat.createAudioFormat("audio/mp4a-latm", 16000, 1);
            audio.setInteger(MediaFormat.KEY_AAC_PROFILE, MediaCodecInfo.CodecProfileLevel.AACObjectLC);
            audio.setInteger(MediaFormat.KEY_BIT_RATE, 64000);
            audio.setInteger(MediaFormat.KEY_MAX_INPUT_SIZE, 8192);
            encoder = MediaCodec.createEncoderByType("audio/mp4a-latm");
            encoder.configure(audio, null, null, MediaCodec.CONFIGURE_FLAG_ENCODE);
            encoder.start();
            MediaCodec.BufferInfo info = new MediaCodec.BufferInfo();
            boolean inputDone = false, outputDone = false;
            int audioTrack = -1;
            long samples = 0, firstVideoPts = -1;
            long deadline = System.nanoTime() + 120_000_000_000L;
            byte[] chunk = new byte[4096];
            while (!outputDone) {
                if (System.nanoTime() > deadline) throw new Exception("Hangvéglegesítési időtúllépés.");
                if (!inputDone) {
                    int index = encoder.dequeueInputBuffer(10000);
                    if (index >= 0) {
                        ByteBuffer buffer = encoder.getInputBuffer(index);
                        buffer.clear();
                        int n = in.read(chunk, 0, Math.min(chunk.length, buffer.remaining()) & ~1);
                        if (n < 0) {
                            encoder.queueInputBuffer(index, 0, 0, samples * 1_000_000L / 16000,
                                MediaCodec.BUFFER_FLAG_END_OF_STREAM);
                            inputDone = true;
                        } else {
                            buffer.put(chunk, 0, n);
                            encoder.queueInputBuffer(index, 0, n, samples * 1_000_000L / 16000, 0);
                            samples += n / 2;
                        }
                    }
                }
                int out = encoder.dequeueOutputBuffer(info, 10000);
                if (out == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED) {
                    audioTrack = muxer.addTrack(encoder.getOutputFormat());
                    muxer.start(); started = true;
                    // Copy the original compressed frames without re-encoding the video.
                    extractor.selectTrack(sourceTrack);
                    int bufferSize = video.containsKey(MediaFormat.KEY_MAX_INPUT_SIZE)
                        ? Math.max(video.getInteger(MediaFormat.KEY_MAX_INPUT_SIZE), 4 * 1024 * 1024)
                        : 4 * 1024 * 1024;
                    ByteBuffer frame = ByteBuffer.allocateDirect(bufferSize);
                    MediaCodec.BufferInfo vi = new MediaCodec.BufferInfo();
                    while (true) {
                        frame.clear();
                        int n = extractor.readSampleData(frame, 0);
                        if (n < 0) break;
                        if (firstVideoPts < 0) firstVideoPts = extractor.getSampleTime();
                        vi.set(0, n, extractor.getSampleTime() - firstVideoPts, extractor.getSampleFlags());
                        muxer.writeSampleData(videoTrack, frame, vi);
                        extractor.advance();
                    }
                } else if (out >= 0) {
                    ByteBuffer buffer = encoder.getOutputBuffer(out);
                    if ((info.flags & MediaCodec.BUFFER_FLAG_CODEC_CONFIG) == 0 && info.size > 0) {
                        if (!started || audioTrack < 0) throw new Exception("Hiányzó AAC formátum.");
                        buffer.position(info.offset); buffer.limit(info.offset + info.size);
                        info.presentationTimeUs = Math.max(0, info.presentationTimeUs + audioOffsetUs);
                        muxer.writeSampleData(audioTrack, buffer, info);
                    }
                    outputDone = (info.flags & MediaCodec.BUFFER_FLAG_END_OF_STREAM) != 0;
                    encoder.releaseOutputBuffer(out, false);
                }
            }
        } finally {
            extractor.release();
            if (encoder != null) { try { encoder.stop(); } finally { encoder.release(); } }
            if (muxer != null) { try { if (started) muxer.stop(); } finally { muxer.release(); } }
        }
        if (output.length() == 0) throw new Exception("Üres videófájl.");
    }
}
