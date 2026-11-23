#!/bin/sh
# RT-N10 B1: drop files nothing on the target uses (checked with readelf NEEDED).
set -e
T="$1"
# hostapd and iw only link libnl-3 and libnl-genl-3
rm -f "$T"/usr/lib/libnl-route-3.so* "$T"/usr/lib/libnl-nf-3.so* \
      "$T"/usr/lib/libnl-xfrm-3.so* "$T"/usr/lib/libnl-idiag-3.so* \
      "$T"/usr/lib/libnl-cli-3.so*
# development symlinks
rm -f "$T"/usr/lib/libnl-3.so "$T"/usr/lib/libnl-genl-3.so
# no binary needs libgcc_s / libatomic
rm -f "$T"/lib/libgcc_s.so* "$T"/lib/libatomic.so*
# sample config and control client
rm -f "$T"/etc/hostapd.conf "$T"/usr/bin/hostapd_cli
# the kernel accepts an unsigned regulatory.db (CFG80211_REQUIRE_SIGNED_REGDB=n)
rm -f "$T"/lib/firmware/regulatory.db.p7s
# read-only squashfs root: keep the seedrng seed on tmpfs
rm -rf "$T"/var/lib/seedrng
ln -sfn ../../tmp "$T"/var/lib/seedrng

# serial console: no login, setup wizard on first boot then a root shell
sed -i '/GENERIC_SERIAL/d; /rtn10-console/d' "$T"/etc/inittab
echo 'ttyS0::respawn:/usr/sbin/rtn10-console # RT-N10 console' >> "$T"/etc/inittab

# iptables: keep only the extensions the firewall in S50router uses
if [ -d "$T"/usr/lib/xtables ]; then
	for f in "$T"/usr/lib/xtables/*.so; do
		case "${f##*/}" in
			libxt_standard.so|libxt_conntrack.so|libxt_MASQUERADE.so|libipt_MASQUERADE.so|\
			libxt_tcp.so|libxt_udp.so|libipt_icmp.so|libip6t_icmp6.so|libxt_NAT.so) ;;
			*) rm -f "$f" ;;
		esac
	done
fi
# (libip6tc stays: xtables-legacy-multi links it even for IPv4)
rm -f \
      "$T"/usr/sbin/iptables-apply "$T"/usr/sbin/xtables-monitor "$T"/usr/sbin/nfnl_osf \
      "$T"/usr/share/xtables/pf.os "$T"/usr/lib/libiptc.so*
# the firewall is set up by S50router, not by the iptables package script
rm -f "$T"/etc/init.d/S35iptables

# SSH: our own S55sshd (LAN only, host key on /data) instead of the package script
rm -f "$T"/etc/init.d/S50dropbear
ln -sfn /data/rtn10/ssh "$T"/root/.ssh

# dnsmasq is started by S50router; the DNS hook for udhcpd is gone
rm -f "$T"/etc/init.d/S80dnsmasq "$T"/usr/share/udhcpc/default.script.d/rtn10-dns

# regulatory.db is built into the kernel from board/rt-n10/firmware

# iw is no longer selected (regdb is built into the kernel); drop leftovers
rm -f "$T"/usr/sbin/iw
