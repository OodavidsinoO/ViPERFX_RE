echo -n $LIBPATCH > $MODPATH/libpatch.txt

ui_print "    Copying lib files..."

cp_ch -n $MODPATH/common/files/libv4a_re_$ABI32.so $MODPATH$LIBDIR/lib/soundfx/libv4a_re.so
if [ "$IS64BIT" ]; then
cp_ch -n $MODPATH/common/files/libv4a_re_$ABI.so $MODPATH$LIBDIR/lib64/soundfx/libv4a_re.so
fi

# Mirror the stock soundfx libraries next to the driver. On KernelSU without
# a metamodule, post-fs-data.sh bind-mounts the whole soundfx directory (the
# per-file target /vendor/lib64/soundfx/libv4a_re.so does not exist on stock
# ROMs, so per-file binds are impossible); the mirror keeps the stock libs
# visible under the bind. Magisk/metamodule installs ignore the mirror.
for SDIR in lib64 lib; do
  if [ -d /vendor/$SDIR/soundfx ]; then
    SRC=/vendor/$SDIR/soundfx
  elif [ -d /system/$SDIR/soundfx ]; then
    SRC=/system/$SDIR/soundfx
  else
    continue
  fi
  MKDIR=$MODPATH$LIBDIR/$SDIR/soundfx
  mkdir -p $MKDIR
  cp -a $SRC/. $MKDIR/ 2>/dev/null
done

ui_print "    Patching audio_effects config files"

# Built-in (Dolby / OPPO / etc.) sound effects are stripped generically:
# by library name, by lib path keywords, and by effect/apply name. No device
# or ROM-specific hardcoding - devices without such effects are untouched.
DENY_LIB_NAMES='dap|dvl|spatializer|gamedap|ozo_processing|opupmix|vqe'
DENY_LIB_PATHS='swdap|dlbvol|swgamedap|oplus_spatializer|oplusupmix|ozoprocessing|swvqe|dolby|dax'
DENY_EFFECTS='dlb_[a-z_]*_listener|dap|spatializer|gamedap|ozo|oplusupmix|vqe'

CFGS="$(find /odm /system /vendor -type f -name "*audio_effects*.conf" -o -name "*audio_effects*.xml")"
for OFILE in ${CFGS}; do
  FILE="$MODPATH$(echo $OFILE | sed "s|^/vendor|/system/vendor|g")"
  cp_ch -n $OFILE $FILE
  case $FILE in
    *.conf)
        sed -i "/v4a_standard_re {/,/}/d" $FILE
        sed -i "/v4a_re {/,/}/d" $FILE
        sed -i -E "/^[[:space:]]*(${DENY_LIB_NAMES}) \{/,/^[[:space:]]*\}/d" $FILE
        sed -i -E "/^[[:space:]]*(${DENY_EFFECTS}) \{/,/^[[:space:]]*\}/d" $FILE
        sed -i "s/^effects {/effects {\n  v4a_standard_re {\n    library v4a_re\n    uuid 90380da3-8536-4744-a6a3-5731970e640f\n  }/g" $FILE
        sed -i "s/^libraries {/libraries {\n  v4a_re {\n    path $LIBPATCH\/lib\/soundfx\/libv4a_re.so\n  }/g" $FILE
        ;;
    *.xml)
        sed -i "/v4a_standard_re/d" $FILE
        sed -i "/v4a_re/d" $FILE
        sed -i -E "/<library[^>]*name=\"(${DENY_LIB_NAMES})\"/d" $FILE
        sed -i -E "/<library[^>]*path=\"[^\"]*(${DENY_LIB_PATHS})[^\"]*\"/d" $FILE
        sed -i -E "/<effect[^>]*library=\"(${DENY_LIB_NAMES})\"/d" $FILE
        sed -i -E "/<apply[^>]*effect=\"(${DENY_EFFECTS})\"/d" $FILE
        sed -i "/<libraries>/ a\        <library name=\"v4a_re\" path=\"libv4a_re.so\"\/>" $FILE
        sed -i "/<effects>/ a\        <effect name=\"v4a_standard_re\" library=\"v4a_re\" uuid=\"90380da3-8536-4744-a6a3-5731970e640f\"\/>" $FILE
        ;;
  esac
done
