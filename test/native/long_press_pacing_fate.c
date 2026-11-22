#include <stdio.h>
#include <string.h>

#include "piliexo_audio_clock.h"
#include "piliexo_codec_rate.h"
#include "piliexo_decode_budget.h"

enum { AV_CODEC_ID_H264, AV_CODEC_ID_HEVC, AV_PKT_FLAG_KEY = 1 };
enum { AV_PKT_DATA_NEW_EXTRADATA };
typedef struct { int codec_id; } AVCodecContext;
typedef struct {
    uint8_t *data;
    int size, flags, extradata;
} AVPacket;

static const uint8_t *av_packet_get_side_data(const AVPacket *pkt, int type,
                                             void *size)
{
    (void)type;
    (void)size;
    return pkt->extradata ? pkt->data : NULL;
}

#include "piliexo_nonref_au.h"

int main(void)
{
    char operation, name[80];
    while (scanf(" %c %79s", &operation, name) == 2) {
        if (operation == 'v') {
            double fps, speed;
            int late, samples, elapsed_ms;
            char frames[80];
            if (scanf("%lf %lf %d %d %d %79s", &fps, &speed, &late,
                      &samples, &elapsed_ms, frames) != 6)
                return 1;

            struct piliexo_decode_budget budget = {0};
            int demand = piliexo_codec_operating_rate(fps, speed);
            const int64_t started = 1000000;
            const int64_t elapsed = (int64_t)elapsed_ms * 1000;
            piliexo_decode_budget_measure(&budget, demand, started, late, false);
            for (int n = 1; n <= samples; n++)
                piliexo_decode_budget_measure(&budget, demand,
                                              started + elapsed * n / samples,
                                              late, true);
            piliexo_decode_budget_measure(&budget, demand, started + elapsed,
                                          late, false);

            printf("%s demand=%d drop=%.1f%% ", name, demand, budget.fraction * 100);
            for (const char *frame = frames; *frame; frame++) {
                if (piliexo_decode_budget_due(&budget) && *frame == 'N') {
                    piliexo_decode_budget_drop(&budget);
                    putchar('D');
                } else {
                    putchar(*frame);
                }
            }
            piliexo_decode_budget_measure(&budget, -demand, started + elapsed + 1,
                                          true, false);
            printf(" release=%.1f%%\n", budget.fraction * 100);
        } else if (operation == 'a') {
            struct piliexo_audio_clock audio = {0};
            double old_ms, old_rate, new_ms, new_rate, queued_ms, written_ms;
            if (scanf("%lf %lf %lf %lf %lf %lf", &old_ms, &old_rate, &new_ms,
                      &new_rate, &queued_ms, &written_ms) != 6)
                return 1;

            piliexo_audio_clock_write(&audio, old_ms / 1000, old_rate);
            piliexo_audio_clock_write(&audio, new_ms / 1000, new_rate);
            double remaining = piliexo_audio_clock_delay(&audio, queued_ms / 1000,
                                                         new_rate);
            printf("%s queued-media=%.0fms playing-pts=%.0fms\n",
                   name, remaining * 1000, written_ms - remaining * 1000);
        } else if (operation == 'n') {
            char codec[5], hex[120];
            uint8_t data[60];
            AVPacket pkt = {.data = data};
            if (scanf("%4s %d %d %119s", codec, &pkt.flags, &pkt.extradata, hex)
                != 4 || strlen(hex) % 2)
                return 1;
            for (size_t i = 0; i < strlen(hex); i += 2) {
                unsigned byte;
                if (sscanf(hex + i, "%2x", &byte) != 1)
                    return 1;
                data[pkt.size++] = byte;
            }
            AVCodecContext ctx = {
                .codec_id = !strcmp(codec, "hevc") ? AV_CODEC_ID_HEVC : AV_CODEC_ID_H264,
            };
            printf("%s %s\n", name,
                   piliexo_should_drop_nonref_au(&ctx, &pkt) ? "eligible" : "keep");
        } else {
            return 1;
        }
    }
    return ferror(stdin) || !feof(stdin);
}
