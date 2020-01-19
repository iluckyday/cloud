#!/bin/bash
#

set -e

DEBIAN_FRONTEND=noninteractive apt update
DEBIAN_FRONTEND=noninteractive apt install -qq debootstrap qemu-utils

imagedir=/mnt/sid
include="locales,systemd-sysv"
device=$(losetup -f)

dd if=/dev/zero of=/dev/shm/sid.raw bs=1 count=0 seek=10G
losetup $device /dev/shm/sid.raw
mkfs.ext4 -F -L debian-root -b 1024 -I 128 -O "^has_journal" $device
tune2fs -i 0 $device

mkdir -p $imagedir
mount $device $imagedir

/usr/sbin/debootstrap --no-check-gpg --components=main,contrib,non-free --variant=minbase --include="$include" sid /mnt/sid http://deb.debian.org/debian

mount --bind /dev $imagedir/dev
chroot $imagedir mount -t proc none /proc
chroot $imagedir mount -t sysfs none /sys
chroot $imagedir mount -t devpts none /dev/pts

echo -e "nameserver 8.8.8.8\nnameserver 8.8.4.4" > $imagedir/etc/resolv.conf
#echo tcp_bbr >> $imagedir/etc/modules
sed -i '/src/d' $imagedir/etc/apt/sources.list

cat << EOF > $imagedir/etc/fstab
LABEL=debian-root /        ext4  defaults,noatime                            0 0
tmpfs             /tmp     tmpfs mode=1777,strictatime,nosuid,nodev,size=90% 0 0
tmpfs             /var/log tmpfs defaults,noatime                            0 0
EOF

mkdir -p $imagedir/etc/apt/apt.conf.d
cat << EOF > $imagedir/etc/apt/apt.conf.d/99-freedisk
APT::Authentication "0";
APT::Get::AllowUnauthenticated "1";
Dir::Cache "/dev/shm";
Dir::State::lists "/dev/shm";
Dir::Log "/dev/shm";
DPkg::Post-Invoke {"/bin/rm -f /dev/shm/archives/*.deb || true";};
EOF

mkdir -p $imagedir/etc/dpkg/dpkg.cfg.d
cat << EOF > $imagedir/etc/dpkg/dpkg.cfg.d/99-nodoc
path-exclude /usr/share/doc/*
path-exclude /usr/share/man/*
path-exclude /usr/share/groff/*
path-exclude /usr/share/info/*
path-exclude /usr/share/lintian/*
path-exclude /usr/share/linda/*
path-exclude /usr/share/locale/*
path-include /usr/share/locale/en*
EOF

mkdir -p $imagedir/etc/systemd/journald.conf.d
cat << EOF > $imagedir/etc/systemd/journald.conf.d/storage.conf
[Journal]
Storage=volatile
EOF

cat << EOF >> $imagedir/root/.bashrc
export HISTSIZE=1000 LESSHISTFILE=/dev/null HISTFILE=/dev/null
EOF

mkdir -p $imagedir/etc/sysctl.d
cat << EOF >> $imagedir/etc/sysctl.d/10-tcp_bbr.conf
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
EOF

cat << EOF > $imagedir/etc/sysctl.d/20-security.conf
net.ipv4.tcp_syncookies = 1
net.ipv4.tcp_synack_retries = 5
net.ipv4.tcp_syncookies = 1
net.ipv4.icmp_ignore_bogus_error_responses=1
net.ipv4.icmp_echo_ignore_all = 1
EOF

chroot $imagedir /bin/bash -c "
export PATH=/bin:/sbin:/usr/bin:/usr/sbin
echo root:debian | chpasswd
ln -sf /usr/share/zoneinfo/Asia/Shanghai /etc/localtime
echo 'en_US.UTF-8 UTF-8' > /etc/locale.gen
dpkg-reconfigure --priority=critical locales

mkdir /tmp/apt
DEBIAN_FRONTEND=noninteractive apt -o Dir::Cache=/tmp/apt -o Dir::State::lists=/tmp/apt update
DEBIAN_FRONTEND=noninteractive apt -o Dir::Cache=/tmp/apt -o Dir::State::lists=/tmp/apt install -y -qq linux-image-cloud-amd64 extlinux syslinux-common
dd bs=440 count=1 conv=notrunc if=/usr/lib/extlinux/mbr.bin of=$device
extlinux -i /boot

systemctl enable systemd-networkd
systemctl -f mask apt-daily.timer apt-daily-upgrade.timer fstrim.timer motd-news.timer

rm -rf /etc/hostname /tmp/apt /var/log/* /usr/share/doc/* /usr/local/share/doc/* /usr/share/man/* /tmp/* /var/tmp/* /var/cache/apt/*
find /usr/share/locale -mindepth 1 -maxdepth 1 ! -name 'en' -exec rm -rf {} +
find /usr/share/zoneinfo -mindepth 1 -maxdepth 2 ! -name 'UTC' -a ! -name 'UCT' -a ! -name 'PRC' -a ! -name 'Asia' -a ! -name '*Shanghai' -exec rm -rf {} +
"

if [ -f $imagedir/root/.bash_history ]; then
	shred --remove $imagedir/root/.bash_history
fi


umount $imagedir/dev/pts $imagedir/dev $imagedir/proc $imagedir/sys/fs/fuse/connections $imagedir/sys
sleep 1

while [ -n "`lsof $imagedir`" ]; do
	sleep 1
done

umount $imagedir
losetup -d $device
sync
qemu-img convert -c -f raw -O qcow2 /dev/shm/sid.raw /dev/shm/sid.qcow2

ls -lh /dev/shm/sid.qcow2
