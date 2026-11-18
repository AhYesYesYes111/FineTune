#!/bin/bash
set -euo pipefail

# Build an independent, ad-hoc signed preview. No Apple signing secrets required.
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_DIR"
TAG="${1:-airpods-preview-2026.11.18.1}"
if [[ ! "$TAG" =~ ^airpods-preview-[0-9]{4}\.[0-9]{2}\.[0-9]{2}\.[0-9]+$ ]]; then
    echo "Expected a tag such as airpods-preview-2026.11.18.1" >&2
    exit 1
fi

DERIVED_DATA="$PROJECT_DIR/build/fork-release"
PACKAGES_DIR="${FINETUNE_PACKAGES_DIR:-$PROJECT_DIR/build/fork-packages}"
OUTPUT_DIR="$PROJECT_DIR/build/downloads/$TAG"
BUILD_NUMBER="${FINETUNE_BUILD_NUMBER:-2026111801}"
SOURCE_COMMIT="$(git rev-parse HEAD)"
SOURCE_REPO="${GITHUB_REPOSITORY:-AhYesYesYes111/FineTune}"
ASSET_NAME="FineTune-$TAG-arm64"
if [[ -n "$(git status --porcelain)" ]]; then
    echo "Commit source changes before packaging so the source link matches the binary." >&2
    exit 1
fi
mkdir -p "$OUTPUT_DIR"

xcodebuild -project FineTune.xcodeproj -scheme FineTune \
    -configuration Release -destination 'platform=macOS,arch=arm64' \
    -derivedDataPath "$DERIVED_DATA" \
    -clonedSourcePackagesDirPath "$PACKAGES_DIR" \
    -disablePackageRepositoryCache -skipPackageUpdates \
    -onlyUsePackageVersionsFromResolvedFile \
    CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM= \
    CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO \
    PROVISIONING_PROFILE_SPECIFIER= ARCHS=arm64 ONLY_ACTIVE_ARCH=YES \
    MARKETING_VERSION=1.9.0 CURRENT_PROJECT_VERSION="$BUILD_NUMBER" \
    'SWIFT_ACTIVE_COMPILATION_CONDITIONS=$(inherited) FINETUNE_FORK_BUILD' \
    'OTHER_LDFLAGS=$(inherited) -Wl,-dead_strip_dylibs' \
    build

STAGING_DIR="$(mktemp -d "$PROJECT_DIR/build/fork-package.XXXXXX")"
trap 'rm -rf "$STAGING_DIR"' EXIT
PACKAGE_DIR="$STAGING_DIR/FineTune-AirPods-Preview"
mkdir -p "$PACKAGE_DIR"
ditto --norsrc --noextattr "$DERIVED_DATA/Build/Products/Release/FineTune.app" "$PACKAGE_DIR/FineTune.app"

# The compiled fork flag disables Sparkle entirely. Remove the upstream feed/key
# from the distributed metadata too, so this package identifies no update server.
/usr/libexec/PlistBuddy -c 'Delete :SUFeedURL' "$PACKAGE_DIR/FineTune.app/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Delete :SUPublicEDKey' "$PACKAGE_DIR/FineTune.app/Contents/Info.plist"
if otool -L "$PACKAGE_DIR/FineTune.app/Contents/MacOS/FineTune" | grep -q '/Sparkle.framework/'; then
    echo 'Fork binary still loads Sparkle; refusing to package an incompatible updater.' >&2
    exit 1
fi
rm -rf "$PACKAGE_DIR/FineTune.app/Contents/Frameworks/Sparkle.framework"
codesign --force --sign - --timestamp=none \
    --preserve-metadata=entitlements,flags,requirements "$PACKAGE_DIR/FineTune.app"
codesign --verify --deep --strict --verbose=2 "$PACKAGE_DIR/FineTune.app"

