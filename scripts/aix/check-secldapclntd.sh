#!/usr/bin/bash
# This script checks the AIX service secldapclntd
# See http://www.regatta.cs.msu.su/doc/usr/share/man/info/ru_RU/a_doc_lib/cmds/aixcmds5/secldapclntd.htm
#
# This services fails too often:
#  * sometimes does not reply, its hung
#  * sometimes it consumes all CPU and takes a lot to reply
#  * sometimes it simply dies
# 
# This script will check it and restart it if necesary.
# 
# You can test this script with:
# kill -STOP $(ps -fea| grep -v grep |grep /usr/sbin/secldapclntd| awk '{print $2}' )
#

LDAP_USER=cgetwsad # And user in LDAP to test the service
SCRIPT_NAME=$0
CHECK_TIMEOUT=10
GRACE_TIME=5

# Execute a test command. If it does not end in X seconds, kill an 
# return failure. If it does, return its return code
check_with_timeout_old() {
    [ "$DEBUG" ] && set -x
    COMMAND=$1
    TIMEOUT=$2
    RET=0

    
    # Launch command in backgroup
    [ ! "$DEBUG" ] && exec 6>&2              # Link file descriptor #6 with stderr.
    [ ! "$DEBUG" ] && exec 2> /dev/null      # Send stderr to null (avoid the Terminated messages)
    
    $COMMAND 2>&1 >/dev/null & 
    COMMAND_PID=$!
    [ "$DEBUG" ] && echo "Background command pid $COMMAND_PID, parent pid $$"
    # Timer that will kill the command if timesout
    sleep $TIMEOUT && ps -p $COMMAND_PID -o pid,ppid |grep $$ | awk '{print $1}' | xargs kill &
    KILLER_PID=$!
    [ "$DEBUG" ] && echo "Killer command pid $KILLER_PID, parent pid $$"
    
    wait $COMMAND_PID
    RET=$?
    
    # Kill the killer timer 
    [ "$DEBUG" ] && ps -e -o pid,ppid |grep $KILLER_PID | awk '{print $1}' | xargs echo "Killing processes: "
    ps -e -o pid,ppid |grep -v PID | grep $KILLER_PID | awk '{print $1}' | xargs kill
    wait
    sleep 1

    [ ! "$DEBUG" ] && exec 2>&6 6>&- # Restore stderr and close file descriptor #6.
    return $RET
}

# Execute a test command. If it does not end in X seconds, kill an 
# return failure. If it does, return its return code
check_with_timeout() {
    COMMAND=$1
    TIMEOUT=$2
	# Idea from http://www.commandlinefu.com/commands/view/3583/execute-a-command-with-a-timeout
    perl -e "alarm $TIMEOUT; exec @ARGV" "$COMMAND" 
}


get_secldapclntd_pid() {
    _PID=$(ps -eF pid,ppid,args| grep -v grep |grep /usr/sbin/secldapclntd | awk '{print $1}')
    [ ! -z "_PID" ] && echo $_PID
}

check_secldapclntd() {
    # Check daemon is running
    echo -n "Checking process '/usr/sbin/secldapclntd'..."
    if ! get_secldapclntd_pid; then
        echo "fail."
        return 1
    fi 
    
    # Check lsldap command
    echo -n "Checking 'lsldap'..."
    if check_with_timeout lsldap $CHECK_TIMEOUT > /dev/null; then
        echo "ok."
    else
        echo "lsldap is failing..." 1>&2
        return 2
    fi
    
    # Check id 
    echo -n "Checking 'id $LDAP_USER'..."
    if check_with_timeout "id $LDAP_USER" $CHECK_TIMEOUT > /dev/null; then
        echo "ok."
    else
        RET=$?
        echo "id $LDAP_USER is failing (retcode=$RET)..." 1>&2 
        return 3
    fi
    
}

# Restart the service. Tries three times
do_restart_secldapclntd() {
    COUNT=0
    while [ $COUNT -lt 3 ] && ! ( /usr/sbin/restart-secldapclntd 1>&2 && sleep $GRACE_TIME && check_secldapclntd) ; do
        /usr/sbin/stop-secldapclntd 1>&2 
        SECLDAPCLNTD_PID=$(get_secldapclntd_pid)
        if [ ! -z $SECLDAPCLNTD_PID ]; then
            echo "Killing secldapclntd with pid $SECLDAPCLNTD_PID..." 1>&2 
            kill -9 $SECLDAPCLNTD_PID 1>&2 
        fi
		COUNT=$(($COUNT+1))
    done
}

case $1 in
    check)
        check_secldapclntd
    ;;
    restart)
        do_restart_secldapclntd
    ;;
    check-and-restart)
        if ! check_secldapclntd; then
            echo "secldapclntd is failing... restarting."
            do_restart_secldapclntd
        fi 
    ;;
    *)
        cat <<EOF
Usage: $SCRIPT_NAME <check|restart|check-and-restart>
EOF
    ;;
esac
