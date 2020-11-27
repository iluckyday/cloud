#!/bin/sh
set -e

export DEBIAN_FRONTEND=noninteractive
apt-config dump | grep -we Recommends -e Suggests | sed 's/1/0/' | tee /etc/apt/apt.conf.d/99norecommends
apt update
apt install -y qemu-utils

bootstrap_file=$(curl -skL https://mirror.rackspace.com/archlinux/iso/latest/md5sums.txt | awk '/bootstrap/ {print $2}')
curl -skL https://mirror.rackspace.com/archlinux/iso/latest/${bootstrap_file} | tar -xz -C /tmp

rootpath=/tmp/root.x86_64

qemu-img create -f raw /tmp/arch.raw 201G
loopx=$(losetup --show -f -P /tmp/arch.raw)
mkfs.ext4 -F -L arch-root -b 1024 -I 128 -O "^has_journal" $loopx

echo 'Server = https://mirror.rackspace.com/archlinux/$repo/os/$arch' > ${rootpath}/etc/pacman.d/mirrorlist

${rootpath}/bin/arch-chroot ${rootpath} /bin/bash -c "
pacman-key --init
pacman-key --populate archlinux
mount $loopx /mnt
/usr/bin/pacstrap -i -c /mnt linux grub base bash-completion openssh --noconfirm --cachedir /tmp --ignore dhcpcd --ignore logrotate --ignore nano --ignore netctl --ignore usbutils --ignore s-nail
"

root_dir=${rootpath}/mnt

cat << EOF > ${root_dir}/etc/fstab
LABEL=arch-root   /                       ext4  defaults,noatime      0 0
tmpfs             /run                    tmpfs defaults,size=90%     0 0
tmpfs             /tmp                    tmpfs mode=1777,size=90%    0 0
tmpfs             /var/log                tmpfs defaults,noatime      0 0
tmpfs             /root/.cache            tmpfs   rw,relatime         0 0
tmpfs             /var/cache/pacman       tmpfs   rw,relatime         0 0
tmpfs             /var/lib/pacman/sync    tmpfs   rw,relatime         0 0
EOF

mkdir -p ${root_dir}/root/.ssh
echo "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIDyuzRtZAyeU3VGDKsGk52rd7b/rJ/EnT8Ce2hwWOZWp" >> ${root_dir}/root/.ssh/authorized_keys
chmod 600 ${root_dir}/root/.ssh/authorized_keys

echo 'Server = https://mirrors.aliyun.com/archlinux/$repo/os/$arch' > ${root_dir}/etc/pacman.d/mirrorlist

cat << EOF > ${root_dir}/etc/systemd/network/20-dhcp.network
[Match]
Name=en*
[Network]
DHCP=yes
IPv6AcceptRA=yes
EOF

cat << EOF >> ${root_dir}/root/.bashrc
export HISTSIZE=1000 LESSHISTFILE=/dev/null HISTFILE=/dev/null
EOF

mkdir -p ${root_dir}/etc/systemd/system-generators
cat << "EOF" > ${root_dir}/etc/systemd/system-generators/masked-unit-generator
#!/bin/sh
set -eu
gendir="$1"
while IFS= read -r line
do
  if [ -n "$line" ]; then
    ln -sf "/dev/null" "$gendir/$line"
  fi
done < /etc/systemd/system/masked.units
EOF
chmod +x ${root_dir}/etc/systemd/system-generators/masked-unit-generator

cat << EOF > ${root_dir}/etc/systemd/system/masked.units
lvm2-lvmetad.service
lvm2-monitor.service
lvm2-lvmetad.socket
man-db.timer
shadow.timer
EOF

mount -o bind /dev ${root_dir}/dev
mount -o bind /proc ${root_dir}/proc
mount -o bind /sys ${root_dir}/sys

echo GRUB_TIMEOUT=0 >> ${root_dir}/etc/default/grub
echo 'GRUB_CMDLINE_LINUX_DEFAULT="console=ttyS0 quiet"' >> ${root_dir}/etc/default/grub

${rootpath}/bin/arch-chroot ${rootpath} /usr/bin/pacstrap -i -c /mnt linux

chroot ${root_dir} /bin/bash -c "
cp /etc/skel/.bash_profile /root
systemctl enable systemd-networkd systemd-resolved sshd
ln -sf /run/systemd/resolve/stub-resolv.conf /etc/resolv.conf

echo 'MODULES=(virtio_blk)' >> /etc/mkinitcpio.d/linux.preset
echo 'COMPRESSION="zstd"' >> /etc/mkinitcpio.d/linux.preset

mkinitcpio -z zstd -k /boot/vmlinuz-linux -c /etc/mkinitcpio.conf -g /boot/initramfs-linux.img
rm -f /boot/initramfs-linux-fallback.img

grub-install --force $loopx
grub-mkconfig -o /boot/grub/grub.cfg

rm -rf /var/log/* /usr/share/zoneinfo/* /usr/share/doc/* /usr/share/man/* /tmp/* /var/tmp/* /root/.cache/* /var/cache/pacman/* /var/lib/pacman/sync/*
"

umount ${root_dir}/dev ${root_dir}/proc ${root_dir}/sys
sleep 1
umount $loopx
sleep 1
losetup -d $loopx

qemu-img convert -c -f raw -O qcow2 /tmp/arch.raw /tmp/arch.img
