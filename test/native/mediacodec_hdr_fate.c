// 从固定 CTA-861.3 字节流核验实际 FFmpeg 补丁，包括重复附加时保留已有元数据。
#include <stdio.h>
#include <string.h>
#include <libavutil/frame.h>
#include <libavutil/mastering_display_metadata.h>
#include "libavcodec/mediacodec_hdr.h"

int main(void)
{
    char line[1024];
    int row = 0;
    while (fgets(line, sizeof(line), stdin)) {
        size_t length = strcspn(line, "\r\n");
        if (!length) continue;
        if (length % 2 || length > 512) return 1;
        uint8_t bytes[256];
        for (size_t i = 0; i < length/2; i++) {
            unsigned value;
            if (sscanf(line+2*i, "%2x", &value) != 1) return 1;
            bytes[i] = value;
        }
        AVFrame *frame = av_frame_alloc();
        if (!frame || ff_mediacodec_hdr_static_info_to_frame(frame, bytes, length/2) < 0) return 1;
        int count = frame->nb_side_data;
        if (ff_mediacodec_hdr_static_info_to_frame(frame, bytes, length/2) < 0) return 1;
        printf("%d sides=%d stable=%d", row++, frame->nb_side_data, count == frame->nb_side_data);
        AVFrameSideData *side = av_frame_get_side_data(frame, AV_FRAME_DATA_MASTERING_DISPLAY_METADATA);
        if (side) {
            const AVMasteringDisplayMetadata *m = (void *)side->data;
            printf(" mastering=%d,%d", m->has_primaries, m->has_luminance);
            if (m->has_primaries) {
                printf(" xy=");
                for (int c = 0; c < 4; c++) {
                    const AVRational *point = c < 3 ? m->display_primaries[c] : m->white_point;
                    printf("%s%d/%d,%d/%d", c ? ";" : "", point[0].num, point[0].den, point[1].num, point[1].den);
                }
            }
            if (m->has_luminance)
                printf(" luminance=%d/%d,%d/%d", m->max_luminance.num, m->max_luminance.den,
                       m->min_luminance.num, m->min_luminance.den);
        }
        side = av_frame_get_side_data(frame, AV_FRAME_DATA_CONTENT_LIGHT_LEVEL);
        if (side) {
            const AVContentLightMetadata *cl = (void *)side->data;
            printf(" light=%u,%u", cl->MaxCLL, cl->MaxFALL);
        }
        putchar('\n');
        av_frame_free(&frame);
    }
    return row ? 0 : 1;
}
