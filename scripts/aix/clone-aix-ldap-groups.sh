#!/bin/sh

SCRIPT_NAME=$(basename $0)

usage() {
    cat <<EOF
AIX LDAP integration is not up to expectations. Its cache daemon, secldapclntd,
has a lot of problems:it often crashes, queries are slow, etc... 

To mitigate problems, one workaround could be create the most important users locally, 
using the KRB5files repository.

With this idea, this script will query a set of given groups from the AIX LDAP 
registry using the AIX command line tools (lsuser, lsgroup), and it will create
them locally (mkgroup, mkuser).

This scripts supports nested groups from Active Directory.

Known Bugs:
 - It updates the members of a group, but ** does not remove ** users not needed.
 - Does not support groups/users with special characters. Probably it will crash.
 
Usage:
        $SCRIPT_NAME [-d|-v|-q] group ...

        -d: Debug mode. Prints commands that will execute but does not really execute them.
        -v: Verbose mode.
        -q: Quiet mode
EOF
    exit 1
}


get_ldap_group_members() {
    local REGISTRY=$1
    local group=$2
    local group_acum=$3 # To avoid loops
    if echo $group_acum | grep -q "#$group#" ; then
        [ ! "$QUIET" ] && echo "Loop detected for group '$group'" 1>&2
        return
    fi

    local member_list=
    local subgroup_member_list=
    
    for member in $(lsgroup -R $REGISTRY -a users $group | cut -f 2 -d = | tr ',' ' '); do
        # Check if is an user
        if lsuser -R ${REGISTRY} ${member} > /dev/null 2>&1; then
            member_list=${member_list}${member_list:+ }${member}
        elif lsgroup -R ${REGISTRY} ${member} > /dev/null 2>&1; then
            [ ! "$QUIET" ] && echo "Following nested group '$member'" 1>&2
            subgroup_member_list=$(get_ldap_group_members ${REGISTRY} ${member} "${group_acum}#${group}#")
            [ "$subgroup_member_list" ] && \
                member_list=${member_list}${member_list:+ }${subgroup_member_list}
        fi
    done
    # Remove duplicates
    member_list=$(echo $member_list | tr ' ' '\n' | sort | uniq | tr '\n' ' ')
    [ ! "$QUIET" ] && echo "Members of group '$group': $member_list" 1>&2

    echo $member_list
}


clone_group() {

    local REGISTRY=$1
    local LOCALREGISTRY=$2
    local LOCALSYSTEM=$3
    local group=$4

    local group_users=$(get_ldap_group_members $REGISTRY $group)
    local valid_group_users=

    ldap_group_id=$(lsgroup -R $REGISTRY -a id $group | cut -f 2- -d "=")
    if ! lsgroup -R $LOCALREGISTRY -a id $group > /dev/null 2>&1; then
        [ "$VERBOSE" ] && echo "Creating group '$group' id=$ldap_group_id" 1>&2
        ${DEBUG:+echo} mkgroup -R $LOCALREGISTRY id=$ldap_group_id  $group 
    else 
        local_group_id=$(lsgroup -R $LOCALREGISTRY -a id $group | cut -f 2- -d "=")
        if [ ! "$local_group_id" == "$ldap_group_id" ]; then
            [ "$VERBOSE" ] && echo "Updating id '$group' $local_group_id => $ldap_group_id"  1>&2
            ${DEBUG:+echo} chgroup -R $LOCALREGISTRY id=$ldap_group_id  $group 
        fi
    fi

    for user in $group_users; do 
        if ldap_user_id=$(lsuser -R $REGISTRY -a id $user | cut -f 2- -d " "); then 
            ldap_user_attrs=$(lsuser -R $REGISTRY -a home $user | cut -f 2- -d " ")
            # Set principal group if it is defined in local repository. if not, set actual group
            local user_pgrp=$(lsuser -R $REGISTRY -a pgrp $user | cut -f 2- -d " ")
            if ! lsgroup -R $LOCALREGISTRY  > /dev/null 2>&1; then
                user_pgrp=$group
            fi
            
            if ! lsuser -R $LOCALREGISTRY $user > /dev/null 2>&1; then 
                [ "$VERBOSE" ] && echo "Creating user '$user'" 1>&2
                ${DEBUG:+echo} mkuser -R $LOCALREGISTRY SYSTEM=$LOCALSYSTEM registry=$LOCALREGISTRY $ldap_user_attrs $ldap_user_id shell=/usr/bin/bash pgrp=$user_pgrp $user && \
                    valid_group_users=${valid_group_users}${valid_group_users:+,}$user 
            else
                [ "$VERBOSE" ] && echo "Updating user '$user'" 1>&2
                ${DEBUG:+echo} chuser -R $LOCALREGISTRY SYSTEM=$LOCALSYSTEM $ldap_user_attrs shell=/usr/bin/bash $user && \
                    valid_group_users=${valid_group_users}${valid_group_users:+,}$user 
            fi
            ${DEBUG:+echo} pwdadm -c $user 
        else 
            echo "Warning: User '$user' does not exist in registry '$REGISTRY'" 1>&2
        fi 
    done 
}

# Note the quotes around `$TEMP': they are essential!   
TEMP=$(getopt dvq "$@") || usage
eval set -- "$TEMP"

while true ; do
    case "$1" in
        -d)
            DEBUG=1
            shift
        ;;
        -v)
            VERBOSE=1
            shift
        ;;
        -q)
            QUIET=1
            shift
        ;;
        --)
            shift
            break
        ;;
        *)
            usage
        ;;
    esac
done

if [ $# -lt 1 ]; then
   echo "$SCRIPT_NAME: You must specify one or more groups"
   usage
fi


for group in $@; do 
    clone_group LDAP KRB5files KRB5files $group
done 

