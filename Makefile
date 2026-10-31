TARGET = iphone:clang:latest:16.0
ARCHS = arm64 arm64e

INSTALL_TARGET_PROCESSES = SpringBoard

include $(THEOS)/makefiles/common.mk

# 三个产物共用同一份玻璃核心，只是出口不同：
#   DKLiquidGlass        越狱版 tweak（substrate + Logos）
#   DKLiquidGlassInject  巨魔版纯库（无 substrate），交给 TrollFools 注入
#   DKLiquidGlassDemo    独立演示 App（IPA），TrollStore 直接装

DK_COMMON_CFLAGS = -fobjc-arc -Wall \
	-Wno-error=deprecated-declarations \
	-ISources -ISources/DKGlass -ISources/TabBar -ISources/Host -ISources/Demo
DK_COMMON_FRAMEWORKS = UIKit Foundation QuartzCore CoreGraphics

DK_GLASS_FILES = $(shell find Sources/DKGlass Sources/TabBar -type f -name '*.m' | sort)

# ---------------------------------------------------------------- 越狱版
TWEAK_NAME = DKLiquidGlass
DKLiquidGlass_FILES = $(DK_GLASS_FILES) \
	$(shell find Sources/Host Sources/Preview -type f \( -name '*.m' -o -name '*.xm' \) | sort)
DKLiquidGlass_CFLAGS = $(DK_COMMON_CFLAGS)
DKLiquidGlass_FRAMEWORKS = $(DK_COMMON_FRAMEWORKS)

include $(THEOS_MAKE_PATH)/tweak.mk

after-install::
	install.exec "killall -9 SpringBoard"

# ---------------------------------------------------------------- 巨魔版
# 排掉 Sources/Preview：那是 %hook SpringBoard，会引入 substrate 运行时依赖，
# 注入后 dlopen 会直接失败。
LIBRARY_NAME = DKLiquidGlassInject
DKLiquidGlassInject_FILES = $(DK_GLASS_FILES) \
	$(shell find Sources/Host -type f -name '*.m' | sort)
DKLiquidGlassInject_CFLAGS = $(DK_COMMON_CFLAGS)
DKLiquidGlassInject_FRAMEWORKS = $(DK_COMMON_FRAMEWORKS)
DKLiquidGlassInject_INSTALL_PATH = /usr/lib

include $(THEOS_MAKE_PATH)/library.mk

# ---------------------------------------------------------------- 演示 App
# 不含 Sources/Host：那里面有个自动挂载的 constructor，会和 Demo 自己的底栏重复。
APPLICATION_NAME = DKLiquidGlassDemo
DKLiquidGlassDemo_FILES = $(DK_GLASS_FILES) Sources/Demo/main.m
DKLiquidGlassDemo_CFLAGS = $(DK_COMMON_CFLAGS)
DKLiquidGlassDemo_FRAMEWORKS = $(DK_COMMON_FRAMEWORKS)
DKLiquidGlassDemo_CODESIGN_FLAGS = -S

include $(THEOS_MAKE_PATH)/application.mk

# 打包：
#   make package                                 # 传统 rootful
#   make package THEOS_PACKAGE_SCHEME=rootless   # Dopamine / palera1n rootless
#   make package THEOS_PACKAGE_SCHEME=roothide   # roothide Bootstrap
#
# 巨魔用户不用打包：
#   .theos/obj/DKLiquidGlassInject.dylib  → TrollFools 注入
#   .theos/obj/DKLiquidGlassDemo.app      → 打成 Payload/ 后 zip 成 IPA
