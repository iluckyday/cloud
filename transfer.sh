#!/bin/bash
set -e

ver="$(curl -skL https://api.github.com/repos/Mikubill/transfer/releases/latest | grep -oP '"tag_name": "\K(.*)(?=")')"
curl -skL https://github.com/Mikubill/transfer/releases/download/"$ver"/transfer_"${ver/v/}"_linux_amd64.tar.gz | tar -xz -C /tmp

FILE=$1
FILENAME=$(basename $FILE)
SIZE="$(du -h $FILE | awk '{print $1}')"
cow_data=$(/tmp/transfer cow --silent $FILE)
cow_url=$(echo $cow_data | cut -d' ' -f2)
data="$FILENAME-$SIZE-${cow_url}"
echo $data
curl -skLo /dev/null "https://wxpusher.zjiecode.com/api/send/message/?appToken=${WXPUSHER_APPTOKEN}&uid=${WXPUSHER_UID}&content=${data}"
