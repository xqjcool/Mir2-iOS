#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
echo '1/3 检查应用配置'
plutil -lint Info.plist MirOffline.xcodeproj/project.pbxproj
echo '2/3 测试实际使用的 Swift 寻路代码'
swift test
echo '3/3 编译 iOS 模拟器应用（无需签名）'
xcodebuild -project MirOffline.xcodeproj -scheme MirOffline -configuration Debug \
  -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath .build-xcode CODE_SIGNING_ALLOWED=NO build
echo '验证完成；在 Xcode 选择具体模拟器或 iPhone 后运行。'
