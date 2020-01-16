#!/bin/bash
set -e

WORKDIR=/tmp/sid

mkdir -p $WORKDIR/files $WORKDIR/files/home/debian $WORKDIR/files/etc/{dpkg/dpkg.cfg.d,apt/apt.conf.d} $WORKDIR/files/etc/systemd/{system,network,journald.conf.d} $WORKDIR/elements/diy/{post-install.d,post-root.d,cleanup.d}

cat << 'EOF' > $WORKDIR/elements/diy/post-install.d/99-zz-diy
#!/bin/bash

sudo -u ${DIB_DEV_USER_USERNAME} sh -c "touch /home/${DIB_DEV_USER_USERNAME}/.hushlogin"
echo -e "\nexport HISTSIZE=1000 LESSHISTFILE=/dev/null HISTFILE=/dev/null"| sudo -u ${DIB_DEV_USER_USERNAME} tee -a /home/${DIB_DEV_USER_USERNAME}/.bashrc

systemctl enable systemd-networkd
systemctl disable e2scrub_reap.service
systemctl mask apt-daily.timer e2scrub_reap.service apt-daily-upgrade.timer e2scrub_all.timer fstrim.timer motd-news.timer
EOF
chmod +x $WORKDIR/elements/diy/post-install.d/99-zz-diy

cat << EOF > $WORKDIR/elements/diy/post-root.d/99-zz-diy
#!/bin/bash
set -x

TBDIR=\$TMP_BUILD_DIR/mnt

cp -R $WORKDIR/files/* \${TBDIR}
echo -e "\nnet.core.default_qdisc=fq\nnet.ipv4.tcp_congestion_control=bbr" | tee -a \$TBDIR/etc/sysctl.conf
for f in /etc/hostname /etc/dib-manifests "/var/log/*" "/usr/share/doc/*" "/usr/share/local/doc/*" "/usr/share/man/*" "/tmp/*" "/var/tmp/*" "/var/cache/apt/*" ; do
    rm -rf \$TBDIR\$f
done
find \$TBDIR/usr/share/locale -mindepth 1 -maxdepth 1 ! -name 'en' -exec rm -rf {} +
EOF
chmod +x $WORKDIR/elements/diy/post-root.d/99-zz-diy

cat << 'EOF' > $WORKDIR/elements/diy/cleanup.d/99-zz-diy
#!/bin/bash

chroot $TARGET_ROOT apt remove --purge -y python* libpython*
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

cat << EOF > $WORKDIR/block.yaml
- local_loop:
    name: image0

- partitioning:
    base: image0
    label: mbr
    partitions:
      - name: root
        flags: [ boot, primary ]
        size: 100%
        mkfs:
          name: mkfs_root
          base: root
          type: ext4
          label: cloudimage-root
          opts: "-i 16384 -O ^has_journal"
          mount:
            mount_point: /
            fstab:
              options: "defaults,noatime"
              fsck-passno: 0
EOF

PY_DIB_PATH=$(python3 -c "import os,diskimage_builder; print(os.path.dirname(diskimage_builder.__file__))")
sed -i 's/linux-image-amd64/linux-image-cloud-amd64/' "$PY_DIB_PATH"/elements/debian-minimal/package-installs.yaml
sed -i 's/vga=normal/quiet ipv6.disable=1/' "$PY_DIB_PATH"/elements/bootloader/cleanup.d/51-bootloader
sed -i -e '/gnupg/d' "$PY_DIB_PATH"/elements/debian-minimal/root.d/75-debian-minimal-baseinstall
sed -i '/lsb-release/,/^/d' "$PY_DIB_PATH"/elements/debootstrap/package-installs.yaml
for i in cloud-init debian-networking baseline-environment baseline-tools write-dpkg-manifest copy-manifests-dir ; do
    rm -rf "$PY_DIB_PATH"/elements/*/*/*$i
done

DIB_QUIET=0 \
DIB_IMAGE_SIZE=10 \
DIB_BLOCK_DEVICE_CONFIG=file://$WORKDIR/block.yaml \
DIB_JOURNAL_SIZE=0 \
DIB_EXTLINUX=1 \
ELEMENTS_PATH=$WORKDIR/elements \
DIB_IMAGE_CACHE=/dev/shm \
DIB_PYTHON_VERSION=3 \
DIB_RELEASE=unstable \
DIB_DEBIAN_COMPONENTS=main,contrib,non-free \
DIB_APT_MINIMAL_CREATE_INTERFACES=0 \
DIB_DEBOOTSTRAP_EXTRA_ARGS+=" --no-check-gpg" \
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
