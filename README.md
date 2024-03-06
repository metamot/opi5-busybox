How to create very small minimal Linux system based on Static Busybox for RK3588 **(Orange Pi 5 / 5+ )** : 

**Orange Pi 5 / Orange Pi 5plus --- very small Busybox-Linux-system**

HOST   : Opi5/Opi5+ with Debian/Ubuntu

TARGET : Opi5+(now), Opi5 will be tested in nearest future

    mkdir -p ~/mywork/rk3588-busybox
    git clone https://github.com/metamot/opi5-busybox ~/mywork/rk3588-busybox
    cd ~/mywork/rk3588-busybox
    chmod ugo+x build.sh
    ./build.sh

Check your microSD device:

    lsblk

**:: OPI5+** (emmc is istalled vs microSD-card :: both are mmc-subsytem)

lsblk**X**boot**X** - is emmc(!)

For example "mmcblk1, mmcblk1p1, mmcblk1p2, mmcblk1boot0, mmcblk1boot1". 

If you insert microSD-card then you can see something other like "mmcblk0".

You need to know which device is e

OPI5+ manual:

Prepare microSD (min35GB) and insert to microSD-slot.

**TBD**
