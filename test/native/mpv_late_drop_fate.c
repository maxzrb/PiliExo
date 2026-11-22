#include "piliexo_late_drop.h"

int replace_output(double audio_pts, double pts, double next_pts, double fps)
{
    return piliexo_late_output_due(audio_pts, pts, fps) &&
           piliexo_late_output_can_replace(audio_pts, pts, next_pts);
}

int catchup_after_rate_change(double before, double after, int elapsed_ms,
                              double audio_pts, double head_pts, double next_pts)
{
    struct piliexo_video_speed_transition transition = {0};
    const int64_t released = INT64_C(1000000000);
    piliexo_video_speed_changed(&transition, before, released - 1);
    piliexo_video_speed_changed(&transition, after, released);
    return piliexo_video_releasing(&transition, released + (int64_t)elapsed_ms * 1000000) &&
           replace_output(audio_pts, head_pts, next_pts, 60);
}

int release_can_drop(double before, double after, double current, int elapsed_ms,
                     int dropped_output)
{
    struct piliexo_video_speed_transition transition = {0};
    const int64_t start = INT64_C(1000000000);
    const int64_t now = start + (int64_t)elapsed_ms * 1000000;
    piliexo_video_speed_changed(&transition, before, start - 1);
    piliexo_video_speed_changed(&transition, after, start);
    piliexo_video_speed_changed(&transition, current, now);
    return piliexo_release_can_drop(&transition, now, dropped_output);
}

int release_output_wait_us(double fps, double speed, int age_us, int target_us)
{
    const int64_t now = INT64_C(1000000000);
    int64_t pts = piliexo_release_output_pts(now, now + (int64_t)target_us * 1000,
                                            now - (int64_t)age_us * 1000, fps, speed);
    return (pts - now) / 1000;
}

int texture_drop_recovery(double initial, double lower, int first_ms,
                          double first_av, int second_ms, double second_speed,
                          double second_av)
{
    struct piliexo_video_speed_transition transition = {0};
    const int64_t start = INT64_C(1000000000);
    const int64_t first = start + (int64_t)first_ms * 1000000;
    const int64_t second = start + (int64_t)second_ms * 1000000;
    piliexo_video_speed_changed(&transition, initial, start - 1);
    piliexo_video_speed_changed(&transition, lower, start);
    bool first_drop = piliexo_vo_recovery_can_drop(&transition, first, first_av);
    piliexo_video_speed_changed(&transition, second_speed, second);
    bool second_drop = piliexo_vo_recovery_can_drop(&transition, second, second_av);
    return first_drop * 10 + second_drop;
}
