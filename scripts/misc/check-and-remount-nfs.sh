#!/bin/sh
# This script will check the avaliability of a list of NFS mount point, 
# forcing a remount of those that do not respond in 5 seconds.
# 
# It basically does this:
#   NFSPATH=/mountpoint TIMEOUT=5; perl -e "alarm $TIMEOUT; exec @ARGV" "test -d $NFSPATH" || (umount -fl $NFSPATH; mount $NFSPATH)
# 

TIMEOUT=5
SCRIPT_NAME=$(basename $0)

for i in $@; do
	echo "Checking $i..."
	if ! perl -e "alarm $TIMEOUT; exec @ARGV" "test -d $i" > /dev/null 2>&1; then
		echo "$SCRIPT_NAME: $i is failing with retcode $?."1>&2
		echo "$SCRIPT_NAME: Submmiting umount -fl $i" 1>&2
		umount -fl $i;
		echo "$SCRIPT_NAME: Submmiting mount $i" 1>&2
		mount $i;
	fi
done
