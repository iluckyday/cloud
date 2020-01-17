#!/bin/bash
set -e

WORKDIR=/tmp/sid

mkdir -p $WORKDIR/files $WORKDIR/files/home/debian $WORKDIR/files/etc/{dpkg/dpkg.cfg.d,apt/apt.conf.d} $WORKDIR/files/etc/systemd/{system,network,journald.conf.d} $WORKDIR/elements/diy/cleanup.d

cat << EOF > $WORKDIR/elements/diy/cleanup.d/99-zz-diy-config
#!/bin/bash

cp -R $WORKDIR/files/* \$TARGET_ROOT
echo -e "\nnet.core.default_qdisc=fq\nnet.ipv4.tcp_congestion_control=bbr" | tee -a \$TARGET_ROOT/etc/sysctl.conf
for f in /etc/hostname /etc/dib-manifests /var/log/* /usr/share/doc/* /usr/share/local/doc/* /usr/share/man/* /tmp/* /var/tmp/* /var/cache/apt/* ; do
    rm -rf \$TARGET_ROOT\$f
done
find \$TARGET_ROOT/usr/share/locale -mindepth 1 -maxdepth 1 ! -name 'en' -exec rm -rf {} +

chroot --userspec=\${DIB_DEV_USER_USERNAME}:\${DIB_DEV_USER_USERNAME} \$TARGET_ROOT /bin/bash -c "
touch /home/\${DIB_DEV_USER_USERNAME}/.hushlogin
echo 'export HISTSIZE=1000 LESSHISTFILE=/dev/null HISTFILE=/dev/null'| tee -a /home/\${DIB_DEV_USER_USERNAME}/.bashrc
"

chroot \$TARGET_ROOT /bin/bash -c "
echo -e "nameserver 8.8.8.8\nnameserver 8.8.4.4" > /etc/resolv.conf

systemctl enable systemd-networkd
systemctl disable e2scrub_reap.service
systemctl mask apt-daily.timer e2scrub_reap.service apt-daily-upgrade.timer e2scrub_all.timer fstrim.timer motd-news.timer

ln -sf /usr/share/zoneinfo/Asia/Shanghai /etc/localtime
find /usr/share/zoneinfo -mindepth 1 -maxdepth 2 ! -name 'UTC' -a ! -name 'UCT' -a ! -name 'PRC' -a ! -name 'Asia' -a ! -name '*Shanghai' -exec rm -rf {} \;

apt remove --purge -y python* libpython*
"
EOF
chmod +x $WORKDIR/elements/diy/cleanup.d/99-zz-diy-config


cat << EOF > $WORKDIR/files/etc/fstab
LABEL=cloudimg-rootfs /         ext4  defaults,noatime                            0 0
tmpfs                 /tmp      tmpfs mode=1777,strictatime,nosuid,nodev,size=90% 0 0
tmpfs                 /var/log  tmpfs   rw,relatime                               0 0
EOF

cat << EOF > $WORKDIR/files/etc/apt/apt.conf.d/99-freedisk
APT::Authentication "0";
APT::Get::AllowUnauthenticated "1";
Dir::Cache "/dev/shm";
Dir::State::lists "/dev/shm";
Dir::Log "/dev/shm";
DPkg::Post-Invoke {"/bin/rm -f /dev/shm/archives/*.deb || true";};
EOF

cat << EOF > $WORKDIR/files/etc/dpkg/dpkg.cfg.d/99-nodoc
path-exclude /usr/share/doc/*
path-exclude /usr/share/man/*
path-exclude /usr/share/groff/*
path-exclude /usr/share/info/*
path-exclude /usr/share/lintian/*
path-exclude /usr/share/linda/*
path-exclude /usr/share/locale/*
path-include /usr/share/locale/en*
EOF

cat << EOF > $WORKDIR/files/etc/systemd/journald.conf.d/storage.conf
[Journal]
Storage=volatile
EOF

cat << EOF > $WORKDIR/files/etc/systemd/network/20-dhcp.network
[Match]
Name=en*

[Network]
DHCP=ipv4
EOF

PY_DIB_PATH=$(python3 -c "import os,diskimage_builder; print(os.path.dirname(diskimage_builder.__file__))")
sed -i 's/-i 4096/-i 16384 -O ^has_journal/' "$PY_DIB_PATH"/lib/disk-image-create
sed -i 's/linux-image-amd64/linux-image-cloud-amd64/' "$PY_DIB_PATH"/elements/debian-minimal/package-installs.yaml
sed -i 's/vga=normal/quiet ipv6.disable=1/' "$PY_DIB_PATH"/elements/bootloader/cleanup.d/51-bootloader
sed -i -e '/gnupg/d' "$PY_DIB_PATH"/elements/debian-minimal/root.d/75-debian-minimal-baseinstall
sed -i '/lsb-release/,/^/d' "$PY_DIB_PATH"/elements/debootstrap/package-installs.yaml
for i in cloud-init debian-networking baseline-environment baseline-tools write-dpkg-manifest copy-manifests-dir ; do
    rm -rf "$PY_DIB_PATH"/elements/*/*/*$i
done

DIB_QUIET=1 \
DIB_IMAGE_SIZE=10 \
DIB_JOURNAL_SIZE=0 \
DIB_EXTLINUX=1 \
ELEMENTS_PATH=$WORKDIR/elements \
DIB_IMAGE_CACHE=/dev/shm \
DIB_PYTHON_VERSION=3 \
DIB_RELEASE=unstable \
DIB_DEBIAN_COMPONENTS=main,contrib,non-free \
DIB_APT_MINIMAL_CREATE_INTERFACES=0 \
DIB_DEBOOTSTRAP_EXTRA_ARGS+="--no-check-gpg" \
DIB_DEV_USER_USERNAME=debian \
DIB_DEV_USER_PASSWORD=debian \
DIB_DEV_USER_SHELL=/bin/bash \
DIB_DEV_USER_PWDLESS_SUDO=yes \
DIB_DEBOOTSTRAP_DEFAULT_LOCALE=en_US.UTF-8 \
disk-image-create -o /dev/shm/sid-`date "+%Y%m%d"`.qcow2 vm block-device-mbr cleanup-kernel-initrd devuser diy debian-minimal

ffsend_ver="$(curl -skL https://api.github.com/repos/timvisee/ffsend/releases/latest | grep -oP '"tag_name": "\K(.*)(?=")')"
curl -skL -o /tmp/ffsend https://github.com/timvisee/ffsend/releases/download/"$ffsend_ver"/ffsend-"$ffsend_ver"-linux-x64-static
chmod +x /tmp/ffsend

ls -lh /dev/shm/sid-*.qcow2
/tmp/ffsend -Ifyq upload /dev/shm/sid-*.qcow2
