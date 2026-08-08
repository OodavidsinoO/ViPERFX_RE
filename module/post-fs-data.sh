#!/system/bin/sh
MODDIR=${0%/*}

# ViPER4Android-RE boot script.
# - Magisk / KernelSU with a metamodule: module files are already in place,
#   nothing to do here.
# - KernelSU / APatch WITHOUT a metamodule: module files are never mounted, so
#   bind-mount the driver dirs and the patched audio_effects configs ourselves
#   and restore the stock SELinux label on the bound files so audioserver may
#   use them. This makes the module fully self-sufficient on KernelSU.

v4alog() { /system/bin/log -p i -t v4a_re "$*" 2>/dev/null || echo "v4a_re: $*" >&2; }

MOUNTED="$MODDIR/.mounted"
: > "$MOUNTED"

bind_file() {
  [ -f "$1" ] || return 0
  [ -e "$2" ] || { v4alog "target missing: $2"; return 1; }
  LABEL="$(ls -Zd "$2" 2>/dev/null | awk '{print $1}')"
  mount -o bind "$1" "$2" 2>/dev/null || { v4alog "bind failed: $1 -> $2"; return 1; }
  [ -n "$LABEL" ] && chcon "$LABEL" "$1" 2>/dev/null
  echo "$2" >> "$MOUNTED"
  v4alog "bound $2"
}

bind_dir() {
  [ -d "$1" ] || return 0
  [ -d "$2" ] || { v4alog "target dir missing: $2"; return 1; }
  mount -o bind "$1" "$2" 2>/dev/null || { v4alog "dir bind failed: $1 -> $2"; return 1; }
  echo "$2" >> "$MOUNTED"
  v4alog "bound dir $2"
}

# 1) ODM configs first: Magisk magic mount and most metamodules do NOT mount
#    the module's /odm tree, so bind them explicitly whenever present.
find "$MODDIR/odm" -type f \( -name "*audio_effects*.conf" -o -name "*audio_effects*.xml" \) 2>/dev/null | while IFS= read -r CFG; do
  [ -n "$CFG" ] || continue
  REL="${CFG#$MODDIR/}"
  case "$REL" in
    odm/*) bind_file "$CFG" "/odm/${REL#odm/}" ;;
  esac
done

# 2) If a non-empty driver is already visible, Magisk / metamodule mounted
#    the module tree; everything else is in place.
if [ -s /vendor/lib64/soundfx/libv4a_re.so ]; then
  exit 0
fi

# 3) KernelSU / APatch without a metamodule: bind the soundfx dirs (install.sh
#    mirrored the stock libs next to the driver) and the patched configs.
bind_dir "$MODDIR/system/vendor/lib64/soundfx" /vendor/lib64/soundfx
bind_dir "$MODDIR/system/vendor/lib/soundfx" /vendor/lib/soundfx

find "$MODDIR/system" -type f \( -name "*audio_effects*.conf" -o -name "*audio_effects*.xml" \) 2>/dev/null | while IFS= read -r CFG; do
  [ -n "$CFG" ] || continue
  REL="${CFG#$MODDIR/}"
  case "$REL" in
    system/vendor/*) bind_file "$CFG" "/vendor/${REL#system/vendor/}" ;;
    system/*) bind_file "$CFG" "/system/${REL#system/}" ;;
  esac
done
