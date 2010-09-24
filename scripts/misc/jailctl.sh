#!/bin/bash 
# 
# Program: jailctl.sh
# Author: Hector Rivas Gandara <keymon@gmail.com>
# Description: 
#  This script allows to "control" a small chrooted system with a linux
#  (or probably any unix) system. It mounts and starts needed services
# 
#  It will use the location DEVEL_JAIL_HOME=/var/devel-jail, with this tree:
#   - $DEVEL_JAIL_HOME/rootfs/ : 
#     The rootfs with the chrooted fs. It is supposed to be common for al chroots.
#     The /etc/ contains links to /conf/<file|dir>, in other to support customizations.
#     /conf will be $DEVEL_JAIL_HOME/data/$JAIL/conf (see later). e.p.:
#		# ls -l rootfs/etc/ssh
#		lrwxrwxrwx 1 root root 15 2010-08-18 14:15 rootfs/etc/ssh -> ../conf/etc/ssh
#
#   - $DEVEL_JAIL_HOME/jails/$JAIL: 
#     Where the jail will be mounted. 
#
#   - $DEVEL_JAIL_HOME/data/$JAIL: 
#   - $DEVEL_JAIL_HOME/data/<something>: 
#     The actual data of the jail, Here must be some special directories. 
#     Also some common directories, like $DEVEL_JAIL_HOME/data/home: 
#     some sub-directories here:
#   		data/$JAIL/var/run
#   		data/$JAIL/var/run/exim4
#   		data/$JAIL/var/run/autofs
#   		data/$JAIL/var/run/pppconfig
#   		data/$JAIL/var/run/sudo
#   		data/$JAIL/var/run/sshd
#
#   		data/$JAIL/tmp
#   
#   - $DEVEL_JAIL_HOME/data/conf: 
#     Configuration files, mainly files from /etc/
#     Some files and directories:
#		data/dcvignedevj1/conf/etc/group
#		data/dcvignedevj1/conf/etc/host.conf
#		data/dcvignedevj1/conf/etc/hostname
#		data/dcvignedevj1/conf/etc/hosts.allow
#		data/dcvignedevj1/conf/etc/hosts.deny
#		data/dcvignedevj1/conf/etc/issue
#		data/dcvignedevj1/conf/etc/issue.net
#		data/dcvignedevj1/conf/etc/ldap.conf
#		data/dcvignedevj1/conf/etc/motd
#		data/dcvignedevj1/conf/etc/mtab
#		data/dcvignedevj1/conf/etc/nsswitch.conf
#		data/dcvignedevj1/conf/etc/passwd
#
#		data/dcvignedevj1/conf/etc/pam.conf
#		data/dcvignedevj1/conf/etc/pam.d/*
#		data/dcvignedevj1/conf/etc/rc*.d
#		data/dcvignedevj1/conf/etc/init.d/* (like sshd, inetd...)
#		data/dcvignedevj1/conf/etc/default/*
#		data/dcvignedevj1/conf/etc/ssh/*

DEVEL_JAIL_HOME=/var/devel-jail

PROGRAM=$0
MOUNT="mount"
UMOUNT="umount"

# Print error and exists
die() {
    echo "$PROGRAM: $@" 1>&2
    exit 1
}

# Get FSTAB to mount. Carefull, use ' to not expand variables.
# Can be file $DEVEL_JAIL_HOME/data/$JAIL/conf/fstab
# Mount points are related to jail root mounpoint
# bind type will be related to $DEVEL_JAIL_HOME
# $JAIL will be defined
get_fstab() {
    local JAIL=$1
    if [ -f $DEVEL_JAIL_HOME/data/$JAIL/conf/fstab ]; then
        cat $DEVEL_JAIL_HOME/data/$JAIL/conf/fstab | \
            sed 's/[ \t]*#.*//' | grep -v "^$" | \
            while read l; do eval echo $l; done
    else
        cat <<EOF
/rootfs             /           bind     ro         0   0 
/data/home      /home       bind     rw         0   0 
$JAIL-sysfs     /sys        sysfs    defaults   0   0 
$JAIL-proc      /proc       proc     defaults   0   0  
$JAIL-devpts    /dev/pts    devpts   defaults   0   0 
/data/$JAIL/tmp         /tmp        bind     rw         0   0 
/data/$JAIL/var/log   /var/log    bind     rw         0   0 
/data/$JAIL/var/run  /var/run    bind     rw         0   0 
/data/$JAIL/var/tmp  /var/tmp    bind     rw         0   0 
/data/$JAIL/conf      /conf       bind     rw         0   0 
EOF
    fi
}
get_processes_on_path() {
    lsof -Fr +d $1 | sed 's/^p//' 
}

