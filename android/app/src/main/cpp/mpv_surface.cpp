#include <jni.h>
#include <android/native_window_jni.h>
#include <android/data_space.h>
#include <android/log.h>
#include <dlfcn.h>
#include <cstdint>
#include <sstream>
#include <string>
#include <memory>
#include <mutex>
#include <unordered_map>

namespace {
struct MpvApi {
    void *library = nullptr;
    void *(*create_client)(void *, const char *) = nullptr;
    void (*destroy)(void *) = nullptr;
    int (*set_option)(void *, const char *, const char *) = nullptr;
    int (*set_property)(void *, const char *, const char *) = nullptr;
    char *(*get_property)(void *, const char *) = nullptr;
    void (*free_value)(void *) = nullptr;
    int32_t (*set_dataspace)(ANativeWindow *, int32_t) = nullptr;
    int32_t (*get_dataspace)(ANativeWindow *) = nullptr;

    bool load() {
        if (library) return create_client && destroy && set_option && set_property &&
            get_property && free_value && set_dataspace && get_dataspace;
        library = dlopen("libmpv.so", RTLD_NOW | RTLD_LOCAL);
        if (!library) return false;
        create_client = reinterpret_cast<decltype(create_client)>(dlsym(library, "mpv_create_client"));
        destroy = reinterpret_cast<decltype(destroy)>(dlsym(library, "mpv_destroy"));
        set_option = reinterpret_cast<decltype(set_option)>(dlsym(library, "mpv_set_option_string"));
        set_property = reinterpret_cast<decltype(set_property)>(dlsym(library, "mpv_set_property_string"));
        get_property = reinterpret_cast<decltype(get_property)>(dlsym(library, "mpv_get_property_string"));
        free_value = reinterpret_cast<decltype(free_value)>(dlsym(library, "mpv_free"));
        void *android = dlopen("libandroid.so", RTLD_NOW | RTLD_LOCAL);
        set_dataspace = reinterpret_cast<decltype(set_dataspace)>(dlsym(android, "ANativeWindow_setBuffersDataSpace"));
        get_dataspace = reinterpret_cast<decltype(get_dataspace)>(dlsym(android, "ANativeWindow_getBuffersDataSpace"));
        return create_client && destroy && set_option && set_property && get_property &&
            free_value && set_dataspace && get_dataspace;
    }
};
MpvApi api;

struct Output {
    void *client = nullptr;
    jobject surface = nullptr;
    ANativeWindow *window = nullptr;
    int32_t original_dataspace = ADATASPACE_UNKNOWN;
    bool marked_hdr = false;
    int32_t marked_dataspace = ADATASPACE_UNKNOWN;
    bool profile5_software_requested = false;
    bool direct_output = false;
    bool direct_logged = false;
    bool native_dolby = false;
    uintptr_t metadata_token = 0;
};

JavaVM *java_vm = nullptr;

// 解码线程只持有递增令牌，回调不解引用已经释放的视频输出对象。
struct MetadataSink {
    std::mutex mutex;
    jobject object = nullptr;
    jclass klass = nullptr;
    jmethodID method = nullptr;
};
std::mutex metadata_mutex;
uintptr_t next_metadata_token = 0;
std::unordered_map<uintptr_t, std::shared_ptr<MetadataSink>> metadata_sinks;

std::string string(JNIEnv *env, jstring input) {
    const char *value = env->GetStringUTFChars(input, nullptr);
    std::string result(value);
    env->ReleaseStringUTFChars(input, value);
    return result;
}

void fail(JNIEnv *env, const std::string &message) {
    env->ThrowNew(env->FindClass("java/lang/IllegalStateException"), message.c_str());
}

std::string property(Output *output, const char *name) {
    char *raw = api.get_property(output->client, name);
    if (!raw) return "";
    std::string result(raw);
    api.free_value(raw);
    return result;
}

std::string quoted(const std::string &value) {
    std::string result = "\"";
    for (unsigned char c : value) {
        if (c == '"' || c == '\\') result += '\\';
        if (c >= 0x20) result += static_cast<char>(c);
    }
    return result + '"';
}

void detach(JNIEnv *env, Output *output) {
    // 停止视频输出并清除 wid 后，才能释放供 mpv 使用的 Java Surface 全局引用。
    api.set_property(output->client, "vo", "null");
    api.set_option(output->client, "wid", "0");
    if (output->window) {
        if (output->marked_hdr) api.set_dataspace(output->window, output->original_dataspace);
        ANativeWindow_release(output->window);
        output->window = nullptr;
    }
    if (output->surface) {
        env->DeleteGlobalRef(output->surface);
        output->surface = nullptr;
    }
    output->marked_hdr = false;
    output->marked_dataspace = ADATASPACE_UNKNOWN;
    output->direct_logged = false;
}

void clear_metadata(JNIEnv *env, Output *output) {
    std::shared_ptr<MetadataSink> sink;
    {
        std::lock_guard<std::mutex> lock(metadata_mutex);
        auto entry = metadata_sinks.find(output->metadata_token);
        if (entry != metadata_sinks.end()) {
            sink = entry->second;
            metadata_sinks.erase(entry);
        }
        output->metadata_token = 0;
    }
    if (!sink) return;
    // 等待正在执行的回调结束，再删除 JNI 引用；迟到回调会查不到令牌。
    std::lock_guard<std::mutex> lock(sink->mutex);
    if (sink->object) env->DeleteGlobalRef(sink->object);
    if (sink->klass) env->DeleteGlobalRef(sink->klass);
    sink->object = nullptr;
    sink->klass = nullptr;
}

void deliver_metadata(uintptr_t opaque, int64_t pts_us, int type,
                      const uint8_t *data, int size) {
    std::shared_ptr<MetadataSink> sink;
    {
        std::lock_guard<std::mutex> lock(metadata_mutex);
        auto entry = metadata_sinks.find(opaque);
        if (entry == metadata_sinks.end()) return;
        sink = entry->second;
    }
    std::lock_guard<std::mutex> lock(sink->mutex);
    if (!sink->object || !java_vm) return;
    JNIEnv *env = nullptr;
    bool attached = false;
    const jint status = java_vm->GetEnv(reinterpret_cast<void **>(&env), JNI_VERSION_1_6);
    if (status == JNI_EDETACHED) {
        if (java_vm->AttachCurrentThread(&env, nullptr) != JNI_OK) return;
        attached = true;
    } else if (status != JNI_OK) {
        return;
    }
    jbyteArray payload = nullptr;
    if (data && size > 0) {
        payload = env->NewByteArray(size);
        if (payload) env->SetByteArrayRegion(
            payload, 0, size, reinterpret_cast<const jbyte *>(data));
    }
    if (type == 0 || payload) {
        env->CallVoidMethod(sink->object, sink->method,
                            static_cast<jlong>(pts_us), static_cast<jint>(type), payload);
    }
    if (payload) env->DeleteLocalRef(payload);
    if (env->ExceptionCheck()) env->ExceptionClear();
    if (attached) java_vm->DetachCurrentThread();
}
}

