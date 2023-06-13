#!/system/bin/sh

log_dir="/cache/phh"
log_file="$log_dir/logs"

if [ -z "$debug" ] && [ -f "/cache/phh-log" ]; then
    mkdir -p "$log_dir"
    debug=1 exec sh -x "$(readlink -f -- "$0")" > "$log_file" 2>&1
else
    chmod 0755 "$log_dir"
    chmod 0644 "$log_file"
fi

if [ -f "/cache/phh-adb" ]; then
    setprop ctl.stop adbd adbd_apex
    mount -t configfs none /config
    rm -rf /config/usb_gadget
    mkdir -p /config/usb_gadget/g1

    echo 0x12d1 > /config/usb_gadget/g1/idVendor
    echo 0x103A > /config/usb_gadget/g1/idProduct
    mkdir -p /config/usb_gadget/g1/strings/0x409
    for str in serialnumber manufacturer product; do
        echo phh > "/config/usb_gadget/g1/strings/0x409/$str"
    done

    for func in ffs.adb mtp.gs0 ptp.gs1; do
        mkdir "/config/usb_gadget/g1/functions/$func"
    done

    mkdir -p "/config/usb_gadget/g1/configs/c.1/strings/0x409"
    echo 'ADB MTP' > "/config/usb_gadget/g1/configs/c.1/strings/0x409/configuration"

    mkdir /dev/usb-ffs
    chmod 0770 /dev/usb-ffs
    chown shell:shell /dev/usb-ffs
    mkdir /dev/usb-ffs/adb/
    chmod 0770 /dev/usb-ffs/adb
    chown shell:shell /dev/usb-ffs/adb

    mount -t functionfs -o uid=2000,gid=2000 adb /dev/usb-ffs/adb

    /apex/com.android.adbd/bin/adbd &

    sleep 1
    echo none > /config/usb_gadget/g1/UDC
    ln -s /config/usb_gadget/g1/functions/ffs.adb /config/usb_gadget/g1/configs/c.1/f1
    ls /sys/class/udc | head -n 1 > /config/usb_gadget/g1/UDC

    sleep 2
    echo 2 > /sys/devices/virtual/android_usb/android0/port_mode
fi

vndk="$(getprop persist.sys.vndk)"
[ -z "$vndk" ] && vndk="$(getprop ro.vndk.version | grep -oE '^[0-9]+')"

if [ "$vndk" = 26 ];then
	resetprop_phh ro.vndk.version 26
fi

setprop sys.usb.ffs.aio_compat true

if getprop ro.vendor.build.fingerprint | grep -q -i -e Blackview/BV9500Plus;then
    setprop persist.adb.nonblocking_ffs true
else
    setprop persist.adb.nonblocking_ffs false
fi

