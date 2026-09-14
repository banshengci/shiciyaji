#!/bin/bash
# 诗词雅集 · iOS IPA 构建脚本
# ---------------------------------------------------------------
# 适用：无 Apple 开发者账号，通过 TrollStore（巨魔）自签安装
# 环境：macOS + Xcode + Flutter SDK + CocoaPods
# 用法：bash tools/build_ios_ipa.sh
# 产物：build/ios/shici_yaji.ipa
# ---------------------------------------------------------------
set -euo pipefail

cd "$(dirname "$0")/.."
ROOT="$(pwd)"
IPA="$ROOT/build/ios/shici_yaji.ipa"

echo "==> 1/5 拉取 Flutter 依赖"
flutter pub get

echo "==> 2/5 安装 CocoaPods 依赖"
# 注意：必须先 pub get 再 pod install。
# Podfile 依赖 Flutter/Generated.xcconfig 里的 FLUTTER_ROOT，
# 该文件由 flutter pub get 生成，若缺失 pod install 会直接报
# "FLUTTER_ROOT not found"。Windows 上生成的旧文件指向 Windows 路径，
# pub get 会重新生成成本机（macOS）路径。
cd "$ROOT/ios"
pod install
cd "$ROOT"

echo "==> 3/5 构建 Release（跳过代码签名）"
# --no-codesign：不要求开发者账号。TrollStore 安装时会自行处理签名。
flutter build ios --release --no-codesign

echo "==> 4/5 打包 IPA"
cd "$ROOT/build/ios/iphoneos"
rm -rf Payload
rm -f "$IPA"
mkdir -p Payload
cp -R Runner.app Payload/
# -y 保留符号链接（Flutter.framework 依赖符号链接），
# 不加会导致安装后启动闪退。
zip -qry "$IPA" Payload
cd "$ROOT"

echo "==> 5/5 完成"
ls -lh "$IPA"
echo ""
echo "IPA 已生成: $IPA"
echo "将该文件通过 TrollStore 安装即可（无需开发者账号）。"