extern "C" JNIEXPORT jlong JNICALL
Java_com_maxzrb_piliexo_MpvSurfaceNative_create(JNIEnv *env, jobject, jlong handle, jboolean direct_output) {
    if (!api.load()) {
        fail(env, "mpv 或 NativeWindow HDR 接口不可用");
        return 0;
    }
    auto *output = new Output;
    output->direct_output = direct_output;
    output->client = api.create_client(reinterpret_cast<void *>(handle), "piliexo_hdr_output");
    if (!output->client) {
        delete output;
        fail(env, "无法创建 mpv 视频输出客户端");
        return 0;
    }
    return reinterpret_cast<jlong>(output);
}

extern "C" JNIEXPORT jstring JNICALL
Java_com_maxzrb_piliexo_MpvSurfaceNative_metadata(JNIEnv *env, jobject, jlong pointer,
                                                  jobject object, jboolean native_dolby) {
    auto *output = reinterpret_cast<Output *>(pointer);
    if (!output) return nullptr;
    output->native_dolby = native_dolby;
    clear_metadata(env, output);
    if (object) {
        auto sink = std::make_shared<MetadataSink>();
        sink->object = env->NewGlobalRef(object);
        jclass klass = env->GetObjectClass(object);
        sink->klass = reinterpret_cast<jclass>(env->NewGlobalRef(klass));
        env->DeleteLocalRef(klass);
        sink->method = env->GetMethodID(sink->klass, "onMetadata", "(JI[B)V");
        if (!sink->method || env->ExceptionCheck()) {
            env->DeleteGlobalRef(sink->object);
            env->DeleteGlobalRef(sink->klass);
            return nullptr;
        }
        std::lock_guard<std::mutex> lock(metadata_mutex);
        output->metadata_token = ++next_metadata_token;
        metadata_sinks.emplace(output->metadata_token, sink);
    }
    // 这些是 FFmpeg 私有选项，交给 Dart 合入每次 loadfile 的 vd-lavc-o。
    // 不调用 mpv_set_option_string 设置不存在的同名 mpv 顶层选项。
    const std::string options = std::string("piliexo_dolbyvision=") +
        (native_dolby ? "1" : "0") + ",piliexo_metadata_callback=" +
        (object ? std::to_string(reinterpret_cast<uintptr_t>(&deliver_metadata)) : "0") +
        ",piliexo_metadata_opaque=" + std::to_string(output->metadata_token);
    return env->NewStringUTF(options.c_str());
}

