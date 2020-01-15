#!/bin/bash
set -ex

WORKDIR=/tmp/sid

mkdir -p $WORKDIR/files $WORKDIR/files/home/debian $WORKDIR/files/etc/{dpkg/dpkg.cfg.d,apt/apt.conf.d} $WORKDIR/files/etc/systemd/{system,network,journald.conf.d} $WORKDIR/elements/diy/{extra-data.d,cleanup.d}

cat << "EOF" > $WORKDIR/elements/diy/cleanup.d/99-zz-diy
#!/bin/bash
export TARGET_ROOT
export basedir=$(dirname ${ELEMENTS_PATH%%:*})
find ${basedir}/files -type f -exec bash -c 'dirname {} | sed -e "s@${basedir}/files@@" | xargs -I % bash -c "mkdir -p $TARGET_ROOT%; sudo cp {} $TARGET_ROOT%"' \;

sudo touch $TARGET_ROOT/home/${DIB_DEV_USER_USERNAME}/.hushlogin
echo -e "\n\nexport HISTSIZE=1000 LESSHISTFILE=/dev/null HISTFILE=/dev/null"| sudo tee -a $TARGET_ROOT/home/${DIB_DEV_USER_USERNAME}/.bashrc
echo debian | sudo tee $TARGET_ROOT/etc/hostname
echo -e "\n\nnet.core.default_qdisc=fq\nnet.ipv4.tcp_congestion_control=bbr" | sudo tee -a $TARGET_ROOT/etc/sysctl.conf
sed -i '/src/d' $TARGET_ROOT/etc/apt/sources.list

sudo chroot $TARGET_ROOT systemctl enable systemd-networkd
sudo chroot $TARGET_ROOT systemctl -f mask apt-daily.timer apt-daily-upgrade.timer fstrim.timer motd-news.timer

#sudo chroot $TARGET_ROOT apt remove --purge -y 

sudo rm -rf $TARGET_ROOT/etc/dib-manifests $TARGET_ROOT/var/log/* $TARGET_ROOT/usr/share/doc/* $TARGET_ROOT/usr/share/local/doc/* $TARGET_ROOT/usr/share/man/* $TARGET_ROOT/tmp/* $TARGET_ROOT/var/tmp/* $TARGET_ROOT/var/cache/apt/*
sudo find $TARGET_ROOT/usr/share/locale -mindepth 1 -maxdepth 1 ! -name 'en' -exec rm -rf {} +
EOF
chmod +x $WORKDIR/elements/diy/cleanup.d/99-zz-diy

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
sed -i 's/4096/16384 -O ^has_journal/' "$PY_DIB_PATH"/lib/disk-image-create
sed -i 's/linux-image-amd64/linux-image-cloud-amd64/' "$PY_DIB_PATH"/elements/debian-minimal/package-installs.yaml
sed -i 's/vga=normal/quiet ipv6.disable=1 intel_iommu=on/' "$PY_DIB_PATH"/elements/*/*/*-bootloader
sed -i -e '/gnupg/d' -e '/python/d' "$PY_DIB_PATH"/elements/debian-minimal/root.d/75-debian-minimal-baseinstall
sed -i -e '/lsb-release/{n;d}' -e '/lsb-release/d' "$PY_DIB_PATH"/elements/debootstrap/package-installs.yaml
rm -rf "$PY_DIB_PATH"/elements/{*/*/*-cloud-init,*/*/*-debian-networking,*/*/*-baseline-environment,*/*/*-baseline-tools}

#DIB_QUIET=1 \
DIB_IMAGE_SIZE=20 \
DIB_JOURNAL_SIZE=0 \
DIB_EXTLINUX=1 \
ELEMENTS_PATH=$WORKDIR/elements \
DIB_IMAGE_CACHE=/dev/shm \
DIB_RELEASE=unstable \
DIB_DEBIAN_COMPONENTS=main,contrib,non-free \
DIB_APT_MINIMAL_CREATE_INTERFACES=0 \
DIB_DEBOOTSTRAP_EXTRA_ARGS+=" --no-check-gpg" \
DIB_DEV_USER_USERNAME=debian \
DIB_DEV_USER_PASSWORD=debian \
DIB_DEV_USER_SHELL=/bin/bash \
DIB_DEV_USER_PWDLESS_SUDO=yes \
DIB_DEBOOTSTRAP_DEFAULT_LOCALE=en_US.UTF-8 \
disk-image-create -o /dev/shm/sid-`date "+%Y%m%d"` vm block-device-mbr cleanup-kernel-initrd devuser diy debian-minimal

ls -lh /dev/shm/sid-*.qcow2
exit 0

ffsend_ver="$(curl -skL https://api.github.com/repos/timvisee/ffsend/releases/latest | grep -oP '"tag_name": "\K(.*)(?=")')"
curl -skL -o /tmp/ffsend https://github.com/timvisee/ffsend/releases/download/"$ffsend_ver"/ffsend-"$ffsend_ver"-linux-x64-static
chmod +x /tmp/ffsend

/tmp/ffsend -Ifyq upload /dev/shm/sid-*.qcow2
