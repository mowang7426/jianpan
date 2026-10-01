#pragma once
// This branch builds without PureBlackKeyboard.xm. Shared by the renderer and
// settings UI so unavailable keycap themes cannot silently override live effects.
#define RK_SAFE_TEST_BUILD 1
