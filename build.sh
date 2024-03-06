#!/bin/bash
set -x
sudo apt install -y zstd pv dosfstools swig python-dev-is-python3 python3 python3-pyelftools
mkdir -p clones
mkdir -p src
# === Part0: download
if ! test -f src/linux.cpio.zst; then
  git clone https://github.com/orangepi-xunlong/linux-orangepi.git -b orange-pi-5.10-rk3588 clones/linux
  cd clones/linux && git status && find . -print0 | cpio -o0H newc | zstd -z4T9 > ../../src/linux.cpio.zst && cd -
fi
if ! test -f src/busybox.cpio.zst; then
  git clone https://git.busybox.net/busybox -b 1_36_stable clones/busybox  
  cd clones/busybox && git status && find . -print0 | cpio -o0H newc | zstd -z9T9 > ../../src/busybox.cpio.zst && cd -
fi
if ! test -f src/uboot.cpio.zst; then
  git clone https://github.com/u-boot/u-boot clones/uboot
  cd clones/uboot && git checkout v2024.01 && cd - 
  cd clones/uboot && git status && find . -print0 | cpio -o0H newc | zstd -z9T9 > ../../src/uboot.cpio.zst && cd -
fi
if ! test -f src/atf.cpio.zst; then
  git clone https://review.trustedfirmware.org/TF-A/trusted-firmware-a clones/rk35-atf
  cd clones/rk35-atf && git fetch https://review.trustedfirmware.org/TF-A/trusted-firmware-a refs/changes/40/21840/5 && git checkout -b change-21840 FETCH_HEAD && cd -
  cd clones/rk35-atf && git status && find . -print0 | cpio -o0H newc | zstd -z9T9 > ../../src/atf.cpio.zst && cd -
fi
if ! test -f src/rkbin.cpio.zst; then
  git clone https://github.com/armbian/rkbin clones/rkbin
  cd clones/rkbin && git checkout be3d2004d019b42cbecb001f5d7dd1e361d41e05 && cd -
  cd clones/rkbin && git status && find . -print0 | cpio -o0H newc | zstd -z9T9 > ../../src/rkbin.cpio.zst && cd -
