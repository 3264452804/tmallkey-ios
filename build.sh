#!/bin/bash
# 在本机 Mac 上构建未签名 IPA（需要 Xcode + xcodegen）
set -e
cd "$(dirname "$0")"
command -v xcodegen >/dev/null || brew install xcodegen
xcodegen generate
xcodebuild -project VocLock.xcodeproj -scheme VocLock -configuration Release \
  -sdk iphoneos -derivedDataPath build \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO
mkdir -p Payload
cp -R build/Build/Products/Release-iphoneos/VocLock.app Payload/
zip -qr VocLock-unsigned.ipa Payload
echo "✅ 产出：$(pwd)/VocLock-unsigned.ipa"
