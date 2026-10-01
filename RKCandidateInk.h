#pragma once
#include <stddef.h>
#include <stdint.h>
#include <stdbool.h>

// Input is RGBA8 premultiplied-last, as created by the native glyph capture.
// Shares the existing ink-bounds pass; no extra image or pixel traversal.
typedef struct { size_t minX, maxX; bool chromatic; } RKCandidateInk;
static inline RKCandidateInk RKScanCandidateInk(const uint8_t *bytes, size_t width, size_t height) {
    RKCandidateInk ink = {width, 0, false};
    for (size_t y = 0; y < height; y++) {
        for (size_t x = 0; x < width; x++) {
            const uint8_t *p = bytes + (y * width + x) * 4;
            if (p[3] <= 8) continue;
            if (x < ink.minX) ink.minX = x;
            if (x > ink.maxX) ink.maxX = x;
            if (!ink.chromatic) {
                unsigned hi = p[0] > p[1] ? p[0] : p[1];
                unsigned lo = p[0] < p[1] ? p[0] : p[1];
                if (p[2] > hi) hi = p[2];
                if (p[2] < lo) lo = p[2];
                // Tolerate rounding noise, but preserve low-alpha color too.
                ink.chromatic = (hi - lo > 3);
            }
        }
    }
    return ink;
}
