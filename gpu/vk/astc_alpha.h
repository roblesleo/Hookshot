// (fork) Whether an ASTC block can decode to an alpha other than 1, from its header alone: the endpoint modes of its
// partitions (luminance and RGB modes have none), or a void-extent block's constant. What says which large ASTC textures
// kept as BC3 (8 bits a texel) carry nothing in BC3's alpha half and could be BC1 (4 bits). (vk_texture.cpp)
// tests/test_astc_alpha.py
#pragma once
#include <cstdint>
#include <cstring>

namespace astc_alpha {

inline uint32_t bits(const uint8_t* b, uint32_t at, uint32_t n) {   // (n <= 16, at + n <= 128)
    uint32_t v = 0;
    for (uint32_t i = 0; i < 3 && (at >> 3) + i < 16; i++) v |= (uint32_t)b[(at >> 3) + i] << (8 * i);
    return (v >> (at & 7)) & ((1u << n) - 1);
}

inline bool mode_has_alpha(uint32_t cem) {   // (4, 5: luminance + alpha; 10: RGB + two alphas; 12-15: RGBA)
    return cem == 4 || cem == 5 || cem == 10 || cem >= 12;
}

/// The bits of a 2D block's weights; 0 for a reserved block mode
inline uint32_t weight_bits(uint32_t mode) {
    uint32_t r, w, h, dual, high;
    const uint32_t a = (mode >> 5) & 3;
    if (mode & 3) {
        r = ((mode >> 4) & 1) | ((mode & 3) << 1);
        const uint32_t b = (mode >> 7) & 3;
        switch ((mode >> 2) & 3) {
        case 0: w = b + 4, h = a + 2; break;
        case 1: w = b + 8, h = a + 2; break;
        case 2: w = a + 2, h = b + 8; break;
        default:
            if (b & 2) w = (b & 1) + 2, h = a + 2;
            else w = a + 2, h = (b & 1) + 6;
        }
        dual = (mode >> 10) & 1, high = (mode >> 9) & 1;
    } else {
        if (!((mode >> 2) & 3)) return 0;
        r = ((mode >> 4) & 1) | (((mode >> 2) & 3) << 1);
        const uint32_t b = (mode >> 9) & 3;
        dual = (mode >> 10) & 1, high = (mode >> 9) & 1;
        switch ((mode >> 7) & 3) {
        case 0: w = 12, h = a + 2; break;
        case 1: w = a + 2, h = 12; break;
        case 2: w = a + 6, h = b + 6, dual = 0, high = 0; break;
        default:
            if (a & 2) return 0;
            if (a & 1) w = 10, h = 6;
            else w = 6, h = 10;
        }
    }
    if (r < 2) return 0;
    static const uint8_t trits[2][8] = {{0, 0, 0, 1, 0, 0, 1, 0}, {0, 0, 0, 1, 0, 0, 1, 0}};
    static const uint8_t quints[2][8] = {{0, 0, 0, 0, 0, 1, 0, 0}, {0, 0, 1, 0, 0, 1, 0, 0}};
    static const uint8_t plain[2][8] = {{0, 0, 1, 0, 2, 0, 1, 3}, {0, 0, 1, 2, 4, 2, 3, 5}};
    const uint32_t n = w * h * (dual ? 2 : 1);
    if (n > 64) return 0;
    uint32_t total = n * plain[high][r];
    if (trits[high][r]) total += (n * 8 + 4) / 5;
    if (quints[high][r]) total += (n * 7 + 2) / 3;
    return total;
}

/// One 16-byte block. A block that does not decode (reserved mode: the error colour, opaque) has none
inline bool block_has_alpha(const uint8_t* b) {
    const uint32_t mode = bits(b, 0, 11);
    if ((mode & 0x1FF) == 0x1FC) return (b[14] | (b[15] << 8)) != 0xFFFF;   // (void extent: its constant alpha)
    const uint32_t wb = weight_bits(mode);
    if (wb < 24 || wb > 96) return false;
    const uint32_t parts = bits(b, 11, 2) + 1;
    if (parts == 1) return mode_has_alpha(bits(b, 13, 4));
    uint32_t cem = bits(b, 23, 6);
    if (!(cem & 3)) return mode_has_alpha(cem >> 2);
    const uint32_t extra = 3 * parts - 4;
    cem |= bits(b, 128 - wb - extra, extra) << 6;
    const uint32_t base = (cem & 3) - 1;
    for (uint32_t i = 0; i < parts; i++) {
        const uint32_t cls = ((cem >> (2 + i)) & 1) + base;
        const uint32_t m = (cem >> (2 + parts + 2 * i)) & 3;
        if (mode_has_alpha((cls << 2) | m)) return true;
    }
    return false;
}

/// How many of the n bytes' blocks have alpha
inline uint64_t count(const uint8_t* p, uint64_t n) {
    uint64_t c = 0;
    for (uint64_t at = 0; at + 16 <= n; at += 16) c += block_has_alpha(p + at);
    return c;
}

} // namespace astc_alpha
