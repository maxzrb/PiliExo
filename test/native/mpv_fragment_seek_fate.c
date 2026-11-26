#include <math.h>
#include <stdio.h>
#include <string.h>
#include <time.h>
#include <mpv/client.h>

static double clock_seconds(void)
{
    struct timespec now;
    clock_gettime(CLOCK_MONOTONIC, &now);
    return now.tv_sec + now.tv_nsec / 1e9;
}

static double seconds_at(mpv_handle *player, const char *property)
{
    double seconds;
    return mpv_get_property(player, property, MPV_FORMAT_DOUBLE, &seconds) >= 0
        ? seconds : NAN;
}

int main(int argc, char **argv)
{
    if (argc != 3 && argc != 4)
        return 2;
    char options[2048];
    int length = snprintf(options, sizeof(options),
        "start=45,audio-files-append=%%%zu%%%s%s", strlen(argv[2]), argv[2],
        argc == 3 ? ",demuxer-lavf-piliexo-refresh-mov-index=yes" : "");
    if (length < 0 || (size_t)length >= sizeof(options))
        return 2;

    mpv_handle *player = mpv_create();
    if (!player)
        return 2;
    int status = 1;
    if (mpv_set_option_string(player, "config", "no") < 0 ||
        mpv_set_option_string(player, "vo", "null") < 0 ||
        mpv_set_option_string(player, "ao", "null") < 0 ||
        mpv_set_option_string(player, "hwdec", "no") < 0 ||
        mpv_set_option_string(player, "cache-secs", "3") < 0 ||
        mpv_initialize(player) < 0 ||
        mpv_command(player, (const char *[]){"loadfile", argv[1], "replace",
                                           "0", options, NULL}) < 0)
        goto done;

    double deadline = clock_seconds() + 8;
    while (clock_seconds() < deadline) {
        mpv_wait_event(player, 0.1);
        if (seconds_at(player, "audio-pts") >= 48)
            break;
    }
    if (clock_seconds() >= deadline ||
        mpv_command(player, (const char *[]){"seek", "7", "absolute+exact", NULL}) < 0)
        goto done;

    double first_sync = NAN;
    deadline = clock_seconds() + 7;
    while (clock_seconds() < deadline) {
        mpv_wait_event(player, 0.1);
        double video = seconds_at(player, "time-pos");
        double audio = seconds_at(player, "audio-pts");
        if (isfinite(audio) && fmax(video, audio) > 15)
            break;
        if (video > 7.05 && fabs(video - audio) < 0.3) {
            if (!isfinite(first_sync))
                first_sync = video;
            if (first_sync < 8 && video >= 10.5) {
                printf("原地跳转后同步推进：%.3f -> %.3f 秒\n", first_sync, video);
                status = 0;
                break;
            }
        }
    }

done:
    if (status)
        fprintf(stderr, "原地回跳未同步：视频 %.3f，音频 %.3f\n",
                seconds_at(player, "time-pos"), seconds_at(player, "audio-pts"));
    mpv_terminate_destroy(player);
    return status;
}
