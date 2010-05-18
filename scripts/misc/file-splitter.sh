#!/bin/bash
#
# This command splits and compress (or uncompress) using gzip big files.
#
# It can crypt files symmetrically with gpg.
# It can be interrupted, and it will check the last split or all of them.
# It is AIX compilant.
#
# (c) Hector Rivas Gandara <keymon@gmail.com>
# 

# Constants
SCRIPT_NAME=$(basename $0)

usage() {
    cat <<EOF
This command splits and compress (or uncompress) using gzip big files.
It can crypt files symmetrically with gpg.
It can be interrupted, and it will check the last split or all of them.
    
Usage:
        $SCRIPT_NAME [-c|-u] [-e <password>] [-s <split size in MB>] <filename> [filename ...]

       filename: 
          - List of files to split and compress (and optionally crypt)
          - List of split files to check/uncompress  
          - List of destination files whose splits will be checked/uncompressed
        
        -c: Compress (default action).
        -u: Uncompres the files,
        -v: Verify compressed files, but dot not perform any action.        
        -e: Encrypt/Decrpt with gpg using given password
        -s: Set different split size (default 100MB)
        -t: Test the file integrity? This option is valid for compress,
            checking files already compressed, or to uncompress, 
            checking files before uncompress.
        -f: Overwrite file if exists
Example:
        $SCRIPT_NAME -e "Gs4.2GPsa" -s 100 -t MUREX_20100131_01.dmp
        
Known bugs:
    Do not use spaces os special characters in files. 
EOF
    exit 1
}

encrypt() {
    gpg --batch -q --passphrase "$1" --no-secmem-warning --cipher-algo AES256 -c
}

decrypt() {
    gpg --batch -q --passphrase "$1" --no-secmem-warning --cipher-algo AES256 -d
}

check_compressed() {
    file=$1
    echo -n "Checking integrity of $file:"
    gzip -vt < $file
}

check_crypted_compressed() {
    file=$1
    password=$2
    echo -n "Checking integrity of $file:"
    cat $file | decrypt $password | gzip -vt
}

uncompress() {
    gunzip < $1
}

decrypt_uncompress() {
    file=$1
    password=$2
    cat $file | decrypt $password | gunzip 
}

split_compress() {
    shift_size=$1
    count=$2
    total_count=$3
    origfile=$4
    destfile=$5
    echo "Compresing '$origfile' shift of ${shift_size}MB $(($count+1)) of $TOTAL_COUNT to $destfile..."
    time dd if="$origfile" count=$SHIFT_SIZE bs=1M skip=$(($count*$shift_size)) | gzip > "$destfile"
}

split_compress_crypt() {
    shift_size=$1
    count=$2
    total_count=$3
    origfile=$4
    destfile=$5
    password=$6
    echo "Compresing and encrypting '$origfile' shift of ${shift_size}MB $(($count+1)) of $TOTAL_COUNT to $destfile..."
    time dd if="$origfile" count=$SHIFT_SIZE bs=1M skip=$(($count*$shift_size)) | gzip | encrypt $password > "$destfile"
}

do_compress() {
    for FILE in $@; do

        if [ ! -r $FILE ]; then
            echo "Can not read $FILE"
            continue
        fi

        FILE_SIZE=$(du -sm "$FILE" | cut -f 1 | cut -f 1 -d .)

        COUNT=0
        TOTAL_COUNT=$(( ($FILE_SIZE+$SHIFT_SIZE) / $SHIFT_SIZE ))
        while [ $(($COUNT*$SHIFT_SIZE)) -le $FILE_SIZE ]; do
            DEST_FILE="$FILE.$SUFFIX.$(printf '%.3d' $COUNT).gz"
            [ "$ENCRIPT" ] && DEST_FILE=$DEST_FILE.gpg
            NEXT_DEST_FILE="$FILE.$SUFFIX.$(printf '%.3d' $((COUNT+1))).gz"
            [ "$ENCRIPT" ] && NEXT_DEST_FILE=$NEXT_DEST_FILE.gpg

            # If file exists, and we have to test or does not exists next file, check it.
            if [ -f "$DEST_FILE" ] && [ "$TEST" -o ! -f "$NEXT_DEST_FILE" ]; then
                if [ ! "$ENCRIPT" ]; then
                    check_compressed $DEST_FILE || rm -v $DEST_FILE
                else
                    check_crypted_compressed $DEST_FILE $PASSWORD || rm -v $DEST_FILE
                fi
            fi

            if [ ! -f "$DEST_FILE" -o "$OVERWRITE" ]; then
                if [ ! "$ENCRIPT" ]; then
                    split_compress $SHIFT_SIZE $COUNT $TOTAL_COUNT $FILE $DEST_FILE || return 1
                else
                    split_compress_crypt $SHIFT_SIZE $COUNT $TOTAL_COUNT $FILE $DEST_FILE $PASSWORD || return 1
                fi
            else
                echo "'$DEST_FILE' exists, skipping."
            fi
            COUNT=$(($COUNT+1))
        done
    done

}

