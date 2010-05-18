#!/bin/sh

X_TEST_PROGRAMS="xclock xlogo xterm"

if [ $# -lt 1 ]; then
    cat <<EOF
Usage: $0 <user>
        Copy all X11 credentials for this host to destination user using sudo.
EOF
    exit 1
fi

DESTUSER=$1

# Check $DISPLAY variable
if [ ! "$DISPLAY" ]; then
    echo "\$DISPLAY environment variable is not set."
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
    $X_TEST_PROGRAM_BIN
    RET=$?
fi

if [ $RET != 0 ]; then
    echo "Graphical test program failed. "
    echo "Do you really a X server (like Xming) in DISPLAY='$DISPLAY'?"
    read -p "Press ENTER if yes to continue or Ctrl+C to cancel." || exit 1
fi

# Export the key
for DISPLAY_ID in $(xauth list |grep $(hostname) |cut -f 1 -d " "); do
    echo "Exporting $DISPLAY_ID to user $DESTUSER."
    if ! xauth extract - $DISPLAY_ID | sudo -u $DESTUSER -p "$USER's password for sudo: " -H xauth merge -; then
        echo "Failed importing key..."
        exit 1
    fi
done

# Check if sudo popragates the $DISPLAY variable
if ! sudo -u $DESTUSER -p "$USER's password for sudo: " -H env | grep -qe "^DISPLAY=" ; then
    echo "WARNING, sudo does not propagate the \$DISPLAY variable. It must be set manually:"
    echo "  'sudo -H -u $DESTUSER DISPLAY=$DISPLAY <command>'"
    NO_SUDO_ENV_DISPLAY=1
fi

if [ "$X_TEST_PROGRAM_BIN" ]; then
    echo "Testing the display '$DISPLAY' for user '$DESTUSER'. Close the graphical program '$X_TEST_PROGRAM' when displayed"
    sudo -p "$USER's password for sudo: "  -H -u $DESTUSER ${NO_SUDO_ENV_DISPLAY:+DISPLAY=$DISPLAY} $X_TEST_PROGRAM_BIN; RET=$?
    if [ $RET == 1 ]; then
        echo "'$X_TEST_PROGRAM' failed as user '$DESTUSER' :-("
        exit 1
    else 
        echo "It works!!! "
    fi
else 
    echo "Can not find binary for '$X_TEST_PROGRAMS'. Not testing..."
fi

cat <<EOF
To execute any command as '$DESTUSER', use this command line:
 'sudo -H -u $DESTUSER ${NO_SUDO_ENV_DISPLAY:+DISPLAY=$DISPLAY} <command> [<args>]'

So. to work with a shell with '$DESTUSER', execute this command:'
 'sudo -H -u $DESTUSER ${NO_SUDO_ENV_DISPLAY:+DISPLAY=$DISPLAY} sh'
EOF
