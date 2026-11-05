#!/bin/sh
# Собирает DATA-OUT.apk — приложение DATA.OUT для Android (папка android/) — без Gradle:
# значки из icons/icon-512.png → aapt2 (ресурсы и манифест) → javac → d8 → zipalign → apksigner.
#
# Нужны: JDK 17+, python3 с Pillow, curl, unzip. Android SDK скачивается один раз (платформа 35 и build-tools 35)
# в ~/.cache/data-out-android-sdk (или в $ANDROID_SDK_CACHE).
#
# Запуск из корня репозитория:
#   KEYSTORE=/путь/data-out-release.jks KS_PASS='пароль' VERSION_CODE=2 VERSION_NAME=1.1 sh tools/build-apk.sh
# Ключ подписи хранится у автора и в репозиторий не кладётся: новая версия ставится поверх старой,
# только если подписана тем же ключом (иначе старое приложение придётся удалить — прогресс в аккаунте не пропадёт).
set -e
cd "$(dirname "$0")/.."
VC=${VERSION_CODE:-1}
VN=${VERSION_NAME:-1.0}
OUT=${OUT:-DATA-OUT.apk}
SDK=${ANDROID_SDK_CACHE:-$HOME/.cache/data-out-android-sdk}
if [ -z "$KEYSTORE" ] || [ ! -f "$KEYSTORE" ] || [ -z "$KS_PASS" ]; then
  echo "Нужны KEYSTORE=<файл ключа .jks> и KS_PASS=<пароль> (ключ — у автора игры)"; exit 1
fi
export KS_PASS

# ---------- Android SDK ----------
mkdir -p "$SDK"
if [ ! -f "$SDK/platform/android.jar" ]; then
  curl -fsSL -o "$SDK/platform.zip" https://dl.google.com/android/repository/platform-35_r02.zip
  rm -rf "$SDK/platform" "$SDK/android-35"; unzip -q -o "$SDK/platform.zip" -d "$SDK"; mv "$SDK/android-35" "$SDK/platform"; rm "$SDK/platform.zip"
fi
if [ ! -x "$SDK/bt/aapt2" ]; then
  curl -fsSL -o "$SDK/bt.zip" https://dl.google.com/android/repository/build-tools_r35_linux.zip
  rm -rf "$SDK/bt" "$SDK/android-15"; unzip -q -o "$SDK/bt.zip" -d "$SDK"; mv "$SDK/android-15" "$SDK/bt"; rm "$SDK/bt.zip"
fi
JAR="$SDK/platform/android.jar"; BT="$SDK/bt"

B=$(mktemp -d)
trap 'rm -rf "$B"' EXIT
mkdir -p "$B/res" "$B/gen" "$B/classes" "$B/dex"
cp -r android/res/. "$B/res/"

# ---------- значки ----------
# старый значок (до Android 8) — картинка со скруглёнными углами; новый (adaptive) — картинка на фоне
# 108 dp, из которых launcher показывает середину 72 dp по своей форме (круг, «капля», квадрат)
python3 - "$B/res" icons/icon-512.png <<'PY'
import sys, os
from PIL import Image, ImageDraw
res, src = sys.argv[1], sys.argv[2]
im = Image.open(src).convert('RGBA')
edge = im.getpixel((8, 8))
for name, k in [('mdpi', 1), ('hdpi', 1.5), ('xhdpi', 2), ('xxhdpi', 3), ('xxxhdpi', 4)]:
    d = os.path.join(res, 'mipmap-' + name); os.makedirs(d, exist_ok=True)
    n = int(48 * k)
    ic = im.resize((n, n), Image.LANCZOS)
    mask = Image.new('L', (n * 4, n * 4), 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, n * 4 - 1, n * 4 - 1], radius=int(n * 4 * 0.2), fill=255)
    ic.putalpha(mask.resize((n, n), Image.LANCZOS))
    ic.save(os.path.join(d, 'ic_launcher.png'))
    m = int(108 * k); s = int(m * 90 / 108)
    bg = Image.new('RGBA', (m, m), edge)
    bg.paste(im.resize((s, s), Image.LANCZOS), ((m - s) // 2, (m - s) // 2))
    bg.convert('RGB').save(os.path.join(d, 'ic_launcher_bg.png'))
PY

# ---------- ресурсы, код, упаковка, подпись ----------
"$BT/aapt2" compile --dir "$B/res" -o "$B/res.zip"
"$BT/aapt2" link -o "$B/base.apk" -I "$JAR" --manifest android/AndroidManifest.xml \
  --min-sdk-version 24 --target-sdk-version 34 --version-code "$VC" --version-name "$VN" \
  --java "$B/gen" "$B/res.zip"
javac -nowarn -Xlint:-options -source 8 -target 8 -encoding UTF-8 -bootclasspath "$JAR" -d "$B/classes" \
  $(find android/src "$B/gen" -name '*.java')
"$BT/d8" --release --min-api 24 --lib "$JAR" --output "$B/dex" $(find "$B/classes" -name '*.class')
python3 - "$B/base.apk" "$B/dex/classes.dex" <<'PY'
import sys, zipfile
with zipfile.ZipFile(sys.argv[1], 'a', zipfile.ZIP_DEFLATED) as z:
    z.write(sys.argv[2], 'classes.dex')
PY
"$BT/zipalign" -f -p 4 "$B/base.apk" "$B/aligned.apk"
"$BT/apksigner" sign --ks "$KEYSTORE" --ks-pass env:KS_PASS --ks-key-alias dataout --v4-signing-enabled false --out "$OUT" "$B/aligned.apk"
"$BT/apksigner" verify --print-certs "$OUT" | head -3
echo "Готово: $OUT (версия $VN, код $VC)"