do_uncompress() {
    # Generate list of original names by removing the suffix.
    MATCH_EXPR="\\.split\\.[0-9][0-9][0-9]\\.gz${ENCRIPT:+\\.gpg}\$"
    FILES=$(for f in $@; do echo $f | sed "s/$MATCH_EXPR//"; done | sort | uniq)

    exec 10>&- #close fd 10. To prevent previously open files.
    
    for FILE in $FILES; do 
        # Check if destination exists
        if [ -f "$FILE" -a ! "$OVERWRITE" ]; then
            echo "$SCRIPT_NAME: file '$FILE' already exists."
            return 1
        fi
    
        # Check that exists split
        if ! ls $FILE.split.[0-9][0-9][0-9].gz${ENCRIPT:+.gpg} > /dev/null 2>&1; then
            echo "$SCRIPT_NAME: Error, no files found with pattern '$FILE.split.[0-9][0-9][0-9].gz${ENCRIPT:+.gpg}'."
            return 1
        fi

        echo "Uncompressing $FILE..."
        exec 10>$FILE # Redirect fd=10 to $FILE
        FAILED=
        for split_file in $FILE.split.[0-9][0-9][0-9].gz${ENCRIPT:+.gpg}; do 
            if [ -f $split_file ]; then 
                echo " - $split_file..."
                if [ ! "$ENCRIPT" ]; then
                    if ! uncompress $split_file 1>&10; then
                        FAILED=1
                        break
                    fi
                else 
                    if ! decrypt_uncompress $split_file $PASSWORD 1>&10; then
                        FAILED=1
                        break
                    fi
                fi
            fi
        done
        exec 10>&- #close fd 10
        if [ "$FAILED" ]; then
            echo "Failed." 
            return 1
        else 
            echo "Ok."
        fi
    done
}

# Check files integrity
do_verify() {
    BAD_FILES=""
    # Generate split file list
    FILES=
    
    MATCH_EXPR="\\.split\\.[0-9][0-9][0-9]\\.gz${ENCRIPT:+\\.gpg}\$"
    FOUND=
    for f in $@; do
        # Add file is it is a "compressed split and exists"
        if echo "$f" | grep -qe "$MATCH_EXPR" > /dev/null && [ -f "$f" ]; then
            FILES="$FILES $f"
            FOUND=1
        else 
            for f2 in $f.split.[0-9][0-9][0-9].gz${ENCRIPT:+.gpg}; do 
                if [ -f "$f2" ]; then 
                    FILES="$FILES $f2"
                    FOUND=1
                fi 
            done 
        fi
        [ !  "$FOUND" ] &&  echo "$SCRIPT_NAME: Warning, no splits found for file '$f'. With given options, files must match pattern '$MATCH_EXPR'." 1>&2
        FOUND=
    done

    
    for FILE in $FILES; do 
        if [ ! "$ENCRIPT" ]; then
            check_compressed $FILE || BAD_FILES="$BAD_FILES $split_file"
        else
            check_crypted_compressed $FILE $PASSWORD || BAD_FILES="$BAD_FILES $split_file"
        fi
    done 
    
    [ "$BAD_FILES" ] &&  echo "List of corrupted files: $BAD_FILES" && return 1
    return 0
}


# Default values 
SHIFT_SIZE=100
SUFFIX="split"
ENCRIPT=
PASSWORD=""
TEST=
ACTION=compress

# Note the quotes around `$TEMP': they are essential!
TEMP=$(getopt cuvtfs:e: "$@") || usage
eval set -- "$TEMP"

while true ; do
    case "$1" in
        -c)
            ACTION=compress
            shift
        ;;
        -u)
            ACTION=uncompress
            shift
        ;;
        -v)
            ACTION=verify
            shift
        ;;
		-s)
            SHIFT_SIZE=$2
            shift 2
        ;;
		-e)
            ENCRIPT=1
            PASSWORD=$2
            shift 2
        ;;
        -t)
            TEST=1
            shift
        ;;
        -u)
            UNCOMPRESS=1
            shift       
        ;;
        -f)
            OVERWRITE=1
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
   echo "$SCRIPT_NAME: You must specify one or more files to split"
   usage
fi

case $ACTION in
    compress)
        do_compress $@ || exit 1
    ;;
    uncompress)
        [ "$TEST" ] && ( do_verify $@ || exit 1 )
        do_uncompress $@ || exit 1
    ;;
    verify)
        do_verify $@ || exit 1
    ;;
esac
