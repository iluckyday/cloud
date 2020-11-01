#!/bin/bash
set -e

ver="$(curl -skL https://api.github.com/repos/Mikubill/transfer/releases/latest | grep -oP '"tag_name": "\K(.*)(?=")')"
curl -skL https://github.com/Mikubill/transfer/releases/download/"$ver"/transfer_"${ver/v/}"_linux_amd64.tar.gz | tar -xz -C /tmp

END=$1
FILE=$2

case $END in
	arp)
		echo "arp"
		;;
	bit)
		echo "bit"
		;;
	cat)
		echo "cat"
		;;
	cow)
		TYPE="cow"
		;;
	gof)
		echo "gof"
		;;
	tmp)
		echo "tmp"
		;;
	vim)
		echo "vim"
		;;
	wss)
		echo "wss"
		;;
	wet)
		echo "wet"
		;;
	flk)
		echo "flk"
		;;
	trs)
		echo "trs"
		;;
	lzs)
		echo "lzs"
		;;
	*)
		echo "error"
		exit
esac

t_data=$(/tmp/transfer $END --silent $FILE)

FILENAME=$(basename $FILE)
SIZE="$(du -h $FILE | awk '{print $1}')"
data="$FILENAME-$SIZE-${t_data}"
curl -skLo /dev/null "https://wxpusher.zjiecode.com/api/send/message/?appToken=${WXPUSHER_APPTOKEN}&uid=${WXPUSHER_UID}&content=${data}"