extern "C" JNIEXPORT void JNICALL
Java_com_maxzrb_piliexo_MpvSurfaceNative_option(JNIEnv *env, jobject, jlong pointer,
                                               jstring name, jstring value) {
    auto *output = reinterpret_cast<Output *>(pointer);
    const auto key = string(env, name);
    const auto content = string(env, value);
    const int result = api.set_option(output->client, key.c_str(), content.c_str());
    if (result < 0) {
        // 缺少配套 EGL 实现时按既有错误流程回退，不能只标记 dataspace 就宣称完整 HDR。
        fail(env, "mpv 选项设置失败：" + key + " (" + std::to_string(result) + ")");
    }
}

extern "C" JNIEXPORT void JNICALL
Java_com_maxzrb_piliexo_MpvSurfaceNative_attach(JNIEnv *env, jobject, jlong pointer,
                                               jobject surface, jint width, jint height) {
    auto *output = reinterpret_cast<Output *>(pointer);
    detach(env, output);
    output->surface = env->NewGlobalRef(surface);
    output->window = ANativeWindow_fromSurface(env, surface);
    if (!output->window) {
        fail(env, "无效的 mpv HDR Surface");
        return;
    }
    output->original_dataspace = api.get_dataspace(output->window);
    const std::string wid = std::to_string(reinterpret_cast<intptr_t>(output->surface));
    const std::string size = std::to_string(width) + "x" + std::to_string(height);
    api.set_option(output->client, "android-surface-size", size.c_str());
    api.set_option(output->client, "wid", wid.c_str());
    const char *vo = output->direct_output ? "mediacodec_embed" : "gpu-next";
    if (api.set_property(output->client, "vo", vo) < 0) {
        fail(env, "无法启用 mpv 原生视频输出：" + std::string(vo));
    }
}

extern "C" JNIEXPORT void JNICALL
Java_com_maxzrb_piliexo_MpvSurfaceNative_resize(JNIEnv *, jobject, jlong pointer,
                                               jint width, jint height) {
    auto *output = reinterpret_cast<Output *>(pointer);
    const std::string size = std::to_string(width) + "x" + std::to_string(height);
    api.set_option(output->client, "android-surface-size", size.c_str());
}

