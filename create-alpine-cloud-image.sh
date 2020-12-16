#!/bin/sh

apt update
apt install -y qemu-utils

qemu-img create -f raw /tmp/alpine.raw 1G
dev=$(losetup --show -f /tmp/alpine.raw)
mkfs.ext4 -F -L alpine-root -b 1024 -I 128 -O "^has_journal" $dev

mount_dir=/mnt/alpine
mkdir -p ${mount_dir}
mount $dev ${mount_dir}

apkg=$(wget -qO- http://dl-cdn.alpinelinux.org/alpine/edge/main/x86_64 | awk -F'"' '/apk-tools-static/ {print$2}')
wget -qO- http://dl-cdn.alpinelinux.org/alpine/edge/main/x86_64/$apkg | tar -xz -C /tmp

/tmp/sbin/apk.static -q -X http://dl-cdn.alpinelinux.org/alpine/edge/main -X http://dl-cdn.alpinelinux.org/alpine/edge/community -X http://dl-cdn.alpinelinux.org/alpine/edge/testing -U --no-cache --allow-untrusted --root ${mount_dir} --initdb add alpine-base openssh qemu-guest-agent e2fsprogs-extra

sleep 2

mount -t proc none ${mount_dir}/proc
mount -o bind /sys ${mount_dir}/sys
mount -o bind /dev ${mount_dir}/dev

rm -f ${mount_dir}/etc/sysctl.d/00-alpine.conf ${mount_dir}/etc/motd ${mount_dir}/etc/init.d/crond ${mount_dir}/etc/init.d/klogd ${mount_dir}/etc/init.d/syslog

echo -e "http://dl-cdn.alpinelinux.org/alpine/edge/main\nhttp://dl-cdn.alpinelinux.org/alpine/edge/community\nhttp://dl-cdn.alpinelinux.org/alpine/edge/testing" > ${mount_dir}/etc/apk/repositories

cat << EOF > ${mount_dir}/etc/inittab
::sysinit:/sbin/openrc sysinit
::sysinit:/sbin/openrc boot
::wait:/sbin/openrc default
tty0::respawn:/sbin/getty 38400 tty0
::ctrlaltdel:/sbin/reboot
::shutdown:/sbin/openrc shutdown
EOF

cat << EOF > ${mount_dir}/etc/init.d/resizefs-root
#!/sbin/openrc-run
name="cloud-init resize rootfs"
command="/usr/sbin/resize2fs $(blkid -o device)"
EOF
chmod +x ${mount_dir}/etc/init.d/resizefs-root

cat << EOF > ${mount_dir}/etc/profile.d/ash_history.sh
export HISTFILE=/dev/null
EOF

cat << EOF > ${mount_dir}/etc/fstab
LABEL=alpine-root /        ext4  defaults,noatime       0 0
tmpfs             /tmp     tmpfs mode=1777              0 0
tmpfs             /var/log tmpfs defaults,noatime       0 0
EOF

cat << EOF > ${mount_dir}/etc/network/interfaces
auto lo
iface lo inet loopback

auto eth0
iface eth0 inet dhcp
EOF

echo GA_PATH="/dev/vport1p1" >> ${mount_dir}/etc/conf.d/qemu-guest-agent

mkdir -p ${mount_dir}/root/.ssh
echo "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIDyuzRtZAyeU3VGDKsGk52rd7b/rJ/EnT8Ce2hwWOZWp" >> ${mount_dir}/root/.ssh/authorized_keys
chmod 600 ${mount_dir}/root/.ssh/authorized_keys

chroot ${mount_dir} /bin/sh -c "
echo "root:root" | chpasswd
echo nameserver 8.8.8.8 > /etc/resolv.conf
apk add -U --no-cache syslinux linux-virt
dd bs=440 count=1 if=/usr/share/syslinux/mbr.bin of=$dev
extlinux -i /boot
rm -f /boot/System.map*
rc-update add devfs sysinit
rc-update add mdev sysinit
rc-update add hwdrivers sysinit
rc-update add resizefs-root sysinit
rc-update add modules boot
rc-update add sysctl boot
rc-update add hostname boot
rc-update add bootmisc boot
rc-update add networking boot
rc-update add urandom boot
rc-update add sshd boot
rc-update add qemu-guest-agent boot
rc-update add mount-ro shutdown
rc-update add killprocs shutdown
"
cat << EOF > ${mount_dir}/boot/extlinux.conf
PROMPT 0
TIMEOUT 0
DEFAULT alpine

LABEL alpine
    LINUX vmlinuz-virt
    INITRD initramfs-virt
    APPEND root=LABEL=alpine-root modules=ext4 quiet
EOF


sync ${mount_dir}
sleep 1
umount ${mount_dir}/dev ${mount_dir}/proc ${mount_dir}/sys
sleep 1
umount ${mount_dir}
losetup -d $dev

qemu-img convert -f raw -O qcow2 -c /tmp/alpine.raw /tmp/calpine.img

echo Done.
