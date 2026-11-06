#!/bin/bash
# usage: install_test_fonts.sh <wineprefix>
# Makes Flash Player in that Wine prefix draw device text (_sans, _serif,
# _typewriter, Arial, Times New Roman, Courier New, ...) with the same Noto Sans
# subset the Rust test harness uses for `with_default_font = true`, so goldens
# recorded there differ from Timffle only in rasterisation, not in the font.
#   1. make_test_fonts.py writes NotoSans-TestRegular.ttf / -TestBold.ttf
#      from core/assets/notosans.subset.ttf.gz (same outlines; see that script)
#   2. copies them into <prefix>/drive_c/windows/Fonts and registers them in
#      HKLM\Software\Microsoft\Windows NT\CurrentVersion\Fonts
#      under the family name "Timffle Test Sans" (the host may have the full
#      Noto Sans, which Wine would mix in)
#   3. points the names Flash asks for at that family: Wine's
#      HKCU\Software\Wine\Fonts\Replacements and HKLM\...\FontSubstitutes
# Use a prefix of your own (never the shared one); it changes how every
# program in that prefix draws those fonts. WINE_DIR = folder with wine.
set -euo pipefail
pfx=${1:?usage: install_test_fonts.sh <wineprefix>}
[ -d "$pfx/drive_c/windows" ] || { echo "not a wine prefix: $pfx" >&2; exit 1; }
here=$(cd "$(dirname "$0")" && pwd)
repo=$(cd "$here/../.." && pwd)
wine=${WINE_DIR:+$WINE_DIR/}wine
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

python3 -I "$here/make_test_fonts.py" "$repo/core/assets/notosans.subset.ttf.gz" "$tmp"
cp "$tmp/NotoSans-TestRegular.ttf" "$tmp/NotoSans-TestBold.ttf" "$pfx/drive_c/windows/Fonts/"

# Names Flash Player 32 on Windows looks up for the default device fonts and
# the common names SWFs ask for directly. Ruffle's harness maps all default
# fonts (sans, serif, typewriter, Japanese) to Noto Sans.
names=("Arial" "Times New Roman" "Courier New" "Verdana" "Tahoma" "Helvetica"
       "Times" "Courier" "MS UI Gothic" "MS Gothic" "MS PGothic" "MS Mincho" "MS PMincho")
{
  printf 'REGEDIT4\r\n\r\n'
  printf '[HKEY_LOCAL_MACHINE\\Software\\Microsoft\\Windows NT\\CurrentVersion\\Fonts]\r\n'
  printf '"Timffle Test Sans (TrueType)"="NotoSans-TestRegular.ttf"\r\n'
  printf '"Timffle Test Sans Bold (TrueType)"="NotoSans-TestBold.ttf"\r\n\r\n'
  printf '[HKEY_LOCAL_MACHINE\\Software\\Microsoft\\Windows NT\\CurrentVersion\\FontSubstitutes]\r\n'
  for n in "${names[@]}"; do printf '"%s"="Timffle Test Sans"\r\n' "$n"; done
  printf '\r\n[HKEY_CURRENT_USER\\Software\\Wine\\Fonts\\Replacements]\r\n'
  for n in "${names[@]}"; do printf '"%s"="Timffle Test Sans"\r\n' "$n"; done
} > "$tmp/fonts.reg"
WINEPREFIX="$pfx" WINEDEBUG=-all "$wine" regedit /S "$(WINEPREFIX="$pfx" "$wine" winepath -w "$tmp/fonts.reg" 2>/dev/null)"
WINEPREFIX="$pfx" "${WINE_DIR:+$WINE_DIR/}wineserver" -w
echo "installed Timffle Test Sans (the harness Noto Sans subset) in $pfx; substituted: ${names[*]}"
