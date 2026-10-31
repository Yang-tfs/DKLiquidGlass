TARGET = iphone:clang:latest:16.0
ARCHS = arm64 arm64e

INSTALL_TARGET_PROCESSES = SpringBoard

include $(THEOS)/makefiles/common.mk

# ---------------------------------------------------------------- 越狱版
# 走 MobileSubstrate 注入，含 Logos hook。
# 巨魔（TrollStore）用不上这条：那里没有 substrate，deb 不会被加载。

TWEAK_NAME = DKLiquidGlass

DKLiquidGlass_FILES = $(shell find Sources -type f \( -name '*.m' -o -name '*.xm' \) | sort)
DKLiquidGlass_CFLAGS = -fobjc-arc -Wall \
	-Wno-error=deprecated-declarations \
	-ISources -ISources/DKGlass -ISources/TabBar -ISources/Host
DKLiquidGlass_FRAMEWORKS = UIKit Foundation QuartzCore CoreGraphics

include $(THEOS_MAKE_PATH)/tweak.mk

after-install::
	install.exec "killall -9 SpringBoard"

# ---------------------------------------------------------------- 巨魔版
# 纯库，不含任何 Logos / substrate 依赖，供 TrollFools 注入到目标 App。
# 排掉 Sources/Preview：那里面是 %hook SpringBoard，会引入 substrate 运行时依赖。

LIBRARY_NAME = DKLiquidGlassInject

DKLiquidGlassInject_FILES = $(shell find Sources -type f \( -name '*.m' -o -name '*.mm' \) | grep -v '/Preview/' | sort)
DKLiquidGlassInject_CFLAGS = $(DKLiquidGlass_CFLAGS)
DKLiquidGlassInject_FRAMEWORKS = $(DKLiquidGlass_FRAMEWORKS)
DKLiquidGlassInject_INSTALL_PATH = /usr/lib

include $(THEOS_MAKE_PATH)/library.mk

# 打包：按越狱环境选 scheme，例如
#   make package THEOS_PACKAGE_SCHEME=rootless   # Dopamine / palera1n rootless
#   make package                                 # 传统 rootful
#   make package THEOS_PACKAGE_SCHEME=roothide   # roothide Bootstrap
# 产物在 ./packages/
#
# 巨魔用户不用打包，直接取 .theos/obj/DKLiquidGlassInject.dylib 交给 TrollFools。
