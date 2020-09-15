#!/bin/bash
set -e

cow_ver="$(curl -skL https://api.github.com/repos/Mikubill/cowtransfer-uploader/releases/latest | grep -oP '"tag_name": "\K(.*)(?=")')"
curl -skL https://github.com/Mikubill/cowtransfer-uploader/releases/download/"$cow_ver"/cowtransfer-uploader_"${cow_ver/v/}"_linux_amd64.tar.gz | tar -xz -C /tmp
#chmod +x /tmp/cowtransfer-uploader

FILE=$1
FILENAME=$(basename $FILE)
SIZE="$(du -h $FILE | awk '{print $1}')"
cow_data=$(/tmp/cowtransfer-uploader $FILE)
cow_url=$(echo $cow_data | cut -d' ' -f2)
data="$FILENAME-$SIZE-${cow_url}"
echo $data
curl -skLo /dev/null "https://wxpusher.zjiecode.com/api/send/message/?appToken=${WXPUSHER_APPTOKEN}&uid=${WXPUSHER_UID}&content=${data}"
