#!/system/bin/sh

# Discover and stop built-in Dolby audio HAL services. The init service NAME
# differs from the binary path (e.g. 'dms-sp-hal-2-0' for
# vendor.dolby_sp.hardware.dmssp@2.0-service), so we scan the init rc files
# for dolby dms/dax binaries and stop the declared services. Only the Dolby
# AUDIO HAL services are matched ('dmssp'/'dms'/'dax'); Dolby Vision codec
# services (dvs/c2) are left untouched.
for RC in /odm/etc/init/*.rc /vendor/etc/init/*.rc /system/etc/init/*.rc; do
  [ -f "$RC" ] || continue
  grep -Eq 'vendor\.dolby[^ ]*(dmssp|dms|dax)' "$RC" || continue
  SVC="$(sed -n 's/^service \([^ ]*\) .*/\1/p' "$RC" | head -n1)"
  [ -n "$SVC" ] || continue
  stop "$SVC" 2>/dev/null
done

# Disable known Dolby service apps if any are present (non-fatal).
for PKG in com.dolby.daxservice com.dolby com.oplus.soundfx; do
  pm path "$PKG" >/dev/null 2>&1 && pm disable-user --user 0 "$PKG" 2>/dev/null
done