extern "C" JNIEXPORT jstring JNICALL
Java_com_maxzrb_piliexo_MpvSurfaceNative_snapshot(JNIEnv *env, jobject, jlong pointer) {
    auto *output = reinterpret_cast<Output *>(pointer);
    const bool configured = property(output, "vo-configured") == "yes";
    const auto vo = property(output, "current-vo");
    const auto profile = property(output, "current-tracks/video/dolby-vision-profile");
    const auto decoder = property(output, "hwdec-current");
    if (profile == "5" && !output->profile5_software_requested && !output->native_dolby) {
        // 容器探测作为 Codec String 缺失时的第二道保护，不让 P5 裸 YUV 留在硬解路径。
        output->profile5_software_requested = true;
        if (output->direct_output) api.set_property(output->client, "vo", "null");
        api.set_property(output->client, "hwdec", "no");
        if (output->direct_output) {
            output->direct_output = false;
            api.set_property(output->client, "vo", "gpu-next");
            return env->NewStringUTF("{\"configured\":false,\"hdrActive\":false,\"videoWidth\":\"0\",\"error\":\"\"}");
        }
        __android_log_print(ANDROID_LOG_INFO, "PiliMpvHdr", "Profile 5: requesting software RPU decoding");
    }
    const int format = output->window ? ANativeWindow_getFormat(output->window) : 0;
    int dataspace = output->window ? api.get_dataspace(output->window) : 0;
    const auto target_gamma = property(output, "video-target-params/gamma");
    const auto source_gamma = property(output, "video-out-params/gamma");
    const auto output_gamma = vo == "mediacodec_embed" ? source_gamma : target_gamma;
    const int desired_dataspace = target_gamma == "hlg" ? ADATASPACE_BT2020_HLG : ADATASPACE_BT2020_PQ;
    std::string error;
    bool direct_active = false;
    if (configured && output->window && vo == "mediacodec_embed" && !decoder.empty()) {
        // MediaCodec 负责原生 YUV 的范围和 HDR 标记，不能用 GPU 的全范围 RGB 标记覆盖。
        // 解码器可通过另一个 Surface 客户端给每个缓冲提交标记；本地窗口查询可仍为 UNKNOWN。
        // 此处确认实际解码与源信号，最终缓冲标记另由系统图层验收，不能据本地值误回退。
        if (decoder == "no") {
            error = "原生 Surface 直出需要 MediaCodec 硬解";
        } else if (source_gamma == "pq" || source_gamma == "hlg") {
            direct_active = true;
            if (!output->direct_logged) {
                output->direct_logged = true;
                __android_log_print(ANDROID_LOG_INFO, "PiliMpvHdr",
                    "HDR direct: format=%d dataspace=0x%x vo=mediacodec_embed", format, dataspace);
            }
        } else if (!source_gamma.empty()) {
            error = "原生 HDR 输出的源传递函数不是 PQ 或 HLG";
        }
    }
    if (configured && output->window && vo == "gpu-next" && !target_gamma.empty()) {
        if (target_gamma != "pq" && target_gamma != "hlg") {
            error = "HDR 输出传递函数不是 PQ 或 HLG：" + target_gamma;
        // RGB10_A2 或 RGBA_FP16 才允许声明原生 HDR，拒绝把八位 SDR 缓冲当作验收成功。
        } else if (format != 43 && format != 22) {
            error = "HDR 输出缓冲不是10位或浮点格式：" + std::to_string(format);
        } else {
            if (!output->marked_hdr || output->marked_dataspace != desired_dataspace) {
                const int result = api.set_dataspace(output->window, desired_dataspace);
                dataspace = api.get_dataspace(output->window);
                if (result != 0 || dataspace != desired_dataspace) {
                    error = "HDR dataspace 请求未生效";
                } else {
                    output->marked_hdr = true;
                    output->marked_dataspace = desired_dataspace;
                    __android_log_print(ANDROID_LOG_INFO, "PiliMpvHdr",
                        "HDR active: format=%d dataspace=0x%x vo=gpu-next", format, dataspace);
                }
            } else if (dataspace != desired_dataspace) {
                error = "HDR dataspace 被驱动改写，停止 HDR 输出";
            }
        }
    }
    std::ostringstream json;
    json << "{\"configured\":" << (configured ? "true" : "false")
         << ",\"vo\":" << quoted(vo)
         << ",\"hdrActive\":" << ((direct_active || (configured && !target_gamma.empty() && output->marked_hdr)) && error.empty() ? "true" : "false")
         << ",\"outputTransfer\":" << quoted(output_gamma)
         << ",\"signalling\":" << quoted(vo == "mediacodec_embed" ? "decoder-managed" : "gpu-window")
         << ",\"format\":" << format << ",\"dataspace\":" << dataspace
         << ",\"videoWidth\":" << quoted(property(output, "video-params/w"))
         << ",\"error\":" << quoted(error);
    for (const char *name : {"current-tracks/video/dolby-vision-profile", "hwdec-current",
                             "options/android-hdr-signal-passthrough", "options/target-trc",
                             "options/target-prim", "options/target-peak",
                             "options/tone-mapping", "options/gamut-mapping-mode",
                             "options/hdr-compute-peak", "video-target-params/gamma",
                             "video-target-params/sig-peak", "video-params/sig-peak",
                             "video-params/min-luma", "video-params/max-luma",
                             "video-params/max-cll", "video-params/max-fall",
                             "video-params/prim-red-x", "video-params/prim-red-y",
                             "video-params/prim-green-x", "video-params/prim-green-y",
                             "video-params/prim-blue-x", "video-params/prim-blue-y",
                             "video-params/prim-white-x", "video-params/prim-white-y",
                             "video-params/colormatrix", "video-params/primaries",
                             "video-params/gamma", "video-out-params/colormatrix",
                             "video-out-params/primaries", "video-out-params/gamma"}) {
        json << ',' << quoted(name) << ':' << quoted(property(output, name));
    }
    json << '}';
    return env->NewStringUTF(json.str().c_str());
}

extern "C" JNIEXPORT void JNICALL
Java_com_maxzrb_piliexo_MpvSurfaceNative_detach(JNIEnv *env, jobject, jlong pointer) {
    detach(env, reinterpret_cast<Output *>(pointer));
}

extern "C" JNIEXPORT void JNICALL
Java_com_maxzrb_piliexo_MpvSurfaceNative_release(JNIEnv *env, jobject, jlong pointer) {
    auto *output = reinterpret_cast<Output *>(pointer);
    clear_metadata(env, output);
    detach(env, output);
    api.destroy(output->client);
    delete output;
}

extern "C" JNIEXPORT jint JNICALL JNI_OnLoad(JavaVM *vm, void *) {
    java_vm = vm;
    return JNI_VERSION_1_6;
}
