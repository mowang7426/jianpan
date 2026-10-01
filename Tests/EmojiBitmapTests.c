#include <assert.h>
#include <stdio.h>
#include <string.h>
#include "RKCandidateInk.h"
#include "RKCandidateEmojiData.h"
int main(void) {
    uint8_t pixels[17 * 9 * 4];
    unsigned seed = 71;
    for (unsigned round = 0; round < 300; round++) {
        for (size_t i = 0; i < sizeof(pixels); i++) {
            seed = seed * 1664525u + 1013904223u;
            pixels[i] = seed >> 24;
        }
        if (round == 0) memset(pixels, 0, sizeof(pixels));
        size_t min = 17, max = 0;
        for (size_t y = 0; y < 9; y++) for (size_t x = 0; x < 17; x++)
            if (pixels[(y * 17 + x) * 4 + 3] > 8) {
                if (x < min) min = x;
                if (x > max) max = x;
            }
        RKCandidateInk ink = RKScanCandidateInk(pixels, 17, 9);
        assert(ink.minX == min && ink.maxX == max);
    }
    uint8_t transparent[] = {255,0,0,0};
    uint8_t gray[] = {100,100,100,255};
    uint8_t rounding[] = {100,102,103,255};
    uint8_t alphaColor[] = {0,4,9,9};
    assert(!RKScanCandidateInk(transparent,1,1).chromatic);
    assert(!RKScanCandidateInk(gray,1,1).chromatic);
    assert(!RKScanCandidateInk(rounding,1,1).chromatic);
    assert(RKScanCandidateInk(alphaColor,1,1).chromatic);
    assert(RKCandidateEmojiScalar(0x1F600));
    assert(RKCandidateEmojiScalar(0x1F3FD));
    assert(RKCandidateEmojiScalar(0x1F1E8));
    assert(!RKCandidateEmojiScalar('1') && !RKCandidateEmojiScalar('#') && !RKCandidateEmojiScalar('*'));
    assert(!RKCandidateEmojiScalar(0x4E2D));
    puts("PASS production bitmap bounds differential (300 fixtures), alpha/color and scalar tests");
}
