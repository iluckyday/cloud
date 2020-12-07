#!/bin/sh
set -e

include_apps="systemd,systemd-sysv,bash-completion,openssh-server,ca-certificates,v2ray"
exclude_apps="unattended-upgrades"
enable_services="systemd-networkd.service ssh.service v2ray.service resizefs-root.service"
disable_services="apt-daily.timer apt-daily-upgrade.timer e2scrub_all.timer systemd-timesyncd.service e2scrub_reap.service"

export DEBIAN_FRONTEND=noninteractive
apt-config dump | grep -we Recommends -e Suggests | sed 's/1/0/' | tee /etc/apt/apt.conf.d/99norecommends
apt update
apt install -y debootstrap qemu-utils

mount_dir=/tmp/debian

qemu-img create -f raw /tmp/sid.raw 2G
loopx=$(losetup --show -f -P /tmp/sid.raw)

mkfs.ext4 -F -L debian-root -b 1024 -I 128 -O "^has_journal" $loopx

mkdir -p ${mount_dir}
mount $loopx ${mount_dir}

sed -i 's/ls -A/ls --ignore=lost+found -A/' /usr/sbin/debootstrap
/usr/sbin/debootstrap --no-check-gpg --no-check-certificate --components=main,contrib,non-free --include="$include_apps" --exclude="$exclude_apps" --variant minbase sid ${mount_dir}

mount -t proc none ${mount_dir}/proc
mount -o bind /sys ${mount_dir}/sys
mount -o bind /dev ${mount_dir}/dev

cat << EOF > ${mount_dir}/etc/fstab
LABEL=debian-root /        ext4  defaults,noatime                0 0
tmpfs             /run     tmpfs defaults,size=50%               0 0
tmpfs             /tmp     tmpfs mode=1777,size=90%              0 0
tmpfs             /var/log tmpfs defaults,noatime                0 0
EOF

mkdir -p ${mount_dir}/root/.ssh
echo "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIDyuzRtZAyeU3VGDKsGk52rd7b/rJ/EnT8Ce2hwWOZWp" >> ${mount_dir}/root/.ssh/authorized_keys
chmod 600 ${mount_dir}/root/.ssh/authorized_keys

mkdir -p ${mount_dir}/etc/apt/apt.conf.d
cat << EOF > ${mount_dir}/etc/apt/apt.conf.d/99-freedisk
APT::Authentication "0";
APT::Get::AllowUnauthenticated "1";
Dir::Cache "/dev/shm";
Dir::State::lists "/dev/shm";
Dir::Log "/dev/shm";
DPkg::Post-Invoke {"/bin/rm -f /dev/shm/archives/*.deb || true";};
EOF

cat << EOF > ${mount_dir}/etc/apt/apt.conf.d/99norecommend
APT::Install-Recommends "0";
APT::Install-Suggests "0";
EOF

mkdir -p ${mount_dir}/etc/dpkg/dpkg.cfg.d
cat << EOF > ${mount_dir}/etc/dpkg/dpkg.cfg.d/99-nodoc
path-exclude /usr/share/doc/*
path-exclude /usr/share/man/*
path-exclude /usr/share/groff/*
path-exclude /usr/share/info/*
path-exclude /usr/share/lintian/*
path-exclude /usr/share/linda/*
path-exclude /usr/share/locale/*
path-include /usr/share/locale/en*
EOF

mkdir -p ${mount_dir}/etc/systemd/journald.conf.d
cat << EOF > ${mount_dir}/etc/systemd/journald.conf.d/storage.conf
[Journal]
Storage=volatile
EOF

cat << EOF > ${mount_dir}/etc/systemd/network/20-dhcp.network
[Match]
Name=en*

[Network]
DHCP=yes
IPv6AcceptRA=yes
EOF

cat << EOF > ${mount_dir}/root/.bashrc
export HISTSIZE=1000 LESSHISTFILE=/dev/null HISTFILE=/dev/null
EOF

cat << "EOF" > ${mount_dir}/etc/systemd/system/resizefs-root.service
[Unit]
Description=Resize root file system
After=local-fs.target

[Service]
Type=oneshot
ExecStart=/bin/bash -c "resize2fs $(blkid -o device)"

[Install]
WantedBy=multi-user.target
EOF

sed -i '0,/#\?\(ListenAddress\s*\).*$/ s//\1127.0.0.1/' ${mount_dir}/etc/ssh/sshd_config

cat << EOF > ${mount_dir}/etc/v2ray/config.json
{
  "log": {
    "loglevel": "none"
  },
  "inbounds": [{
    "port": 3443,
    "protocol": "vmess",
    "settings": {
      "clients": [{
        "id": "${VUUID}"
      }]
    }
  }],
  "outbounds": [{
    "protocol": "freedom",
    "settings": {}
  }]
}
EOF

mkdir -p ${mount_dir}/boot/syslinux
cat << EOF > ${mount_dir}/boot/syslinux/syslinux.cfg
PROMPT 0
TIMEOUT 0
DEFAULT debian

LABEL debian
        LINUX /vmlinuz
        INITRD /initrd.img
        APPEND root=LABEL=debian-root quiet console=tty1 console=ttyS0
EOF

chroot ${mount_dir} /bin/bash -c "
export PATH=/bin:/sbin:/usr/bin:/usr/sbin DEBIAN_FRONTEND=noninteractive
apt update
apt install -y -o APT::Install-Recommends=0 -o APT::Install-Suggests=0 linux-image-cloud-amd64 extlinux initramfs-tools busybox
dd if=/usr/lib/EXTLINUX/mbr.bin of=$loopx
extlinux -i /boot/syslinux

systemctl enable $enable_services
systemctl disable $disable_services
apt remove -y --purge tzdata

sed -i '/src/d' /etc/apt/sources.list
rm -rf /etc/hostname /etc/resolv.conf /etc/localtime /usr/share/doc /usr/share/man /tmp/* /var/log/* /var/tmp/* /var/cache/apt/* /var/lib/apt/lists/* /usr/bin/perl*.* /usr/bin/systemd-analyze /lib/modules/5.6.0-2-cloud-amd64/kernel/drivers/net/ethernet/ /boot/System.map-*
rm -rf /etc/v2ray/geoip.dat /etc/v2ray/geosite.dat
find /usr/*/locale -mindepth 1 -maxdepth 1 ! -name 'en' -prune -exec rm -rf {} +
"

sync ${mount_dir}
umount ${mount_dir}/dev ${mount_dir}/proc ${mount_dir}/sys
sleep 1
umount ${mount_dir}
sleep 1
losetup -d $loopx

qemu-img convert -c -f raw -O qcow2 /tmp/sid.raw /tmp/vsid.img