wait_processes_on_path() {
    local DIRECTORY=$1
    local COUNT=$2
    while [ $COUNT -gt 0 ] && [ "$(get_processes_on_path $DIRECTORY)" != "" ]; do
        sleep 1
        COUNT=$(($COUNT-1))
    done
}

#  kill all processes running into given path
# @path Path where kill processes
# @args... optional arguments for kill
kill_on_path() {
    local KILLDIR=$1; shift
    lsof -Fr +d $KILLDIR | sed 's/^p//' | xargs -r kill $@
}

check_jail(){
    local JAIL=$1
    mount | grep -q "$DEVEL_JAIL_HOME/jails/$JAIL"
}

exists_jail() {
    local JAIL=$1
    [ -d "$DEVEL_JAIL_HOME/jails/$JAIL" ] 
}

status_jail() {
    # return true if something is mounted
    local JAIL=$1
    if check_jail $JAIL; then
        echo "$JAIL is running"
        return 0
    else
        echo "$JAIL is stopped"
        return 1
    fi
}

list_jails() {
    for i in $DEVEL_JAIL_HOME/jails/*; do 
        [ -d $i ] && status_jail ${i##$DEVEL_JAIL_HOME/jails/}
    done
}

check_mount() {
    local DEVICE=$(echo $1 | sed 's/\/\+/\//g;s/\/$//')
    local MOUNTPOINT=$(echo $2 | sed 's/\/\+/\//g;s/\/$//')
    mount | grep -q "$DEVICE on $MOUNTPOINT "
}

mount_jail() {
    JAIL=$1
    JAIL_ROOT=$DEVEL_JAIL_HOME/jails/$JAIL

    get_fstab $JAIL | while read DEVICE MOUNTPOINT TYPE OPTIONS X Y; do
        case $TYPE in
            bind)
                if ! check_mount $DEVEL_JAIL_HOME/$DEVICE $MOUNTPOINT; then 
                    echo "Mounting $DEVEL_JAIL_HOME/$DEVICE on $JAIL_ROOT/$MOUNTPOINT"
                    [ ! -d $JAIL_ROOT/$MOUNTPOINT ] && mkdir $JAIL_ROOT/$MOUNTPOINT
                    if [ ! -d  $JAIL_ROOT/$MOUNTPOINT ]; then
                    	echo "$0: $JAIL_ROOT/$MOUNTPOINT does not exists!" 1>&2
		    else
                        $MOUNT -o jail=$JAIL,bind,$OPTIONS \
                            $DEVEL_JAIL_HOME/$DEVICE $JAIL_ROOT/$MOUNTPOINT
                    fi
                fi
            ;;
            bind-root)
                # This is a hack to allow mount the /dev/log and nscd sockets. Suse, I don't known, doesn't allow to create new sockets.
                if ! check_mount $DEVICE $MOUNTPOINT; then 
                    echo "Mounting $DEVEL_JAIL_HOME/$DEVICE on $JAIL_ROOT/$MOUNTPOINT"
                    $MOUNT -o jail=$JAIL,bind,$OPTIONS \
                        $DEVICE $JAIL_ROOT/$MOUNTPOINT
                fi
            ;;
            *)
                if ! check_mount $DEVICE $MOUNTPOIMT; then 
                    echo "Mounting $DEVICE on $JAIL_ROOT/$MOUNTPOINT"
                    $MOUNT -t $TYPE -o $OPTIONS $DEVICE $JAIL_ROOT/$MOUNTPOINT
                fi
            ;;
        esac
    done
    
}

start_jail() {
    JAIL=$1
    JAIL_ROOT=$DEVEL_JAIL_HOME/jails/$JAIL

    if check_jail $JAIL; then
        echo "$JAIL: Already running"
        return 2
    fi

    mount_jail $JAIL 
    
    # Start scripts in default runlevel
    chroot $JAIL_ROOT run-parts --arg=start /etc/rc2.d/
}

stop_jail() {
    JAIL=$1
    JAIL_ROOT=$DEVEL_JAIL_HOME/jails/$JAIL

    if ! check_jail $JAIL; then
        echo "$JAIL: Already stoped"
        return 2
    fi
    
    chroot $JAIL_ROOT run-parts --reverse --arg=stop /etc/rc0.d/
    kill_on_path $JAIL_ROOT
    wait_processes_on_path $JAIL_ROOT 5 
    kill_on_path $JAIL_ROOT -9 
    wait_processes_on_path $JAIL_ROOT 5 
    
    for MOUNTPOINT in $(mount | grep -e "$DEVEL_JAIL_HOME/jails/$JAIL" | cut -f 3 -d " " | sort -r); do
        echo Umounting $MOUNTPOINT
        umount -fl $MOUNTPOINT
    done
}

login_jail() {
    JAIL=$1
    
    if [ "$JAIL" != "rootfs" ]; then 
        JAIL_ROOT=$DEVEL_JAIL_HOME/jails/$JAIL

        if ! check_jail $JAIL; then
            echo "$JAIL: Can not login in stopped jail"
            return 2
        fi
    else
        JAIL_ROOT=$DEVEL_JAIL_HOME/rootfs/
    fi
    
    exec sudo chroot $JAIL_ROOT
}

clone_jail() {
    JAIL_ORIG=$1
    JAIL_DEST=$2
    
    mkdir -p $DEVEL_JAIL_HOME/jails/$JAIL_DEST
    rsync -a $DEVEL_JAIL_HOME/data/$JAIL_ORIG $DEVEL_JAIL_HOME/data/$JAIL_DEST
    
    echo "Configuration must be changed in $DEVEL_JAIL_HOME/data/$JAIL_DEST."
}


help() {
    cat <<EOF
Usage:
        $PROGRAM <action> [options]
Actions:
        start   <jail name>        Start a jail
        stop    <jail name>        Stops a jail
        list                       List jails
        status  [jail name]        List jail status
        login   <jail name|rootfs> Login to given jail. rootfs is common filesystem.
        remount <jail name>        Mounts new decices in fstab
EOF
    exit 0
}


case $1 in
    start)
    	JAILNAME=${2:-$(basename $0 | cut -f 1 -d -)}
        [ ! -z "$JAILNAME" ]  || help
        start_jail $JAILNAME
    ;;
    stop)
    	JAILNAME=${2:-$(basename $0 | cut -f 1 -d -)}
        [ ! -z "$JAILNAME" ]  || help
        stop_jail $JAILNAME
    ;;
    restart)
    	JAILNAME=${2:-$(basename $0 | cut -f 1 -d -)}
        [ ! -z "$JAILNAME" ]  || help
        stop_jail $JAILNAME && start_jail $JAILNAME
    ;;
    remount)
    	JAILNAME=${2:-$(basename $0 | cut -f 1 -d -)}
        [ ! -z "$JAILNAME" ]  || help
        mount_jail $JAILNAME
    ;;
    login)
        [ ! -z "$2" ]  || help
        login_jail $2 
    ;;
    list | status)
    	JAILNAME=${2:-$(basename $0 | cut -f 1 -d -)}
        [ ! -z "$JAILNAME" ]  || help
        if [ "$JAILNAME" == "" ]; then
            list_jails 
        else 
            status_jail $JAILNAME
        fi
    ;;
    clone)
        [ ! -z "$3" ]  || help
        exists_jail $2 || die "$2 does not exists."
        ! exists_jail $3 || die "$3 exists already."
        
        clone_jail $2 $3
    ;;
    *)
        help
    ;;
esac
exit 0
