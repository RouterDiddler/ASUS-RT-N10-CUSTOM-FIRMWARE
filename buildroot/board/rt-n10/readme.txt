ASUS RT-N10 B1 (Ralink RT3350, 32 MB RAM, 4 MB MX29LV320 NOR)
===============================================================

Build (always with LC_ALL=C: a tr_TR locale breaks generated sources):

  LC_ALL=C make asus_rt_n10_b1_defconfig
  LC_ALL=C make

Images (output/images/), produced by board/rt-n10/post-image.sh:

  uImage-uboot   RAM test image, kernel + initramfs. Never touches flash
                 (all partitions are read-only: settings are read from
                 flash but changes stay in RAM).
                   U-Boot menu: 4 (command line), then
                   setenv ipaddr 192.168.10.1; setenv serverip 192.168.10.30
                   tftpboot 80b00000 uImage-uboot; bootm 80b00000
                 (post-image.sh prints the safe load address for each build)
  uImage-flash   kernel for flash, root=/dev/mtdblock4 (squashfs)
  firmware.bin   kernel + rootfs, 0x3a0000 bytes, for flash 0x050000-0x3effff

Flash layout (DTS: arch/mips/boot/dts/ralink/rt3350_asus_rt-n10-b1.dts):

  0x000000 u-boot   0x30000   never written
  0x030000 cfg-a    0x10000   settings copy A (was the stock ASUS nvram)
  0x040000 factory  0x10000   wifi EEPROM + MAC, never written
  0x050000 kernel   0x220000  uImage, booted by U-Boot at 0xbfc50000
  0x270000 rootfs   0x180000  squashfs (xz), read-only
  0x3f0000 cfg-b    0x10000   settings copy B (last block)

Settings: /data is a tmpfs. S45data unpacks the newest valid copy (cfg-a or
cfg-b, header "RTN10CFG <seq> <len> <md5>" + tar of /data/rtn10) into it;
rtn10-save writes the settings over the OLDER copy (flashcp: erase, write,
verify), so a power cut while saving keeps the previous settings.
rtn10-cfg status shows both copies, rtn10-cfg erase wipes them.

Writing firmware.bin from the U-Boot command line (U-Boot maps the flash at
0xbf000000; the range below is sectors 12-69 only, cfg-a and cfg-b are not
touched):

  tftpboot 80a00000 firmware.bin        -> must say 3801088 (3a0000 hex)
  erase bf050000 bf3effff               -> "Erased 58 sectors"
  cp.b 80a00000 bf050000 3a0000
  then verify, e.g. by booting uImage-uboot from RAM and comparing
  md5sum /dev/mtdblock3 /dev/mtdblock4 with the matching slices of
  firmware.bin.
  Coming from the older JFFS2 layout: cfg-a holds the stock ASUS nvram and
  cfg-b old JFFS2 data; neither is a valid settings copy, so the first boot
  runs the wizard (old settings are not migrated).

Back to the stock firmware: erase bf050000 bf3fffff + cp.b 80a00000
bf050000 3b0000 with the 0x50000-0x3fffff part of a full flash dump. The
stock firmware rebuilds its nvram at 0x30000 from defaults.

Runtime:
  - serial console 57600 8N1, root shell without login
  - first boot: rtn10-setup asks for the Wi-Fi name and WPA2 password and
    saves them (rtn10-save); run it again to change them
  - S50router: NAT + firewall (INVALID dropped, nothing accepted from the
    WAN), WAN DHCP client (eth0.2, switch port 0), dnsmasq on br0 =
    eth0.1 + wlan0, 192.168.10.1/24 (DHCP + DNS cache, router.lan; busybox
    udhcpd as fallback), hostapd (WPA2, HT40 when the band allows it,
    country TR), ntpd, fq_codel as default qdisc
  - SSH on 192.168.10.1:22, keys only (rtn10-sshkey)
  - buttons: reset held 5 s = factory reset, WPS = Wi-Fi on/off
  - rtn10-status, rtn10-guest, rtn10-backup / rtn10-restore (over ssh)
  - IPv6: WAN address + prefix delegation (udhcpc6), RA/SLAAC on the LAN
    (dnsmasq), ip6tables firewall
  - web page http://192.168.10.1/ (user admin), off until rtn10-webpass
  - firmware upgrade over ssh, keeps the settings, same partition layout only:
      ssh root@192.168.10.1 "rtn10-upgrade $(md5sum firmware.bin | cut -c1-32)" < firmware.bin

Optional settings in /data/rtn10 (one entry per line, '#' comments):
  static-leases   aa:bb:cc:dd:ee:ff 192.168.10.50 [name]
  port-forwards   tcp|udp <wan port> <lan ip> [<lan port>]
then: rtn10-save; /etc/init.d/S50router restart
Guest Wi-Fi (rtn10-guest on): separate BSS on br-guest, 192.168.20.0/24,
clients isolated, internet only. If hostapd refuses the guest BSS or HT40,
S50router retries without them so the main network always comes up.

Kernel patches (board/rt-n10/patches/linux):
  0001  RT3350 sysc compatible (clock lookup)
  0002  RT3050/RT3350 frame engine + switch driver, board DTS
  0003  no erase suspend on MX29LV320 (write timeouts otherwise)
  0004  watchdog
  0005-0007  partition sizes, read-only markers for the flash build
  0008  two settings blocks (cfg-a/cfg-b) instead of the JFFS2 data partition