fixSPL() {
    local img
    local additional=""

    case "$(getprop ro.product.cpu.abi)" in
        armeabi-v7a)
            setprop ro.keymaster.mod 'AOSP on ARM32'
            ;;
        *)
            setprop ro.keymaster.mod 'AOSP on ARM64'
            ;;
    esac

    img=$(find /dev/block -type l -iname "kernel$(getprop ro.boot.slot_suffix)" | grep by-name | head -n 1)
    [ -z "$img" ] && img=$(find /dev/block -type l -iname "boot$(getprop ro.boot.slot_suffix)" | grep by-name | head -n 1)

    if [ -n "$img" ]; then
        local Arelease
        local spl

        Arelease=$(getSPL "$img" android)
        spl=$(getSPL "$img" spl)

        if [ -n "$Arelease" ] && [ -n "$spl" ]; then
            setprop ro.keymaster.xxx.release "$Arelease"
            setprop ro.keymaster.xxx.security_patch "$spl"
            if [ -z "$Arelease" ] || [ -z "$spl" ];then
               return 0
	        fi  
            setprop ro.keymaster.xxx.vbmeta_state unlocked
            setprop ro.keymaster.xxx.verifiedbootstate orange

            if [ -f /vendor/bin/hw/android.hardware.keymaster@4.1-service.trustkernel ] && [ -f /proc/tkcore/tkcore_log ]; then
                setprop debug.phh.props.teed keymaster
                setprop debug.phh.props.ice.trustkernel keymaster
            fi

            setprop ro.keymaster.brn Android

            if getprop ro.vendor.build.fingerprint | grep -qiE 'samsung.*star.*lte'; then
                additional="/apex/com.android.vndk.v28/lib64/libsoftkeymasterdevice.so /apex/com.android.vndk.v29/lib64/libsoftkeymasterdevice.so"
            else
                getprop ro.vendor.build.fingerprint | grep -qiE '^samsung/' && return 0
            fi

            local f
            for f in \
                /vendor/lib64/hw/android.hardware.keymaster@3.0-impl-qti.so /vendor/lib/hw/android.hardware.keymaster@3.0-impl-qti.so \
                /system/lib64/vndk-26/libsoftkeymasterdevice.so /vendor/bin/teed \
                /apex/com.android.vndk.v26/lib/libsoftkeymasterdevice.so  \
                /apex/com.android.vndk.v26/lib64/libsoftkeymasterdevice.so  \
                /system/lib64/vndk/libsoftkeymasterdevice.so /system/lib/vndk/libsoftkeymasterdevice.so \
                /system/lib/vndk-26/libsoftkeymasterdevice.so \
                /system/lib/vndk-27/libsoftkeymasterdevice.so /system/lib64/vndk-27/libsoftkeymasterdevice.so \
                /vendor/lib/libkeymaster3device.so /vendor/lib64/libkeymaster3device.so \
                /vendor/lib/libMcTeeKeymaster.so /vendor/lib64/libMcTeeKeymaster.so \
                /vendor/lib/hw/libMcTeeKeymaster.so /vendor/lib64/hw/libMcTeeKeymaster.so $additional; do
                [ ! -f "$f" ] && continue
                # shellcheck disable=SC2010
                local ctxt
                ctxt=$(ls -lZ "$f" | grep -oE 'u:object_r:[^:]*:s0')
                local b
                b=$(echo "$f" | tr / _)
                cp -a "$f" "/mnt/phh/$b"
                sed -i \
                    -e 's/ro.build.version.release/ro.keymaster.xxx.release/g' \
                    -e 's/ro.build.version.security_patch/ro.keymaster.xxx.security_patch/g' \
                    -e 's/ro.product.model/ro.keymaster.mod/g' \
                    -e 's/ro.product.brand/ro.keymaster.brn/g' \
                    "/mnt/phh/$b"
                chcon "$ctxt" "/mnt/phh/$b"
                mount -o bind "/mnt/phh/$b" "$f"
            done

            [ "$(getprop init.svc.keymaster-3-0)" = "running" ] && setprop ctl.restart keymaster-3-0
            [ "$(getprop init.svc.teed)" = "running" ] && setprop ctl.restart teed
        fi
    fi
}

