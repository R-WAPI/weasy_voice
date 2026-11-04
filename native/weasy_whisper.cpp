#include <jni.h>
#include <atomic>
#include <string>
#include <vector>
#include <memory>
#include <algorithm>
#include "whisper.h"

struct Model {
    whisper_context * context = nullptr;
    std::atomic<bool> cancelled{false};
    ~Model() { if (context) whisper_free(context); }
};

static void fail(JNIEnv * env, const char * message) {
    env->ThrowNew(env->FindClass("java/lang/IllegalStateException"), message);
}

extern "C" JNIEXPORT jlong JNICALL
Java_hu_weasy_hangproba_LocalModel_nativeLoad(JNIEnv * env, jclass, jstring path) {
    const char * filename = env->GetStringUTFChars(path, nullptr);
    if (!filename) return 0;
    auto params = whisper_context_default_params();
    params.use_gpu = false;
    params.flash_attn = true;
    auto model = std::make_unique<Model>();
    model->context = whisper_init_from_file_with_params(filename, params);
    env->ReleaseStringUTFChars(path, filename);
    if (!model->context) { fail(env, "A Whisper modell nem toltheto be."); return 0; }
    if (!whisper_is_multilingual(model->context) || whisper_lang_id("hu") < 0) {
        fail(env, "A modell nem tobbnyelvu vagy nincs magyar nyelvi kod."); return 0;
    }
    return reinterpret_cast<jlong>(model.release());
}

extern "C" JNIEXPORT void JNICALL
Java_hu_weasy_hangproba_LocalModel_nativeCancel(JNIEnv *, jclass, jlong handle) {
    if (handle) reinterpret_cast<Model *>(handle)->cancelled.store(true);
}

extern "C" JNIEXPORT void JNICALL
Java_hu_weasy_hangproba_LocalModel_nativeFree(JNIEnv *, jclass, jlong handle) {
    delete reinterpret_cast<Model *>(handle);
}

extern "C" JNIEXPORT jstring JNICALL
Java_hu_weasy_hangproba_LocalModel_nativeDecode(JNIEnv * env, jclass, jlong handle, jfloatArray input) {
    auto * model = reinterpret_cast<Model *>(handle);
    if (!model || !model->context) { fail(env, "Nincs betoltott felismeromodell."); return nullptr; }
    const auto count = env->GetArrayLength(input);
    if (count < 16000 || count > 16000 * 10) { fail(env, "Hibas hangablakmeret."); return nullptr; }
    std::vector<float> samples(count);
    env->GetFloatArrayRegion(input, 0, count, samples.data());
    if (env->ExceptionCheck()) return nullptr;
    model->cancelled.store(false);
    auto params = whisper_full_default_params(WHISPER_SAMPLING_GREEDY);
    params.n_threads = 4;
    params.language = "hu";
    params.translate = false;
    params.detect_language = false;
    params.no_context = true;
    params.no_timestamps = true;
    params.single_segment = true;
    params.print_realtime = false;
    params.print_progress = false;
    params.print_timestamps = false;
    params.print_special = false;
    params.token_timestamps = false;
    params.suppress_blank = true;
    params.suppress_nst = true;
    params.temperature = 0.0f;
    params.temperature_inc = 0.0f;
    params.greedy.best_of = 1;
    params.max_tokens = 48;
    // One encoder position covers 20 ms. Round up to 32 positions, keeping
    // the three-second window inside a 3.2-second context instead of 5.12 s.
    params.audio_ctx = std::max(96, std::min(160, 32 * ((count + 10239) / 10240)));
    params.no_speech_thold = 0.6f;
    params.abort_callback = [](void * data) { return static_cast<Model *>(data)->cancelled.load(); };
    params.abort_callback_user_data = model;
    const int result = whisper_full(model->context, params, samples.data(), count);
    if (model->cancelled.load()) return env->NewStringUTF("");
    if (result != 0) { fail(env, "A magyar hangfelismeres futasi hibat adott."); return nullptr; }
    std::string text;
    for (int i = 0; i < whisper_full_n_segments(model->context); i++) {
        if (whisper_full_get_segment_no_speech_prob(model->context, i) > 0.85f) continue;
        text += whisper_full_get_segment_text(model->context, i);
    }
    return env->NewStringUTF(text.c_str());
}