cp LICENSE "$PACKAGE_DIR/LICENSE"
mkdir -p "$PACKAGE_DIR/Third-Party-Licenses"
cp "$PACKAGES_DIR/checkouts/FluidMenuBarExtra/LICENSE" "$PACKAGE_DIR/Third-Party-Licenses/FluidMenuBarExtra.txt"
cp "$PACKAGES_DIR/checkouts/KeyboardShortcuts/license" "$PACKAGE_DIR/Third-Party-Licenses/KeyboardShortcuts.txt"
cp "$PACKAGES_DIR/checkouts/Sparkle/LICENSE" "$PACKAGE_DIR/Third-Party-Licenses/Sparkle.txt"
cat > "$PACKAGE_DIR/INSTALL.txt" <<EOF
FineTune AirPods Preview — $TAG

适用于 Apple Silicon（M1 或更新芯片），macOS 15.4 或更新系统。
这是 AhYesYesYes111/FineTune 的独立测试版，不是原作者的官方发行版。

安装：先退出已运行的 FineTune，备份旧版，然后将 FineTune.app 放入“应用程序”。
不要同时启动两个版本。顶部 ⇅ 按钮灰色时跟随 macOS，亮起时使用 FineTune 的设备优先级。
Chrome、Music 等应用若指定了固定输出，请选 System Audio 才会跟随系统。
本预览版没有自动更新；后续版本请从下面的仓库 Releases 下载。

This is an Apple Silicon preview for macOS 15.4 or newer.
It is ad-hoc signed and is NOT Apple-notarized. macOS may block the first launch.
Quit any running FineTune before installing, and keep a backup of your old app.
Automatic and manual in-app updates are disabled in this fork build.

Original project: https://github.com/ronitsingh10/FineTune
Preview releases: https://github.com/$SOURCE_REPO/releases
Corresponding source: https://github.com/$SOURCE_REPO/tree/$SOURCE_COMMIT
Source commit: $SOURCE_COMMIT
License: GNU GPL version 3; see LICENSE and the corresponding source repository.
EOF

ditto -c -k --norsrc --noextattr --keepParent "$PACKAGE_DIR" "$OUTPUT_DIR/$ASSET_NAME.zip"
ln -s /Applications "$PACKAGE_DIR/Applications"
hdiutil create -volname 'FineTune AirPods Preview' -srcfolder "$PACKAGE_DIR" \
    -format UDZO -ov "$OUTPUT_DIR/$ASSET_NAME.dmg"
hdiutil verify "$OUTPUT_DIR/$ASSET_NAME.dmg"
(cd "$OUTPUT_DIR" && shasum -a 256 "$ASSET_NAME.zip" "$ASSET_NAME.dmg" > SHA256SUMS.txt)
cp "$PACKAGE_DIR/INSTALL.txt" "$OUTPUT_DIR/INSTALL.txt"
cat > "$OUTPUT_DIR/RELEASE-NOTES.txt" <<EOF
这是本仓库的 AirPods 自动切换测试版，基于 FineTune 1.9.0。

- 默认尊重 macOS 的音频输出切换；戴上 AirPods 时不再强制切回优先级列表中的设备。
- 菜单面板顶部新增小型 ⇅ 按钮：灰色为跟随 macOS，亮起为启用 FineTune 输出优先级。
- 改善设备连接、断开和连续切换时的应用音频路由。
- 此分支包使用手动下载更新，不会通过原作者的自动更新源替换安装。

**下载：** 推荐 DMG；ZIP 提供相同应用。仅支持 Apple Silicon（M1 及更新芯片），macOS 15.4+。

**验证：** 音频切换改动已通过 35 项 Xcode 测试（含参数共 50 次执行），并在 MacBook Pro + AirPods 上确认自动切换、播放和断开回退。

**安装：** 先退出其他 FineTune 版本，保留旧版备份，再把 FineTune.app 拖入“应用程序”。⇅ 保持灰色即可跟随系统；单独指定输出的应用需选 System Audio。

**签名：** 本包为 ad-hoc 签名，尚未经过 Apple 公证，macOS 可能阻止首次启动。这是独立分支预览版，不是原作者的官方发行版。

源代码与构建脚本：https://github.com/$SOURCE_REPO/tree/$SOURCE_COMMIT
原项目：https://github.com/ronitsingh10/FineTune
许可：GNU GPL v3；安装包附带 LICENSE。下载文件的 SHA-256 见 SHA256SUMS.txt。
EOF
printf 'Download packages: %s\n' "$OUTPUT_DIR"