changeKeylayout() {
    mpk="/mnt/phh/keylayout"
    cp -a /system/usr/keylayout /mnt/phh/keylayout
    changed=false
    fingerprint=$(getprop ro.vendor.build.fingerprint)

    if grep -q vendor.huawei.hardware.biometrics.fingerprint /vendor/etc/vintf/manifest.xml; then
        cp -f /system/phh/huawei/fingerprint.kl "$mpk/fingerprint.kl"
        chmod 0644 "$mpk/fingerprint.kl"
        changed=true
    fi

    if echo "$fingerprint" | grep -qE -e "^samsung"; then
        cp -f /system/phh/samsung-gpio_keys.kl "$mpk/gpio_keys.kl"
        cp -f /system/phh/samsung-sec_touchscreen.kl "$mpk/sec_touchscreen.kl"
        cp -f /system/phh/samsung-sec_touchkey.kl "$mpk/sec_touchkey.kl"
        chmod 0644 "$mpk/gpio_keys.kl" "$mpk/sec_touchscreen.kl"
        changed=true
    fi

    if echo "$fingerprint" | grep -iq -e poco/ -e POCO/ -e redmi/ -e xiaomi/ ; then
        for file in uinput-goodix.kl uinput-fpc.kl; do
            if [ ! -f "$mpk/$file" ]; then
                cp -f /system/phh/empty "$mpk/$file"
                chmod 0644 "$mpk/$file"
                changed=true
            fi
        done
    fi
        
   if echo "$fingerprint" | grep -iq -e xiaomi/daisy; then
      cp -f /system/phh/daisy-buttonJack.kl "$mpk/msm8953-snd-card-mtp_Button_Jack.kl"
      chmod 0644 "$mpk/msm8953-snd-card-mtp_Button_Jack.kl"
      changed=true
      if [ ! -f "$mpk/uinput-goodix.kl" ]; then
        cp -f /system/phh/daisy-uinput-goodix.kl "$mpk/uinput-goodix.kl"
        chmod 0644 "$mpk/uinput-goodix.kl"
        changed=true
      fi
      if [ ! -f "$mpk/uinput-fpc.kl" ]; then
        cp -f /system/phh/daisy-uinput-fpc.kl "$mpk/uinput-fpc.kl"
        chmod 0644 "$mpk/uinput-fpc.kl"
        changed=true
      fi
    fi

    
    if echo "$fingerprint" | grep -iq -e xiaomi/renoir; then
        cp -f /system/phh/daisy-buttonJack.kl "$mpk/lahaina-shimaidp-snd-card_Button_Jack.kl"
        chmod 0644 "$mpk/lahaina-shimaidp-snd-card_Button_Jack.kl"
        changed=true
    fi

    if echo "$fingerprint" | grep -qi oneplus/oneplus6/oneplus6; then
        cp -f /system/phh/oneplus6-synaptics_s3320.kl "$mpk/synaptics_s3320.kl"
        chmod 0644 "$mpk/synaptics_s3320.kl"
        changed=true
    fi

    if echo "$fingerprint" | grep -iq -e iaomi/perseus -e iaomi/cepheus; then
        cp -f /system/phh/mimix3-gpio-keys.kl "$mpk/gpio-keys.kl"
        chmod 0644 "$mpk/gpio-keys.kl"
        changed=true
    fi

    if echo "$fingerprint" | grep -q -e '^Sony/'; then
        cp -f /system/phh/sony-gpio-keys.kl "$mpk/gpio-keys.kl"
        chmod 0644 "$mpk/gpio-keys.kl"
        changed=true
    fi

    if echo "$fingerprint" | grep -q -e '^Nokia/Panther'; then
        cp -f /system/phh/nokia-soc_gpio_keys.kl "$mpk/soc_gpio_keys.kl"
        chmod 0644 "$mpk/soc_gpio_keys.kl"
        changed=true
    fi

    if echo "$fingerprint" | grep -q -e '^Lenovo/' && [ -f /sys/devices/virtual/touch/tp_dev/gesture_on ]; then
        cp -f /system/phh/lenovo-synaptics_dsx.kl "$mpk/synaptics_dsx.kl"
        cp -f /system/phh/lenovo-synaptics_dsx.kl "$mpk/fts_ts.kl"
        chmod 0644 "$mpk/synaptics_dsx.kl" "$mpk/fts_ts.kl"
        changed=true
    fi

    if (getprop ro.build.overlay.deviceid | grep -q -e RMX1931 -e RMX1941 -e CPH1859 -e CPH1861 -e RMX2185) || 
       (grep -q OnePlus /odm/etc/$(getprop ro.boot.prjname)/*.prop); then
        echo 1 > /proc/touchpanel/double_tap_enable
        cp -f /system/phh/oppo-touchpanel.kl "$mpk/touchpanel.kl"
        cp -f /system/phh/oppo-touchpanel.kl "$mpk/mtk-tpd.kl"
        chmod 0644 "$mpk/touchpanel.kl" "$mpk/mtk-tpd.kl"
        changed=true
    fi

    if echo "$fingerprint" | grep -q -e google/; then
        cp -f /system/phh/google-uinput-fpc.kl "$mpk/uinput-fpc.kl"
        chmod 0644 "$mpk/uinput-fpc.kl"
        changed=true
    fi

    if echo "$fingerprint" | grep -q -e motorola; then
        cp -f /system/phh/moto-uinput-egis.kl "$mpk/uinput-egis.kl"
        cp -f /system/phh/moto-uinput-egis.kl "$mpk/uinput-fpc.kl"
        chmod 0644 "$mpk/uinput-egis.kl" "$mpk/uinput-fpc.kl"
        changed=true
    fi

    if echo "$fingerprint" | grep -q -e nubia/NX659; then
        cp -f /system/phh/nubia-nubia_synaptics_dsx.kl "$mpk/nubia_synaptics_dsx.kl"
        chmod 0644 "$mpk/nubia_synaptics_dsx.kl"
        changed=true
    fi

    if echo "$fingerprint" | grep -q -i -e Teracube/Teracube_2e; then
        cp -f /system/phh/teracube2e-mtk-kpd.kl "$mpk/mtk-kpd.kl"
        chmod 0644 "$mpk/mtk-kpd.kl"
        changed=true
    fi

    if echo "$fingerprint" | grep -q ASUS_I01WD; then
        cp -f /system/phh/zf6-goodixfp.kl "$mpk/goodixfp.kl"
        cp -f /system/phh/zf6-googlekey_input.kl "$mpk/googlekey_input.kl"
        chmod 0644 "$mpk/goodixfp.kl" "$mpk/googlekey_input.kl"
        changed=true
    fi

    if echo "$fingerprint" | grep -q -e Unihertz/; then
        cp -f /system/phh/unihertz-mtk-kpd.kl "$mpk/mtk-kpd.kl"
        cp -f /system/phh/unihertz-mtk-tpd.kl "$mpk/mtk-tpd.kl"
        cp -f /system/phh/unihertz-mtk-tpd-kpd.kl "$mpk/mtk-tpd-kpd.kl"
        cp -f /system/phh/unihertz-fingerprint_key.kl "$mpk/fingerprint_key.kl"
        chmod 0644 "$mpk/mtk-kpd.kl" "$mpk/mtk-tpd.kl" "$mpk/mtk-tpd-kpd.kl" "$mpk/fingerprint_key.kl"
        changed=true
    fi

    if echo "$fingerprint" | grep -q -i -e Blackview/BV9500Plus; then
        cp -f /system/phh/bv9500plus-mtk-kpd.kl "$mpk/mtk-kpd.kl"
        chmod 0644 "$mpk/mtk-kpd.kl"
        changed=true
    fi

    if echo "$fingerprint" | grep -qi -e mfh505glm -e fh50lm; then
        cp -f /system/phh/empty "$mpk/uinput-fpc.kl"
        chmod 0644 "$mpk/uinput-fpc.kl"
        changed=true
    fi

    if echo "$fingerprint" | grep -q -e motorola/liber; then
        cp -f /system/phh/moto-liber-gpio-keys.kl "$mpk/gpio-keys.kl"
        chmod 0644 "$mpk/gpio-keys.kl"

        cp -f /system/phh/empty "$mpk/uinput_nav.kl"
        chmod 0644 "$mpk/uinput_nav.kl"
        changed=true
    fi

    if echo "$fingerprint" | grep -q -e DOOGEE/S88Pro; then
        cp -f /system/phh/empty "$mpk/sf-keys.kl"
        chmod 0644 "$mpk/sf-keys.kl"
        changed=true
    fi

    if echo "$fingerprint" | grep -q -e tecno/kd7; then
        echo cc1 > /proc/gesture_function
        cp -f /system/phh/tecno-touchpanel.kl "$mpk/mtk-tpd.kl"
        chmod 0644 "$mpk/mtk-tpd.kl"
        changed=true
    fi

    if [ "$changed" = true ]; then
        mount -o bind /mnt/phh/keylayout /system/usr/keylayout
        restorecon -R /system/usr/keylayout
    fi
}

if [ "$(getprop ro.product.vendor.manufacturer)" = motorola ] && getprop ro.vendor.product.name |grep -qE '^lima';then
    for l in lib lib64;do
        for f in mt6771 lima;do
            mount /system/phh/empty /vendor/$l/hw/keystore.$f.so
        done
    done
    setprop persist.sys.overlay.devinputjack true
fi

resize_system_partition() {
    if mount -o remount,rw /system; then
        resize2fs "$(grep ' /system ' /proc/mounts | cut -d ' ' -f 1)" || true
    else
        mount -o remount,rw /
        major="$(stat -c '%D' /.|sed -E 's/^([0-9a-f]+)([0-9a-f]{2})$/\1/g')"
        minor="$(stat -c '%D' /.|sed -E 's/^([0-9a-f]+)([0-9a-f]{2})$/\2/g')"
        mknod /dev/tmp-phh b $((0x$major)) $((0x$minor))
        blockdev --setrw /dev/tmp-phh
        resize2fs /dev/root || true
        resize2fs /dev/tmp-phh || true
    fi
    mount -o remount,ro /system || true
    mount -o remount,ro / || true
}

set_overlay_deviceid() {
    for part in /dev/block/bootdevice/by-name/oppodycnvbk /dev/block/platform/bootdevice/by-name/nvdata; do
        if [ -b "$part" ]; then
            oppoName="$(grep -aohE '(RMX|CPH)[0-9]{4}' "$part" | head -n 1)"
            if [ -n "$oppoName" ]; then
                setprop ro.build.overlay.deviceid "$oppoName"
            fi
        fi
    done
}

resize_system_partition

set_overlay_deviceid

mkdir -p /mnt/phh/
mount -t tmpfs -o rw,nodev,relatime,mode=755,gid=0 none /mnt/phh || true
mkdir /mnt/phh/empty_dir

fixSPL

changeKeylayout


mount /system/phh/empty /vendor/bin/vendor.samsung.security.proca@1.0-service || true

if grep vendor.huawei.hardware.biometrics.fingerprint /vendor/manifest.xml; then
    mount -o bind system/phh/huawei/fingerprint.kl /vendor/usr/keylayout/fingerprint.kl
fi

foundFingerprint=false
for manifest in /vendor/manifest.xml /vendor/etc/vintf /odm/etc/vintf; do
    if grep -qe 'android.hardware.biometrics.fingerprint' \
        -e 'vendor.oppo.hardware.biometrics.fingerprint' \
        -e 'vendor.oplus.hardware.biometrics.fingerprint' \
        -r "$manifest"; then
        foundFingerprint=true
    fi
done

if [ "$foundFingerprint" = false ]; then
    mount -o bind system/phh/empty /system/etc/permissions/android.hardware.fingerprint.xml
fi

if ! grep -q 'android.hardware.bluetooth' /vendor/manifest.xml && ! grep -q 'android.hardware.bluetooth' /vendor/etc/vintf/manifest.xml; then
    mount -o bind system/phh/empty /system/etc/permissions/android.hardware.bluetooth.xml
    mount -o bind system/phh/empty /system/etc/permissions/android.hardware.bluetooth_le.xml
fi

# Set brightness properties for specific devices
ro_vendor_build_fingerprint=$(getprop ro.vendor.build.fingerprint)
ro_hardware=$(getprop ro.hardware)

# Sony doesn't use Qualcomm HAL, so they don't have this issue
if grep -qE 'Sony/' <<< "$ro_vendor_build_fingerprint"; then
    setprop persist.sys.qcom-brightness -1
fi

# Xiaomi MiA3 uses OLED display which works best with this setting
if grep -qE 'xiaomi/laurel_sprout' <<< "$ro_vendor_build_fingerprint"; then
    setprop persist.sys.qcom-brightness -1
fi

# Lenovo Z5s & Xiaomi Mi10TLite brightness flickers without this setting
if grep -qE 'Lenovo/jd2019|Xiaomi/gauguin|Redmi/gauguin' <<< "$ro_vendor_build_fingerprint"; then
    setprop persist.sys.qcom-brightness -1
fi

# OnePlus 6 
if grep -qF 'oneplus/oneplus6/oneplus6' <<< "$ro_vendor_build_fingerprint"; then
    resize2fs /dev/block/platform/soc/1d84000.ufshc/by-name/userdata
fi

if grep -qE 'full_k50v1_64|mt6580' <<< "$ro_vendor_build_fingerprint"; then
    setprop persist.sys.overlay.nightmode false
fi

if [[ $(getprop ro.wlan.mtk.wifi.5g) -eq 1 ]]; then
    setprop persist.sys.overlay.wifi5g true
fi

# Set brightness property for specific devices
if grep -qF 'mkdir /data/.fps 0770 system fingerp' vendor/etc/init/hw/init.mmi.rc; then
    mkdir -p /data/.fps
    chmod 0770 /data/.fps
    chown system:9015 /data/.fps
    chown system:9015 /sys/devices/soc/soc:fpc_fpc1020/irq
    chown system:9015 /sys/devices/soc/soc:fpc_fpc1020/irq_cnt
fi

if getprop ro.build.overlay.deviceid | grep -q -e CPH1859 -e CPH1861 -e RMX1811 -e RMX2185;then
    setprop persist.sys.qcom-brightness "$(cat /sys/class/leds/lcd-backlight/max_brightness)"
fi

if grep -qiE 'xiaomi/clover|xiaomi/wayne|xiaomi/sakura|xiaomi/nitrogen|xiaomi/whyred|xiaomi/platina|xiaomi/ysl|nubia/nx60|nubia/nx61|xiaomi/tulip|xiaomi/lavender|xiaomi/olive|xiaomi/olivelite|xiaomi/pine|Redmi/lancelot|Redmi/galahad|POCO/evergreen' <<< "$(getprop ro.vendor.build.fingerprint)"; then
    setprop persist.sys.qcom-brightness "$(cat /sys/class/leds/lcd-backlight/max_brightness)"
fi

# Set brightness property for Qualcomm devices
if [[ "$ro_hardware" == *"qcom"* ]] && [[ -f /sys/class/backlight/panel0-backlight/max_brightness ]] &&
    ! grep -qE '^255$' /sys/class/backlight/panel0-backlight/max_brightness; then
    setprop persist.sys.qcom-brightness "$(cat /sys/class/backlight/panel0-backlight/max_brightness)"
fi

# Realme 6
brightness=$(cat /sys/class/leds/lcd-backlight/max_brightness)

if getprop ro.vendor.product.device | grep -iq -e RMX2001 -e RMX2151 -e RMX2111 -e RMX2111L1; then
    setprop persist.sys.phh.fingerprint.nocleanup true
fi

if getprop ro.vendor.product.device | grep -iq -e RMX2001 -e RMX2151 -e RMX2111 -e RMX2111L1 -e RMX1801 -e RMX1803 -e RMX1807; then
    setprop persist.sys.qcom-brightness "$brightness"
fi

if getprop ro.build.overlay.deviceid | grep -q -e CPH1859 -e CPH1861 -e RMX1811 -e RMX2185; then
    setprop persist.sys.qcom-brightness "$brightness"
fi

if getprop ro.build.overlay.deviceid | grep -iq -e RMX2020 -e RMX2027 -e RMX2040 -e RMX2193 -e RMX2193 -e RMX2191 -e RMX2195; then
    setprop persist.sys.qcom-brightness 2047
    setprop persist.sys.overlay.devinputjack true
    setprop persist.sys.phh.fingerprint.nocleanup true
fi

fingerprint=$(getprop ro.vendor.build.fingerprint)
if grep -iqE 'xiaomi/beryllium/beryllium|xiaomi/sirius/sirius|xiaomi/dipper/dipper|xiaomi/ursa/ursa|xiaomi/polaris/polaris|motorola/ali/ali|xiaomi/perseus/perseus|xiaomi/platina/platina|xiaomi/equuleus/equuleus|motorola/nora|xiaomi/nitrogen|motorola/hannah|motorola/james|motorola/pettyl|xiaomi/cepheus|xiaomi/grus|xiaomi/cereus|xiaomi/cactus|xiaomi/raphael|xiaomi/davinci|xiaomi/ginkgo|xiaomi/willow|xiaomi/laurel_sprout|xiaomi/andromeda|xiaomi/gauguin|redmi/gauguin|redmi/curtana|redmi/picasso|bq/Aquaris_M10' <<< "$fingerprint"; then
    mount -o bind /mnt/phh/empty_dir /vendor/lib64/soundfx
    mount -o bind /mnt/phh/empty_dir /vendor/lib/soundfx
    setprop ro.audio.ignore_effects true
fi

manufacturer=$(getprop ro.vendor.product.manufacturer)
device=$(getprop ro.vendor.product.device)

if [ "$manufacturer" = "motorola" ] || [ "$(getprop ro.product.vendor.manufacturer)" = "motorola" ]; then
    if grep -q -e nora -e ali -e hannah -e evert -e jeter -e deen -e james -e pettyl -e jater <<< "$device"; then
        setprop ro.audio.ignore_effects true
        if [ "$vndk" -ge 28 ]; then
            effects_lib="/vendor/lib/libeffects.so"
            ctxt=$(ls -lZ "$effects_lib" | grep -oE 'u:object_r:[^:]*:s0')
            b=$(echo "$effects_lib" | tr / _)

            cp -a "$effects_lib" "/mnt/phh/$b"
            sed -i 's/%zu errors during loading of configuration: %s/%zu errors during loading of configuration: ss/g' "/mnt/phh/$b"
            chcon "$ctxt" "/mnt/phh/$b"
            mount -o bind "/mnt/phh/$b" "$effects_lib"
        else
            mount -o bind /mnt/phh/empty_dir /vendor/lib64/soundfx
            mount -o bind /mnt/phh/empty_dir /vendor/lib/soundfx
        fi
    fi
fi

if grep -q -i -e xiaomi/wayne -e xiaomi/jasmine <<< "$fingerprint"; then
    setprop persist.imx376_sunny.low.lux 310
    setprop persist.imx376_sunny.light.lux 280
    setprop persist.imx376_ofilm.low.lux 310
    setprop persist.imx376_ofilm.light.lux 280
    echo "none" > /sys/class/leds/led:torch_2/trigger
fi

if getprop ro.vendor.build.fingerprint | grep -qEi 'iaomi/(cactus|cereus)'; then
    setprop debug.stagefright.omx_default_rank.sw-audio 1
    setprop debug.stagefright.omx_default_rank 0
fi

mtk_ril_files=(
    "/vendor/lib/mtk-ril.so"
    "/vendor/lib64/mtk-ril.so"
    "/vendor/lib/libmtk-ril.so"
    "/vendor/lib64/libmtk-ril.so"
)

for f in "${mtk_ril_files[@]}"; do
    [ ! -f "$f" ] && continue
    ctxt=$(ls -lZ "$f" | grep -oE 'u:object_r:[^:]*:s0')
    b=$(echo "$f" | tr / _)

    cp -a "$f" "/mnt/phh/$b"
    sed -i 's/AT+EAIC=2/AT+EAIC=3/g' "/mnt/phh/$b"
    chcon "$ctxt" "/mnt/phh/$b"
    mount -o bind "/mnt/phh/$b" "$f"

    setprop persist.sys.phh.radio.force_cognitive true
    setprop persist.sys.radio.ussd.fix true
done

mount -o bind /system/phh/empty /vendor/lib/libpdx_default_transport.so
mount -o bind /system/phh/empty /vendor/lib64/libpdx_default_transport.so

mount -o bind /system/phh/empty /vendor/overlay/SysuiDarkTheme/SysuiDarkTheme.apk || true
mount -o bind /system/phh/empty /vendor/overlay/SysuiDarkTheme/SysuiDarkThemeOverlay.apk || true

if grep -qF 'PowerVR Rogue GE8100' /vendor/lib/egl/GLESv1_CM_mtk.so \
    || grep -qF 'PowerVR Rogue' /vendor/lib/egl/libGLESv1_CM_mtk.so \
    || { echo "$(getprop ro.product.board) $(getprop ro.board.platform)" | grep -qiE -e msm8917 -e msm8937 -e msm8940; }; then
    setprop debug.hwui.renderer opengl
    setprop ro.skia.ignore_swizzle true
    if [ "$vndk" = 26 ] || [ "$vndk" = 27 ]; then
        setprop debug.hwui.use_buffer_age false
    fi
fi

if [ -f /vendor/bin/hw/vendor.samsung.hardware.miscpower@1.0-service ] && [ "$vndk" -lt 28 ]; then
    mount -o bind /system/phh/empty /vendor/bin/hw/android.hardware.power@1.0-service
fi

if [ "$vndk" = 27 ] || [ "$vndk" = 26 ]; then
    mount -o bind /system/phh/libnfc-nci-oreo.conf /system/etc/libnfc-nci.conf
fi

if busybox_phh unzip -p /vendor/app/ims/ims.apk classes.dex | grep -qF -e Landroid/telephony/ims/feature/MmTelFeature -e Landroid/telephony/ims/feature/MMTelFeature; then
    mount -o bind /system/phh/empty /vendor/app/ims/ims.apk
fi

if getprop ro.hardware | grep -qF exynos \
    || getprop ro.product.model | grep -qF ANE \
    || getprop ro.vendor.product.device | grep -q -e nora -e rhannah; then
    setprop debug.sf.latch_unsignaled 1
fi

if getprop ro.vendor.build.fingerprint | grep -iq -e xiaomi/daisy; then
    setprop debug.sf.latch_unsignaled 1
    setprop debug.sf.enable_hwc_vds 1
fi

if getprop ro.vendor.build.fingerprint | grep -iq -e Redmi/merlin; then
    setprop debug.sf.latch_unsignaled 1
    setprop debug.sf.enable_hwc_vds 0
fi

if getprop ro.vendor.build.fingerprint | grep -iq -e Redmi/rosemary \
    -e Redmi/secret -e Redmi/maltose; then
    setprop debug.sf.latch_unsignaled 1
    setprop debug.sf.enable_hwc_vds 0

    # Exclude FP input devices
    mount -o bind /system/phh/rosemary-excluded-input-devices.xml /system/etc/excluded-input-devices.xml
fi

if getprop ro.vendor.build.fingerprint | grep -iq -E -e 'huawei|honor' || getprop persist.sys.overlay.huawei | grep -iq -E -e 'true'; then
    p=/product/etc/nfc/libnfc_nxp_*_*.conf
    mount -o bind "$p" /system/etc/libnfc-nxp.conf ||
        mount -o bind /product/etc/libnfc-nxp.conf /system/etc/libnfc-nxp.conf || true

    p=/product/etc/nfc/libnfc_brcm_*_*.conf
    mount -o bind "$p" /system/etc/libnfc-brcm.conf ||
        mount -o bind /product/etc/libnfc-nxp.conf /system/etc/libnfc-nxp.conf || true

    mount -o bind /system/phh/libnfc-nci-huawei.conf /system/etc/libnfc-nci.conf
fi

if getprop ro.vendor.build.fingerprint | grep -qE -e ".*(crown|star)[q2]*lte.*" -e ".*(SC-0[23]K|SCV3[89]).*" && [ "$vndk" -lt 28 ]; then
    for f in /vendor/lib/libfloatingfeature.so /vendor/lib64/libfloatingfeature.so; do
        [ ! -f "$f" ] && continue
        # shellcheck disable=SC2010
        ctxt="$(ls -lZ "$f" | grep -oE 'u:object_r:[^:]*:s0')"
        b="$(echo "$f" | tr / _)"

        cp -a "$f" "/mnt/phh/$b"
        sed -i \
            -e 's;/system/etc/floating_feature.xml;/system/ph/sam-9810-flo_feat.xml;g' \
            "/mnt/phh/$b"
        chcon "$ctxt" "/mnt/phh/$b"
        mount -o bind "/mnt/phh/$b" "$f"

        setprop ro.audio.monitorRotation true
    done
fi