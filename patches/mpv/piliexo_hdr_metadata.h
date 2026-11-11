#ifndef PILIEXO_HDR_METADATA_H
#define PILIEXO_HDR_METADATA_H
#include <stdint.h>
#include <stddef.h>
#include <stdlib.h>
#include <string.h>

typedef void (*PiliexoHdrCallback)(uintptr_t opaque, int64_t pts_us,
                                   int type, const uint8_t *data, int size);

/* 只读取 HEVC Annex B 的 SEI；不改变送入解码器的码流，保留 RPU 和全部 NAL。 */
static void piliexo_hdr_sei(const uint8_t *nal, size_t size, int64_t pts_us,
                           PiliexoHdrCallback callback, uintptr_t opaque)
{
    if (size < 3 || size > 65536 || !callback)
        return;
    const int nal_type = (nal[0] >> 1) & 63;
    if ((nal_type != 39 && nal_type != 40) || (nal[0] & 128) || !(nal[1] & 7))
        return;
    uint8_t *rbsp = malloc(size);
    if (!rbsp)
        return;
    size_t count = 0;
    int zeros = 0;
    for (size_t i = 2; i < size; i++) {
        if (zeros >= 2 && nal[i] == 3) {
            if (i + 1 >= size || nal[i + 1] > 3) goto done;
            zeros = 0;
            continue;
        }
        rbsp[count++] = nal[i];
        zeros = nal[i] == 0 ? zeros + 1 : 0;
    }
    for (size_t pos = 0; pos < count && rbsp[pos] != 128;) {
        size_t type = 0, length = 0;
        while (pos < count && rbsp[pos] == 255) { type += 255; pos++; }
        if (pos >= count) break;
        type += rbsp[pos++];
        while (pos < count && rbsp[pos] == 255) { length += 255; pos++; }
        if (pos >= count) break;
        length += rbsp[pos++];
        if (length > count - pos) break;
        const uint8_t *payload = rbsp + pos;
        if ((type == 137 && length == 24) || (type == 144 && length == 4)) {
            callback(opaque, pts_us, (int)type, payload, (int)length);
        } else if (type == 4 && length > 5 && payload[0] == 0x26 &&
                   payload[1] == 0 && payload[2] == 4 &&
                   payload[3] == 0 && payload[4] == 5) {
            /* SDK 接收 CUVA 动态载荷，不包含五字节的 ITU-T T.35 标识。 */
            callback(opaque, pts_us, 4, payload + 5, (int)length - 5);
        }
        pos += length;
    }
done:
    free(rbsp);
}

static int piliexo_hdr_annexb_packet(const uint8_t *data, size_t size, int64_t pts_us,
                                    PiliexoHdrCallback callback, uintptr_t opaque)
{
    size_t start = 0;
    int found = 0;
    for (size_t i = 0; i + 2 < size;) {
        if (data[i] == 0 && data[i + 1] == 0 && data[i + 2] == 1) {
            found = 1;
            if (start) piliexo_hdr_sei(data + start, i - start, pts_us, callback, opaque);
            start = i + 3;
            i += 3;
        } else {
            i++;
        }
    }
    if (start < size && start)
        piliexo_hdr_sei(data + start, size - start, pts_us, callback, opaque);
    return found;
}

static uint32_t piliexo_read_be(const uint8_t *data, int bytes)
{
    uint32_t value = 0;
    for (int i = 0; i < bytes; i++) value = (value << 8) | data[i];
    return value;
}

/* nal_length_size=0 表示 Annex B；长度前缀由容器或调用者明确指定，禁止猜测。 */
static void piliexo_hdr_packet(const uint8_t *data, size_t size, int nal_length_size,
                              int64_t pts_us, PiliexoHdrCallback callback, uintptr_t opaque)
{
    if (nal_length_size == 0) {
        piliexo_hdr_annexb_packet(data, size, pts_us, callback, opaque);
        return;
    }
    if (nal_length_size < 1 || nal_length_size > 4)
        return;
    const size_t width = (size_t)nal_length_size;
    // 先验证完整包，避免损坏的长度前缀先投递一部分元数据再失败。
    size_t pos = 0;
    while (pos < size) {
        if (size - pos < width) return;
        uint32_t length = piliexo_read_be(data + pos, nal_length_size);
        pos += width;
        if (length < 2 || length > size - pos) return;
        pos += length;
    }
    for (pos = 0; pos < size;) {
        uint32_t length = piliexo_read_be(data + pos, nal_length_size);
        pos += width;
        piliexo_hdr_sei(data + pos, length, pts_us, callback, opaque);
        pos += length;
    }
}
#endif
