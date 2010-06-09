#!/bin/sh

SCRIPT_NAME=$(basename $0)
X_TEST_PROGRAMS="xclock xlogo xterm"
X_TEST_PROGRAM_BIN_OUTPUT=/tmp/$$.output


[ -x "$SHELL" ] || export SHELL=/bin/sh

if [ $# -lt 1 ]; then
    cat <<EOF
Usage: $0 <user>
        Copy all X11 credentials for this host to destination user using sudo.
EOF
    exit 1
fi

DESTUSER=$1

# Search for xauth:
if [ ! "$XAUTH" ]; then  
	if which xauth > /dev/null 2>&1; then
		XAUTH=$(which xauth)
	else 
		for i in /usr/bin /usr/bin/X11 /usr/bin/X11R6 /usr/X11R6/bin /usr/local/bin /usr/local/X11R6/bin; do
			if [ -x $i/xauth ]; then
				XAUTH="$i/xauth"
				echo "Using XAUTH=$XAUTH"
				break
			fi
		done
	fi
fi 
if [ ! "$XAUTH" ]; then  
	cat <<EOF 
$SCRIPT_NAME: Unable to find 'xauth' binary in \$PATH or common locations.

If it is installed, you can manually set it by:
	* Adding it to the \$PATH variable:
		export PATH=\$PATH:/path_to_xauth
	* Setting XAUTH variable:
		XAUTH=/path_to_xauth/xauth $0 "$@"
		
EOF
	exit 1
fi

# Check $DISPLAY variable
if [ ! "$DISPLAY" ]; then
    cat <<EOF
$SCRIPT_NAME: \$DISPLAY environment variable is not set.
Possible causes:
 * Client is not performing X11 forwarding.
 * Client has not a X11 server configured.
 * xauth command is not installed or failed: ${XAUTH:+Location: $XAUTH}${XAUTH:-Location: $XAUTH}${XAUTH:-xauth not found in $PATH}
 * \$HOME=$HOME is not writable and .XAuthority initialization failed.
EOF
    exit 1
fi


# Check if X works...
for X_TEST_PROGRAM in $X_TEST_PROGRAMS; do 
    X_TEST_PROGRAM_BIN=$(which $X_TEST_PROGRAM 2>/dev/null) 
    [ "$X_TEST_PROGRAM_BIN" ] && break 
done 

if [ ! "$X_TEST_PROGRAM_BIN" ]; then 
    echo "Can not find binary for '$X_TEST_PROGRAMS'. Not testing..."
    RET=1
else 
    echo "Testing the display '$DISPLAY'. Close the graphical program '$X_TEST_PROGRAM' when displayed"
    $X_TEST_PROGRAM_BIN > $X_TEST_PROGRAM_BIN_OUTPUT 2>&1
    RET=$?
fi

if [ $RET != 0 ]; then
    echo "Graphical test program failed: "
	[ -f $X_TEST_PROGRAM_BIN_OUTPUT ] && cat $X_TEST_PROGRAM_BIN_OUTPUT && rm $X_TEST_PROGRAM_BIN_OUTPUT
	echo 
    echo "Do you really a X server (like Xming) in DISPLAY='$DISPLAY'?"
	
    read -p "Press ENTER if yes to continue or Ctrl+C to cancel." || exit 1
fi
[ -f $X_TEST_PROGRAM_BIN_OUTPUT ] && rm $X_TEST_PROGRAM_BIN_OUTPUT

# Check sudo
if ! which sudo > /dev/null 2>&1; then
	echo "$SCRIPT_NAME: Can not find 'sudo' command in $PATH."
	exit 1
fi
if ! sudo -u $DESTUSER -p "$USER's password for sudo: " -H true; then
	echo "$SCRIPT_NAME: sudo to user '$DESTUSER' failed."
	exit 1
fi

# Export the key
for DISPLAY_ID in $($XAUTH list |grep $(hostname) |cut -f 1 -d " "); do
    echo "Exporting $DISPLAY_ID to user $DESTUSER."
    if ! $XAUTH extract - $DISPLAY_ID > /dev/null || \ # first check that we can export
		! $XAUTH extract - $DISPLAY_ID | \
			sudo -u $DESTUSER -p "$USER's password for sudo: " -H $XAUTH merge -; then
        echo "Failed importing key..."
        exit 1
    fi
done

# Check if sudo popragates the $DISPLAY variable
if ! sudo -u $DESTUSER -p "$USER's password for sudo: " -H env | grep -qe "^DISPLAY=" ; then
    echo "WARNING, sudo does not propagate the \$DISPLAY variable. It must be set manually."
    NO_SUDO_ENV_DISPLAY=1
	if ! sudo -u $DESTUSER -p "$USER's password for sudo: " -H DISPLAY=$DISPLAY env | grep -qe "^DISPLAY=" 2>/dev/null; then
		echo "WARNING, this is an old 'sudo' package, can not accept variables in command line. Hacking it..."
		SUDO_DONT_SUPPORTS_VARS_IN_CMD=1
		SUDO_CMD="sudo -H -u $DESTUSER $SHELL -c \\'DISPLAY=$DISPLAY \$__CMD\\'"
	else 
		SUDO_SUPPORTS_VARS_IN_CMD=0
		SUDO_CMD="sudo -H -u $DESTUSER DISPLAY=$DISPLAY \$__CMD"
	fi
else 
	SUDO_CMD="sudo -H -u $DESTUSER \$__CMD"
fi

if [ "$X_TEST_PROGRAM_BIN" ]; then
    echo "Testing the display '$DISPLAY' for user '$DESTUSER'. Close the graphical program '$X_TEST_PROGRAM' when displayed"
    __CMD=$X_TEST_PROGRAM_BIN eval eval $SUDO_CMD > $X_TEST_PROGRAM_BIN_OUTPUT 2>&1; RET=$?
	
    if [ $RET == 1 ]; then
        echo "'$X_TEST_PROGRAM' failed as user '$DESTUSER' :-("
		[ -f $X_TEST_PROGRAM_BIN_OUTPUT ] && cat $X_TEST_PROGRAM_BIN_OUTPUT && rm $X_TEST_PROGRAM_BIN_OUTPUT
        exit 1
    else 
		[ -f $X_TEST_PROGRAM_BIN_OUTPUT ] && rm $X_TEST_PROGRAM_BIN_OUTPUT
        echo "It works!!! "
    fi
else 
    echo "Can not find binary for '$X_TEST_PROGRAMS'. Not testing..."
fi

EXAMPLE1=$(__CMD="<command>" eval echo $SUDO_CMD)
EXAMPLE2=$(__CMD="exec $SHELL" eval echo $SUDO_CMD)
cat <<EOF
To execute any command as '$DESTUSER', use this command line:
 "$EXAMPLE1"

So. to work with a shell with '$DESTUSER', execute this command:'
 "$EXAMPLE2"
EOF
