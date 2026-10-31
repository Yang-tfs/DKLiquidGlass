TARGET = iphone:clang:latest:16.0
ARCHS = arm64 arm64e

INSTALL_TARGET_PROCESSES = SpringBoard

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = DKLiquidGlass

# 递归收集，加新文件不用改这里。
DKLiquidGlass_FILES = $(shell find Sources -type f \( -name '*.m' -o -name '*.xm' \) | sort)
DKLiquidGlass_CFLAGS = -fobjc-arc -Wall \
	-ISources -ISources/DKGlass -ISources/TabBar
DKLiquidGlass_FRAMEWORKS = UIKit Foundation QuartzCore CoreGraphics

include $(THEOS_MAKE_PATH)/tweak.mk

after-install::
	install.exec "killall -9 SpringBoard"

# 打包：按越狱环境选 scheme，例如
#   make package THEOS_PACKAGE_SCHEME=rootless   # Dopamine / palera1n rootless
#   make package                                 # 传统 rootful
#   make package THEOS_PACKAGE_SCHEME=roothide   # roothide Bootstrap
# 产物在 ./packages/
