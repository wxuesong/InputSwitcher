#!/bin/bash
# 构建 InputSwitcher.app(仅 Apple 芯片 arm64,最低 macOS 13)
set -euo pipefail
cd "$(dirname "$0")"

APP=InputSwitcher
OUT=build/$APP.app
ENABLE_SANDBOX=${ENABLE_SANDBOX:-false}
ENABLE_ICLOUD=${ENABLE_ICLOUD:-false}
BUNDLE_ID=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' Info.plist)

for value in "$ENABLE_SANDBOX" "$ENABLE_ICLOUD"; do
    if [ "$value" != "true" ] && [ "$value" != "false" ]; then
        echo "错误: ENABLE_SANDBOX 和 ENABLE_ICLOUD 只能是 true 或 false" >&2
        exit 1
    fi
done

rm -rf build
mkdir -p "$OUT/Contents/MacOS"
mkdir -p "$OUT/Contents/Resources"

swiftc -O -parse-as-library \
    -target arm64-apple-macos13.0 \
    Sources/*.swift \
    -o "$OUT/Contents/MacOS/$APP"

cp Info.plist "$OUT/Contents/Info.plist"

# 复制图标文件(如果存在)
if [ -f "Resources/InputSwitcher.icns" ]; then
    cp "Resources/InputSwitcher.icns" "$OUT/Contents/Resources/"
fi

# 复制菜单栏图标(如果存在)
if [ -f "Resources/MenuBarIcon.png" ]; then
    cp "Resources/MenuBarIcon.png" "$OUT/Contents/Resources/"
fi
if [ -f "Resources/MenuBarIcon@2x.png" ]; then
    cp "Resources/MenuBarIcon@2x.png" "$OUT/Contents/Resources/"
fi
if [ -f "Resources/MenuBarIcon_dark.png" ]; then
    cp "Resources/MenuBarIcon_dark.png" "$OUT/Contents/Resources/"
fi
if [ -f "Resources/MenuBarIcon_dark@2x.png" ]; then
    cp "Resources/MenuBarIcon_dark@2x.png" "$OUT/Contents/Resources/"
fi
# 复制本地化文件
if [ -d "Resources/Localizations" ]; then
    mkdir -p "$OUT/Contents/Resources/Localizations"
    cp Resources/Localizations/*.strings "$OUT/Contents/Resources/Localizations/" 2>/dev/null || true

    # 复制系统元数据的标准本地化资源（例如 Finder 中显示的应用名称）
    for locale in en zh-Hans zh-Hant ja ko de fr es pt-BR; do
        if [ -f "Resources/Localizations/$locale.lproj/InfoPlist.strings" ]; then
            mkdir -p "$OUT/Contents/Resources/$locale.lproj"
            cp "Resources/Localizations/$locale.lproj/InfoPlist.strings" \
                "$OUT/Contents/Resources/$locale.lproj/InfoPlist.strings"
        fi
    done
fi

if [ -f "Resources/PrivacyInfo.xcprivacy" ]; then
    cp "Resources/PrivacyInfo.xcprivacy" "$OUT/Contents/Resources/PrivacyInfo.xcprivacy"
fi

# iCloud KVS 只能在具有有效 Team、证书和 provisioning profile 的构建中使用。
if [ "$ENABLE_ICLOUD" = "true" ] || [ "$ENABLE_SANDBOX" = "true" ]; then
    : "${DEVELOPMENT_TEAM:?错误: 请设置 DEVELOPMENT_TEAM}"
    : "${CODE_SIGN_IDENTITY:?错误: 请设置 CODE_SIGN_IDENTITY}"
    : "${PROVISIONING_PROFILE:?错误: 请设置 PROVISIONING_PROFILE 文件路径}"

    if [ ! -f "$PROVISIONING_PROFILE" ]; then
        echo "错误: 找不到 provisioning profile: $PROVISIONING_PROFILE" >&2
        exit 1
    fi

    if ! security find-identity -v -p codesigning | grep -F "$CODE_SIGN_IDENTITY" >/dev/null; then
        echo "错误: 钥匙串中找不到签名身份: $CODE_SIGN_IDENTITY" >&2
        exit 1
    fi

    TEAM_IDENTIFIER_PREFIX=${TEAM_IDENTIFIER_PREFIX:-$DEVELOPMENT_TEAM.}
    case "$TEAM_IDENTIFIER_PREFIX" in
        *.) ;;
        *) TEAM_IDENTIFIER_PREFIX="$TEAM_IDENTIFIER_PREFIX." ;;
    esac
    KVS_IDENTIFIER=${KVS_IDENTIFIER:-$TEAM_IDENTIFIER_PREFIX$BUNDLE_ID}
    RESOLVED_ENTITLEMENTS=build/$APP.resolved.entitlements
    PROFILE_PLIST=build/$APP.provisioning-profile.plist

    if ! security cms -D -i "$PROVISIONING_PROFILE" > "$PROFILE_PLIST"; then
        echo "错误: 无法解析 provisioning profile" >&2
        exit 1
    fi

    PROFILE_TEAM=$(/usr/libexec/PlistBuddy -c \
        'Print :Entitlements:com.apple.developer.team-identifier' \
        "$PROFILE_PLIST" 2>/dev/null || true)
    PROFILE_APP_ID=$(/usr/libexec/PlistBuddy -c \
        'Print :Entitlements:com.apple.application-identifier' \
        "$PROFILE_PLIST" 2>/dev/null || true)
    PROFILE_KVS_IDENTIFIER=$(/usr/libexec/PlistBuddy -c \
        'Print :Entitlements:com.apple.developer.ubiquity-kvstore-identifier' \
        "$PROFILE_PLIST" 2>/dev/null || true)

    if [ "$PROFILE_TEAM" != "$DEVELOPMENT_TEAM" ]; then
        echo "错误: provisioning profile 的 Team ($PROFILE_TEAM) 与 DEVELOPMENT_TEAM 不一致" >&2
        exit 1
    fi
    if [ "$PROFILE_APP_ID" != "$TEAM_IDENTIFIER_PREFIX$BUNDLE_ID" ]; then
        echo "错误: provisioning profile 不匹配 $BUNDLE_ID: $PROFILE_APP_ID" >&2
        exit 1
    fi
    if [ "$ENABLE_ICLOUD" = "true" ] && [ "$PROFILE_KVS_IDENTIFIER" != "$KVS_IDENTIFIER" ]; then
        echo "错误: provisioning profile 未授权 KVS identifier: $KVS_IDENTIFIER" >&2
        exit 1
    fi

    cp InputSwitcher.entitlements "$RESOLVED_ENTITLEMENTS"
    /usr/libexec/PlistBuddy -c \
        "Set :com.apple.developer.ubiquity-kvstore-identifier $KVS_IDENTIFIER" \
        "$RESOLVED_ENTITLEMENTS"
    /usr/libexec/PlistBuddy -c \
        "Add :com.apple.application-identifier string $PROFILE_APP_ID" \
        "$RESOLVED_ENTITLEMENTS"
    /usr/libexec/PlistBuddy -c \
        "Add :com.apple.developer.team-identifier string $PROFILE_TEAM" \
        "$RESOLVED_ENTITLEMENTS"

    if [ "$ENABLE_ICLOUD" != "true" ]; then
        /usr/libexec/PlistBuddy -c \
            'Delete :com.apple.developer.ubiquity-kvstore-identifier' \
            "$RESOLVED_ENTITLEMENTS"
    fi

    if [ "$ENABLE_SANDBOX" = "true" ]; then
        /usr/libexec/PlistBuddy -c 'Add :com.apple.security.app-sandbox bool true' \
            "$RESOLVED_ENTITLEMENTS"
    fi

    cp "$PROVISIONING_PROFILE" "$OUT/Contents/embedded.provisionprofile"
    codesign --force \
        --sign "$CODE_SIGN_IDENTITY" \
        --entitlements "$RESOLVED_ENTITLEMENTS" \
        --options runtime \
        "$OUT"
    codesign --verify --deep --strict --verbose=2 "$OUT"

    if [ "$ENABLE_ICLOUD" = "true" ]; then
        SIGNED_ENTITLEMENTS=$(codesign -d --entitlements :- "$OUT" 2>&1)
        if [[ "$SIGNED_ENTITLEMENTS" != *"$KVS_IDENTIFIER"* ]]; then
            echo "错误: 签名产物缺少预期的 iCloud KVS entitlement" >&2
            exit 1
        fi
        echo "iCloud KVS: $KVS_IDENTIFIER"
    fi
else
    echo "使用 ad-hoc 本地签名（iCloud 同步不可用）"
    codesign --force --sign - "$OUT"
fi

echo "构建完成: $OUT"
echo "运行: open \"$OUT\""
echo ""
if [ "$ENABLE_ICLOUD" = "false" ]; then
    echo "提示: iCloud 构建需要 Apple Developer 签名，详见 README.md"
fi