fi
# === Part1: rk3588-bins
mkdir -p src/rkbin
pv src/rkbin.cpio.zst | zstd -d | cpio -iduH newc -D src/rkbin
mkdir -p src/rk3588-bins
cp -f src/rkbin/rk35/rk3588_ddr_lp4_2112MHz_lp5_2736MHz_v1.08.bin src/rk3588-bins/
cp -f src/rkbin/rk35/rk3588_bl31_v1.28.elf src/rk3588-bins/
cp -f src/rkbin/rk35/rk3588_spl_loader_v1.08.111.bin src/rk3588-bins/
rm -fr src/rkbin
# == Part2: build bl31
mkdir -p src/rk35-atf
pv src/atf.cpio.zst | zstd -d | cpio -iduH newc -D src/rk35-atf
sed -i 's/ASFLAGS		+=	\$(march-directive)/ASFLAGS += -mcpu=cortex-a76.cortex-a55+crypto -Os/' src/rk35-atf/Makefile
sed -i 's/TF_CFLAGS   +=	\$(march-directive)/TF_CFLAGS += -mcpu=cortex-a76.cortex-a55+crypto -Os/' src/rk35-atf/Makefile
cd src/rk35-atf && make V=1 -j9 PLAT=rk3588 bl31 && cd -
cp -f src/rk35-atf/build/rk3588/release/bl31/bl31.elf src/rk3588-bins/
# == Part3: build uboot (there are different copies for opi5 and opi5plus)
mkdir -p src/uboot-opi5
pv src/uboot.cpio.zst | zstd -d | cpio -iduH newc -D src/uboot-opi5
sed -i 's/-O2/-mcpu=cortex-a76.cortex-a55+crypto -Os/' src/uboot-opi5/Makefile
sed -i 's/-march=armv8-a+crc/-mcpu=cortex-a76.cortex-a55+crypto/' src/uboot-opi5/arch/arm/Makefile
cp -far src/uboot-opi5 src/uboot-opi5plus
cd src/uboot-opi5     && make V=1 orangepi-5-rk3588s_defconfig     && cd -
sed -i 's|CONFIG_BOOTDELAY=2|CONFIG_BOOTDELAY=0|' src/uboot-opi5/.config
cd src/uboot-opi5     && make V=1 -j9 ROCKCHIP_TPL=../rk3588-bins/rk3588_ddr_lp4_2112MHz_lp5_2736MHz_v1.08.bin BL31=../rk3588-bins/bl31.elf && cd -
cd src/uboot-opi5plus && make V=1 orangepi-5-plus-rk3588_defconfig && cd -
sed -i 's|CONFIG_BOOTDELAY=2|CONFIG_BOOTDELAY=0|' src/uboot-opi5plus/.config
cd src/uboot-opi5plus && make V=1 -j9 ROCKCHIP_TPL=../rk3588-bins/rk3588_ddr_lp4_2112MHz_lp5_2736MHz_v1.08.bin BL31=../rk3588-bins/bl31.elf && cd -
# == Part3: build linux-kernel (build time: ~30m)
mkdir -p src/linux
pv src/linux.cpio.zst | zstd -d | cpio -iduH newc -D src/linux
mkdir -p out/fat
mkdir -p out/rd
cd src/linux && make rockchip_linux_defconfig && cd -
cd src/linux && make ARCH=arm64 V=1 -j9 KCFLAGS="-mcpu=cortex-a76.cortex-a55+crypto -Os" dtbs && cd -
cd src/linux && make ARCH=arm64 V=1 -j9 INSTALL_DTBS_PATH=../../out/fat/dtb dtbs_install && cd -
cd src/linux && make ARCH=arm64 V=1 -j9 KCFLAGS="-mcpu=cortex-a76.cortex-a55+crypto -Os" Image && cd -
cp -f src/linux/arch/arm64/boot/Image out/fat/
cd src/linux && make ARCH=arm64 V=1 -j9 KCFLAGS="-mcpu=cortex-a76.cortex-a55+crypto -Os" modules && cd -
cd src/linux && make ARCH=arm64 V=1 -j9 INSTALL_MOD_PATH=../../out/rd/kermod modules_install && cd -
# == Part4: build busybox
mkdir -p src/busybox
pv src/busybox.cpio.zst | zstd -d | cpio -iduH newc -D src/busybox
find src/busybox -name "*.h" -exec sed -i "s/\/bin\//\/abin\//g" {} +
find src/busybox -name "*.c" -exec sed -i "s/\/bin\//\/abin\//g" {} +
find src/busybox -name "*.h" -exec sed -i "s/\/etc\//\/aetc\//g" {} +
find src/busybox -name "*.c" -exec sed -i "s/\/etc\//\/aetc\//g" {} +
cd src/busybox && make defconfig && cd -
sed -i 's|# CONFIG_STATIC is not set|CONFIG_STATIC=y|' src/busybox/.config
sed -i 's|# CONFIG_INSTALL_NO_USR is not set|CONFIG_INSTALL_NO_USR=y|' src/busybox/.config
#sed -i 's|CONFIG_DESKTOP=y|# CONFIG_DESKTOP is not set|' src/busybox/.config
cd src/busybox && make CFLAGS="-mcpu=cortex-a76.cortex-a55+crypto -Os" V=1 -j9 && cd -
# == Part5: create uboot script
echo 'setenv load_addr "0x9000000"' > src/boot.cmd
echo 'setenv overlay_error "false"' >> src/boot.cmd
echo 'setenv rootdev "/dev/mmcblk0p1"' >> src/boot.cmd
echo 'setenv verbosity "1"' >> src/boot.cmd
echo 'setenv console "both"' >> src/boot.cmd
echo 'setenv bootlogo "false"' >> src/boot.cmd
echo 'setenv rootfstype "ext4"' >> src/boot.cmd
echo 'setenv docker_optimizations "on"' >> src/boot.cmd
echo 'setenv earlycon "off"' >> src/boot.cmd
echo 'echo "Boot script loaded from ${devtype} ${devnum}"' >> src/boot.cmd
echo 'if test -e ${devtype} ${devnum} ${prefix}orangepiEnv.txt; then' >> src/boot.cmd
echo '	load ${devtype} ${devnum} ${load_addr} ${prefix}orangepiEnv.txt' >> src/boot.cmd
echo '	env import -t ${load_addr} ${filesize}' >> src/boot.cmd
echo 'fi' >> src/boot.cmd
echo 'if test "${logo}" = "disabled"; then setenv logo "logo.nologo"; fi' >> src/boot.cmd
echo 'if test "${console}" = "display" || test "${console}" = "both"; then setenv consoleargs "console=tty1"; fi' >> src/boot.cmd
echo 'if test "${console}" = "serial" || test "${console}" = "both"; then setenv consoleargs "console=ttyFIQ0,1500000 ${consoleargs} myboot=${devnum}"; fi' >> src/boot.cmd
echo 'if test "${earlycon}" = "on"; then setenv consoleargs "earlycon ${consoleargs}"; fi' >> src/boot.cmd
echo 'if test "${bootlogo}" = "true"; then' >> src/boot.cmd
echo '        setenv consoleargs "splash plymouth.ignore-serial-consoles ${consoleargs}"' >> src/boot.cmd
echo 'else' >> src/boot.cmd
echo '        setenv consoleargs "splash=verbose ${consoleargs}"' >> src/boot.cmd
echo 'fi' >> src/boot.cmd
echo 'if test "${devtype}" = "mmc"; then part uuid mmc ${devnum}:1 partuuid; fi' >> src/boot.cmd
echo 'setenv bootargs "root=${rootdev} rootfstype=${rootfstype} ${consoleargs} consoleblank=0 loglevel=${verbosity} ubootpart=${partuuid} ${extraargs} ${extraboardargs}"' >> src/boot.cmd
echo 'if test "${docker_optimizations}" = "on"; then setenv bootargs "${bootargs} cgroup_enable=cpuset cgroup_memory=1 cgroup_enable=memory swapaccount=1"; fi' >> src/boot.cmd
echo 'load ${devtype} ${devnum} ${ramdisk_addr_r} ${prefix}uInitrd' >> src/boot.cmd
echo 'load ${devtype} ${devnum} ${kernel_addr_r} ${prefix}Image' >> src/boot.cmd
echo 'load ${devtype} ${devnum} ${fdt_addr_r} ${prefix}dtb/${fdtfile}' >> src/boot.cmd
echo 'fdt addr ${fdt_addr_r}' >> src/boot.cmd
echo 'fdt resize 65536' >> src/boot.cmd
echo 'for overlay_file in ${overlays}; do' >> src/boot.cmd
echo '	if load ${devtype} ${devnum} ${load_addr} ${prefix}dtb/rockchip/overlay/${overlay_prefix}-${overlay_file}.dtbo; then' >> src/boot.cmd
echo '		echo "Applying kernel provided DT overlay ${overlay_prefix}-${overlay_file}.dtbo"' >> src/boot.cmd
echo '		fdt apply ${load_addr} || setenv overlay_error "true"' >> src/boot.cmd
echo '	fi' >> src/boot.cmd
echo 'done' >> src/boot.cmd
echo 'for overlay_file in ${user_overlays}; do' >> src/boot.cmd
echo '	if load ${devtype} ${devnum} ${load_addr} ${prefix}overlay-user/${overlay_file}.dtbo; then' >> src/boot.cmd
echo '		echo "Applying user provided DT overlay ${overlay_file}.dtbo"' >> src/boot.cmd
echo '		fdt apply ${load_addr} || setenv overlay_error "true"' >> src/boot.cmd
echo '	fi' >> src/boot.cmd
echo 'done' >> src/boot.cmd
echo 'if test "${overlay_error}" = "true"; then' >> src/boot.cmd
echo '	echo "Error applying DT overlays, restoring original DT"' >> src/boot.cmd
echo '	load ${devtype} ${devnum} ${fdt_addr_r} ${prefix}dtb/${fdtfile}' >> src/boot.cmd
echo 'else' >> src/boot.cmd
echo '	if load ${devtype} ${devnum} ${load_addr} ${prefix}dtb/rockchip/overlay/${overlay_prefix}-fixup.scr; then' >> src/boot.cmd
echo '		echo "Applying kernel provided DT fixup script (${overlay_prefix}-fixup.scr)"' >> src/boot.cmd
echo '		source ${load_addr}' >> src/boot.cmd
echo '	fi' >> src/boot.cmd
echo '	if test -e ${devtype} ${devnum} ${prefix}fixup.scr; then' >> src/boot.cmd
echo '		load ${devtype} ${devnum} ${load_addr} ${prefix}fixup.scr' >> src/boot.cmd
echo '		echo "Applying user provided fixup script (fixup.scr)"' >> src/boot.cmd
echo '		source ${load_addr}' >> src/boot.cmd
echo '	fi' >> src/boot.cmd
echo 'fi' >> src/boot.cmd
echo 'booti ${kernel_addr_r} ${ramdisk_addr_r} ${fdt_addr_r}' >> src/boot.cmd
# == Part6: create RFS(Root-File-System)
mkdir -p out/rd/aetc/init.d
# rcS
echo '#!/abin/sh' > out/rd/aetc/init.d/rcS
echo 'for x in $(/abin/busybox cat /proc/cmdline); do' >> out/rd/aetc/init.d/rcS
echo '  case $x in' >> out/rd/aetc/init.d/rcS
echo '  myboot=*)' >> out/rd/aetc/init.d/rcS
echo '    BOOT_DEV=${x#myboot=}' >> out/rd/aetc/init.d/rcS
echo '    BOOT_DEV_NAME=/dev/mmcblk${BOOT_DEV}' >> out/rd/aetc/init.d/rcS
echo '    /abin/busybox echo "BOOT_DEV_NAME = ${BOOT_DEV_NAME}"' >> out/rd/aetc/init.d/rcS
echo '    ;;' >> out/rd/aetc/init.d/rcS
echo '  esac' >> out/rd/aetc/init.d/rcS
echo 'done' >> out/rd/aetc/init.d/rcS
echo 'if [ ${BOOT_DEV} = "0" ]' >> out/rd/aetc/init.d/rcS
echo 'then' >> out/rd/aetc/init.d/rcS
echo '   BOOT_DEV_TYPE=microSD' >> out/rd/aetc/init.d/rcS
echo 'else' >> out/rd/aetc/init.d/rcS
echo '   BOOT_DEV_TYPE=eMMC' >> out/rd/aetc/init.d/rcS
#echo '   /abin/busybox mkdir /boot' >> out/rd/aetc/init.d/rcS
#echo '   /abin/busybox mount /dev/mmcblk${BOOT_DEV}p1 /boot' >> out/rd/aetc/init.d/rcS
#echo '   /abin/busybox mkdir /usr' >> out/rd/aetc/init.d/rcS
#echo '   /abin/busybox mount /dev/mmcblk${BOOT_DEV}p2 /usr' >> out/rd/aetc/init.d/rcS
#echo '   /abin/busybox ln -sf /usr/bin /bin' >> out/rd/aetc/init.d/rcS
#echo '   /abin/busybox ln -sf /usr/sbin /sbin' >> out/rd/aetc/init.d/rcS
#echo '   /abin/busybox ln -sf /usr/lib /lib' >> out/rd/aetc/init.d/rcS
echo 'fi' >> out/rd/aetc/init.d/rcS
echo '/abin/busybox echo "BOOT_DEV_TYPE = ${BOOT_DEV_TYPE}"' >> out/rd/aetc/init.d/rcS
chmod ugo+x out/rd/aetc/init.d/rcS
# inittab
echo "::sysinit:/abin/busybox mkdir /sys" > out/rd/aetc/inittab
echo "::sysinit:/abin/busybox mount -t sysfs -o nodev,noexec,nosuid sysfs /sys" >> out/rd/aetc/inittab
echo "::sysinit:/abin/busybox mkdir /proc" >> out/rd/aetc/inittab
echo "::sysinit:/abin/busybox mount -t proc -o nodev,noexec,nosuid proc /proc" >> out/rd/aetc/inittab
echo "::sysinit:/abin/busybox mount -t devtmpfs -o nosuid,mode=0755 udev /dev" >> out/rd/aetc/inittab
echo "::sysinit:/abin/busybox mkdir /dev/pts" >> out/rd/aetc/inittab
echo "::sysinit:/abin/busybox mount -t devpts -o noexec,nosuid,gid=5,mode=0620 devpts /dev/pts" >> out/rd/aetc/inittab
echo "::sysinit:/aetc/init.d/rcS" >> out/rd/aetc/inittab
echo "::respawn:-/abin/sh" >> out/rd/aetc/inittab
echo "ttyFIQ0::respawn:/abin/getty -L -f 0 1500000 ttyFIQ0 vt100" >> out/rd/aetc/inittab
echo "::ctrlaltdel:/abin/busybox poweroff" >> out/rd/aetc/inittab
# profile
echo 'export PATH="/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin:/usr/local/sbin"' > out/rd/aetc/profile
echo '/abin/busybox cat /aetc/issue' >> out/rd/aetc/profile
# shells
echo "/abin/ash" > out/rd/aetc/shells
echo "/abin/sh" >> out/rd/aetc/shells
# group
echo "root:x:0:" > out/rd/aetc/group
echo "daemon:x:1:" >> out/rd/aetc/group
echo "bin:x:2:" >> out/rd/aetc/group
echo "sys:x:3:" >> out/rd/aetc/group
echo "adm:x:4:" >> out/rd/aetc/group
echo "tty:x:5:" >> out/rd/aetc/group
echo "disk:x:6:" >> out/rd/aetc/group
echo "lp:x:7:" >> out/rd/aetc/group
echo "mail:x:8:" >> out/rd/aetc/group
echo "kmem:x:9:" >> out/rd/aetc/group
echo "wheel:x:10:root" >> out/rd/aetc/group
echo "cdrom:x:11:" >> out/rd/aetc/group
echo "dialout:x:18:" >> out/rd/aetc/group
echo "floppy:x:19:" >> out/rd/aetc/group
echo "video:x:28:" >> out/rd/aetc/group
echo "audio:x:29:" >> out/rd/aetc/group
echo "tape:x:32:" >> out/rd/aetc/group
echo "www-data:x:33:" >> out/rd/aetc/group
echo "operator:x:37:" >> out/rd/aetc/group
echo "utmp:x:43:" >> out/rd/aetc/group
echo "plugdev:x:46:" >> out/rd/aetc/group
echo "staff:x:50:" >> out/rd/aetc/group
echo "lock:x:54:" >> out/rd/aetc/group
echo "netdev:x:82:" >> out/rd/aetc/group
echo "users:x:100:" >> out/rd/aetc/group
echo "nobody:x:65534:" >> out/rd/aetc/group
# passwd
echo "root::0:0:root:/root:/abin/sh" > out/rd/aetc/passwd
echo "daemon:x:1:1:daemon:/usr/sbin:/abin/false" >> out/rd/aetc/passwd
echo "bin:x:2:2:bin:/abin:/abin/false" >> out/rd/aetc/passwd
echo "sys:x:3:3:sys:/dev:/abin/false" >> out/rd/aetc/passwd
echo "sync:x:4:100:sync:/abin:/abin/sync" >> out/rd/aetc/passwd
echo "mail:x:8:8:mail:/var/spool/mail:/abin/false" >> out/rd/aetc/passwd
echo "www-data:x:33:33:www-data:/var/www:/abin/false" >> out/rd/aetc/passwd
echo "operator:x:37:37:Operator:/var:/abin/false" >> out/rd/aetc/passwd
echo "nobody:x:65534:65534:nobody:/home:/abin/false" >> out/rd/aetc/passwd
# shadow
echo "root::19701::::::" > out/rd/aetc/shadow
echo "daemon:*:::::::" >> out/rd/aetc/shadow
echo "bin:*:::::::" >> out/rd/aetc/shadow
echo "sys:*:::::::" >> out/rd/aetc/shadow
echo "sync:*:::::::" >> out/rd/aetc/shadow
echo "mail:*:::::::" >> out/rd/aetc/shadow
echo "www-data:*:::::::" >> out/rd/aetc/shadow
echo "operator:*:::::::" >> out/rd/aetc/shadow
echo "nobody:*:::::::" >> out/rd/aetc/shadow
# bin
mkdir -p out/rd/abin
cp -f src/busybox/busybox out/rd/abin/
cd out/rd && ln -sf /abin/busybox init && cd -
cd out/rd/abin && ln -sf busybox login && ln -sf busybox getty && ln -sf busybox sh && ln -sf busybox ash && ln -sf busybox sync && ln -sf busybox true && ln -sf busybox false && cd -
# == Part7: create final image (opi5 and opi5+ are different because uboot)
echo 'verbosity=1' > out/fat/orangepiEnv.txt
echo 'bootlogo=false' >> out/fat/orangepiEnv.txt
echo 'extraargs=cma=128M' >> out/fat/orangepiEnv.txt
echo 'overlay_prefix=rk3588' >> out/fat/orangepiEnv.txt
echo 'rootdev=UUID=0b9501f8-db3c-4b33-940a-7fce0931dc2c' >> out/fat/orangepiEnv.txt
# opi5
cp -far out out-opi5
echo 'fdtfile=rockchip/rk3588s-orangepi-5.dtb.dtb' >> out-opi5/fat/orangepiEnv.txt
echo "Opi5" > out-opi5/rd/aetc/issue
src/uboot-opi5/tools/mkimage -C none -A arm -T script -d src/boot.cmd out-opi5/fat/boot.scr
cd out-opi5/rd && find . -print | cpio -oH newc | gzip > ../Initrd && cd -
src/uboot-opi5/tools/mkimage -A arm64 -O linux -T ramdisk -C gzip -n uInitrd -d out-opi5/Initrd out-opi5/fat/uInitrd
rm -f out-opi5/Initrd
# opi5+
cp -far out out-opi5plus
echo 'fdtfile=rockchip/rk3588-orangepi-5-plus.dtb' >> out-opi5plus/fat/orangepiEnv.txt
echo "Opi5+" > out-opi5plus/rd/aetc/issue
src/uboot-opi5plus/tools/mkimage -C none -A arm -T script -d src/boot.cmd out-opi5plus/fat/boot.scr
cd out-opi5plus/rd && find . -print | cpio -oH newc | gzip > ../Initrd && cd -
src/uboot-opi5plus/tools/mkimage -A arm64 -O linux -T ramdisk -C gzip -n uInitrd -d out-opi5plus/Initrd out-opi5plus/fat/uInitrd
rm -f out-opi5plus/Initrd
mkdir -p out-opi5plus/mnt
dd of=out-opi5plus/mmc-fat.bin if=/dev/zero bs=1M count=0 seek=190
/sbin/mkfs.fat -F 32 -n "opi_boot" -i A77ACF93 out-opi5plus/mmc-fat.bin
sudo mount out-opi5plus/mmc-fat.bin out-opi5plus/mnt
sudo cp --force --no-preserve=all --recursive out-opi5plus/fat/* out-opi5plus/mnt
sudo umount out-opi5plus/mnt
rm -fr out-opi5plus/mnt
dd of=out-opi5plus/mmc.img if=/dev/zero bs=1M count=0 seek=201
dd of=out-opi5plus/mmc.img if=src/uboot-opi5plus/u-boot-rockchip.bin seek=64 conv=notrunc
dd of=out-opi5plus/mmc.img if=out-opi5plus/mmc-fat.bin seek=20480 conv=notrunc
/sbin/parted -s out-opi5plus/mmc.img mklabel gpt
/sbin/parted -s out-opi5plus/mmc.img unit s mkpart bootfs 20480 409599
set +x

# The system has no "/bin, /sbin, /lib and others"
# Here are only "/dev, /proc, /sys ..  and /root - empty"
# "/abin & /aetc" - are unusual, but both are static busybox linked.
# So, you can create/mount your custom "/usr", so "/bin,/sbin,/lib" etc can be mounted or linked to usr-friedly "/usr/bin, /usr/sbin, /usr/lib"
# All others like "/run, /tmp, /var" can be linked, for example to new /usr system like unusual "/usr/log, /usr/tmp, /usr/run & etc".

#https://distfiles.gentoo.org/releases/arm64/autobuilds/20240304T223401Z/stage3-arm64-systemd-mergedusr-20240304T223401Z.tar.xz
# ^^ Try it
