# Use the SDK installed by CI, including its private-framework link stubs.
export TARGET := iphone:clang:16.5:15.0
# Rootless package architecture stays iphoneos-arm64. Its Mach-O binaries
# need both slices for arm64 apps and arm64e system processes on A12+.
# RootHide CI explicitly overrides this with ARCHS=arm64e.
export ARCHS ?= arm64 arm64e

include $(THEOS)/makefiles/common.mk

TWEAK_NAME := RainbowKeyboard
# Safe target: exclude the entire black-keyboard implementation (including its
# direct host entry and diagnostic hook installer), but ALWAYS start preferences.
RainbowKeyboard_FILES := RKPreferencesRelay.m RKBlackKeyboardDisabled.m RKAdaptivePerformance.m Tweak.xm RainbowEffectView.m RKNeonPress.m RKThemeEngine.m RKKeyboardGeometry.m RKBlackBitmap.m CandidateGradient.xm
RainbowKeyboard_CFLAGS := -fobjc-arc -Wno-deprecated-declarations
RainbowKeyboard_FRAMEWORKS := UIKit QuartzCore CoreGraphics

include $(THEOS_MAKE_PATH)/tweak.mk

SUBPROJECTS += RainbowKeyboardPrefs
include $(THEOS_MAKE_PATH)/aggregate.mk

after-stage::
	$(ECHO_NOTHING)find "$(THEOS_STAGING_DIR)" -type f -name '*.plist' -exec chmod 644 {} \;$(ECHO_END)
