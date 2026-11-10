#include <inttypes.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "piliexo_hdr_metadata.h"

static void print_metadata(uintptr_t opaque, int64_t pts_us, int type,
                           const uint8_t *data, int size)
{
    const char *name = (const char *)opaque;
    printf("%s@%" PRId64 " type=%d size=%d hex=", name, pts_us, type, size);
    for (int i = 0; i < size; i++) printf("%02x", data[i]);
    putchar('\n');
}

int main(void)
{
    char id[32];
    int64_t pts;
    char *hex = malloc(65536);
    if (!hex) return 2;
    while (scanf("%31s %" SCNd64 " %65535s", id, &pts, hex) == 3) {
        if ((strlen(hex) & 1) || strlen(hex) / 2 > 32768) return 3;
        size_t size = strlen(hex) / 2;
        uint8_t *packet = malloc(size);
        if (!packet) return 4;
        for (size_t i = 0; i < size; i++) {
            unsigned value;
            if (sscanf(hex + i * 2, "%2x", &value) != 1) return 5;
            packet[i] = (uint8_t)value;
        }
        piliexo_hdr_packet(packet, size, pts, print_metadata, (uintptr_t)id);
        free(packet);
    }
    free(hex);
    return 0;
}
