// 使用与 Android mpv 相同的 libplacebo 静态库，在离屏 EGL 上核验 PQ 颜色映射。
#include <EGL/egl.h>
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <libplacebo/dispatch.h>
#include <libplacebo/gamut_mapping.h>
#include <libplacebo/log.h>
#include <libplacebo/opengl.h>
#include <libplacebo/shaders/colorspace.h>
#include <libplacebo/shaders/sampling.h>
#include <libplacebo/tone_mapping.h>
#include "video/out/opengl/android_hdr.h"

#define REQUIRE(x) do { if (!(x)) { fprintf(stderr, "failed: %s\n", #x); return 1; } } while (0)

int main(int argc, char **argv)
{
    if (argc == 2 && strcmp(argv[1], "--metadata") == 0) {
        float f[12];
        int row = 0;
        while (scanf("%f %f %f %f %f %f %f %f %f %f %f %f",
                     &f[0], &f[1], &f[2], &f[3], &f[4], &f[5],
                     &f[6], &f[7], &f[8], &f[9], &f[10], &f[11]) == 12) {
            struct pl_hdr_metadata hdr = { .prim = {
                .red = {f[0], f[1]}, .green = {f[2], f[3]},
                .blue = {f[4], f[5]}, .white = {f[6], f[7]} },
                .max_luma = f[8], .min_luma = f[9], .max_cll = f[10], .max_fall = f[11] };
            EGLint values[12];
            mpv_android_hdr_metadata(&hdr, values);
            printf("%d", row++);
            for (int i = 0; i < 12; i++) printf(" %d", values[i]);
            putchar('\n');
        }
        REQUIRE(row > 0);
        return 0;
    }
    REQUIRE(argc == 3 || argc == 4);
    float peak = strtof(argv[1], NULL);
    bool clip = strcmp(argv[2], "clip") == 0;
    bool hlg = argc == 4 && strcmp(argv[3], "hlg") == 0;
    float pixels[256][4];
    int count = 0;
    while (count < 256 && scanf("%f %f %f", &pixels[count][0],
                               &pixels[count][1], &pixels[count][2]) == 3) {
        pixels[count++][3] = 1.0f;
    }
    REQUIRE(count > 0);
    EGLDisplay display = eglGetDisplay(EGL_DEFAULT_DISPLAY);
    REQUIRE(eglInitialize(display, NULL, NULL));
    REQUIRE(eglBindAPI(EGL_OPENGL_ES_API));
    const EGLint attrs[] = { EGL_SURFACE_TYPE, EGL_PBUFFER_BIT,
        EGL_RENDERABLE_TYPE, EGL_OPENGL_ES3_BIT, EGL_NONE };
    EGLConfig config;
    EGLint configs;
    REQUIRE(eglChooseConfig(display, attrs, &config, 1, &configs) && configs);
    const EGLint context_attrs[] = { EGL_CONTEXT_CLIENT_VERSION, 3, EGL_NONE };
    EGLContext context = eglCreateContext(display, config, EGL_NO_CONTEXT, context_attrs);
    REQUIRE(context != EGL_NO_CONTEXT);
    const EGLint surface_attrs[] = { EGL_WIDTH, count, EGL_HEIGHT, 1, EGL_NONE };
    EGLSurface surface = eglCreatePbufferSurface(display, config, surface_attrs);
    REQUIRE(surface != EGL_NO_SURFACE);
    REQUIRE(eglMakeCurrent(display, surface, surface, context));
    pl_log log = pl_log_create(PL_API_VER, pl_log_params(
        .log_cb = pl_log_simple, .log_priv = stderr, .log_level = PL_LOG_WARN));
    pl_opengl gl = pl_opengl_create(log, pl_opengl_params(
        .get_proc_addr = (pl_voidfunc_t (*)(const char *)) eglGetProcAddress,
        .egl_display = display, .egl_context = context));
    REQUIRE(gl);
    pl_gpu gpu = gl->gpu;
    pl_fmt fmt = pl_find_fmt(gpu, PL_FMT_FLOAT, 4, 16, 16,
        PL_FMT_CAP_SAMPLEABLE | PL_FMT_CAP_RENDERABLE | PL_FMT_CAP_HOST_READABLE);
    REQUIRE(fmt);
    _Float16 input[256][4];
    for (int i = 0; i < count; i++)
        for (int c = 0; c < 4; c++) input[i][c] = pixels[i][c];
    pl_tex source = pl_tex_create(gpu, pl_tex_params(
        .w = count, .h = 1, .format = fmt, .sampleable = true,
        .initial_data = input));
    pl_tex target = pl_tex_create(gpu, pl_tex_params(
        .w = count, .h = 1, .format = fmt, .renderable = true, .host_readable = true));
    REQUIRE(source && target);
    struct pl_color_space src = pl_color_space_hdr10;
    src.hdr = pl_hdr_metadata_hdr10;
    src.hdr.max_luma = 1000.0f;
    src.hdr.min_luma = 0.005f;
    if (hlg) src = pl_color_space_bt2020_hlg;
    struct pl_color_space dst = pl_color_space_hdr10;
    if (hlg) dst = pl_color_space_bt2020_hlg;
    dst.hdr.max_luma = peak;
    dst.hdr.min_luma = 1e-7f;
    struct pl_color_map_params params = pl_color_map_default_params;
    params.tone_mapping_function = clip ? &pl_tone_map_clip : &pl_tone_map_auto;
    if (clip) params.gamut_mapping = &pl_gamut_map_clip;
    params.contrast_recovery = 0;
    pl_dispatch dispatch = pl_dispatch_create(log, gpu);
    pl_shader shader = pl_dispatch_begin(dispatch);
    pl_shader_sample_direct(shader, pl_sample_src(.tex = source));
    pl_shader_obj state = NULL;
    pl_shader_color_map(shader, &params, src, dst, &state, false);
    REQUIRE(pl_dispatch_finish(dispatch, pl_dispatch_params(.shader = &shader, .target = target)));
    _Float16 result[256][4];
    REQUIRE(pl_tex_download(gpu, pl_tex_transfer_params(.tex = target, .ptr = result)));
    for (int i = 0; i < count; i++) {
        printf("%d %.6f %.6f %.6f\n", i, (double)result[i][0],
               (double)result[i][1], (double)result[i][2]);
    }
    pl_shader_obj_destroy(&state);
    pl_dispatch_destroy(&dispatch);
    pl_tex_destroy(gpu, &source);
    pl_tex_destroy(gpu, &target);
    pl_opengl_destroy(&gl);
    pl_log_destroy(&log);
    eglMakeCurrent(display, EGL_NO_SURFACE, EGL_NO_SURFACE, EGL_NO_CONTEXT);
    eglDestroySurface(display, surface);
    eglDestroyContext(display, context);
    eglTerminate(display);
    return 0;
}
