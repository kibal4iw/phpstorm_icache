#!/bin/bash

# Gist: c5f0a118fa07d7be2af85f1b266bff7f
# Github: https://github.com/iusmac/phpstorm_icache
#
# phpStorm – Improved Cache (ICache)
#
# Move the phpStorm cache to RAM while it is in running. All the cache will be synchronized when phpStorm will be closed.
# 

# Params
MOUNT_AS_USER=1000
SHOW_NOTIFICATIONS="yes" # [yes|no]

#
# !! NOT RECOMMENDED !!
PASSWD=""
# If you don't want to pass the password for some sudo operations every time you start phpStorm,
# you can store it in this variable, but it is not recommended for security concerns...
#
# P.S the password from the prompt window / terminal will be temporarily memorized until this script is running,
# so you will need to enter it only once at the start of the session
#

# ABSOLUTE path to executable phpstorm.sh
PHPSTORM_SH_PATH="$HOME/phpStorm/bin/phpstorm.sh"

# ABSOLUTE path to phpStorm directory with configuration files and cache
PHPSTORM_CACHE_PATH="$HOME/.PhpStorm2018.1"

main() {
    prepareDirs

    mountToRam

    startPhpStorm "$*"

    # Will call trap function to sync all
    exit 0;
}

prepareDirs() {
    if [ ! -d $ORIGINAL_SYSTEM_PATH ]; then
        mkdir $ORIGINAL_SYSTEM_PATH || (sendError ; exit)
    fi
    if [ ! -d $BACKUP_SYSTEM_PATH ]; then  
        syncFrom $ORIGINAL_TO_BACKUP || (sendError ; exit)
        rm -rf $ORIGINAL_SYSTEM_PATH/
        mkdir $ORIGINAL_SYSTEM_PATH
    fi
    say "Prepared directories"
}

mountToRam() {
    if ! isCacheMounted; then
        iSudo mount -t tmpfs -o uid=$MOUNT_AS_USER,gid=$MOUNT_AS_USER,mode=0700 tmpfs $ORIGINAL_SYSTEM_PATH
        say "Mounted cache directory to RAM" $?
        syncFrom $BACKUP_TO_ORIGINAL || (sendError ; exit)
    fi
}

startPhpStorm() {
    params=

    [ -n "$1" ] && params=$@
    
    exec /bin/sh $PHPSTORM_SH_PATH $params &
    
    if ! isPhpStormLaunched; then
        sendError
        exit 1
    fi
    say "Launched the phpStorm"
    # Freeze until phpStorm is running
    while isPhpStormLaunched; do
        # To avoid losing the "control" while phpStorm restarts, 
        # we will wait before checking the condition
        sleep 5
    done
}

isPhpStormLaunched() {
    ps -Af | grep -v grep | grep -q "/bin/sh $PHPSTORM_SH_PATH" &>/dev/null
}

isCacheMounted() {
    mount | grep -q $ORIGINAL_SYSTEM_PATH
}

# Imporved sudo with GUI support
iSudo() {
    local cmd=$@

    [ -z "$cmd" ] && exit 1

    while true; do
        case $EXECUTED_IN in
            "terminal")
                # Use the "pre-injected" password
                if [ -n "$PASSWD" ]; then
                    echo "$PASSWD" | sudo -kS $cmd
                    return $?
                else
                    # Require the password
                    sudo -i echo '' 2>/dev/null
                    if [ $? -eq 0 ]; then
                        sudo $cmd
                        return 0
                    else
                        exit 1
                    fi
                fi
            ;;
            "gui")
                getGuiSudoAccess $1
                [ $? -ne 0 ] && exit 1
                echo "$PASSWD" | sudo -kS $cmd
                return 0
            ;;
        esac
    done
}

getGuiSudoAccess() {
    local cmdName=$1
    local passwdPromptState=
    local attempts=3

    while true; do
        # Require the user's password
        if [ -z "$PASSWD" ]; then
            PASSWD="$(zenity \
                            --password \
                            --title='Command "'$cmdName'" requires sudo' \
                            --timeout=20 \
                            2>/dev/null
                     )"
            passwdPromptState=$?
         fi

        if [ ! -z "$PASSWD" ]; then
            # Check for successful sudo login
            echo $PASSWD | sudo -kS echo '' 2>/dev/null
            if [ $? -eq 0 ]; then
                return 0
            else
                PASSWD=
                say "Password incorrect!\nTry again."
            fi
        fi

        ((attempts--))

        if [ "$attempts" -eq 0 ]; then
            zenity \
                --warning \
                --ellipsize \
                --timeout=20 \
                --title="Password attempts exceeded" \
                --text="You have exceeded the number (3) of allowed sudo login attempts\nTry again!" \
                &>/dev/null
            return 1
        elif [ "$passwdPromptState" -eq "$CANCEL_PRESSED" ] || [ "$passwdPromptState" -eq "$TIMEOUT_EXCEEDED" ]; then
            return 1
        fi
    done
}

say() {
    local msg="$1"
    local statusCode="$2"
    if [ -n "$statusCode" ] && [ "$statusCode" -gt 0 ]; then
        sendError
        return "$statusCode"
    fi

    if [ "$SHOW_NOTIFICATIONS" != "yes" ]; then
        return 1
    fi

    notificator "$msg"
    return $?
}

notificator() {
    local msg="$1"

    if [ "$EXECUTED_IN" = "terminal" ]; then
        echo "phpStorm – ICache: $msg"
    else
        zenity \
            --notification \
            --text="phpStorm – ICache: \n$msg" \
            --window-icon="${PHPSTORM_SH_PATH%/*}/phpstorm.png" \
            &>/dev/null
    fi
    return $?
}

syncFrom() {
    case $1 in
    $ORIGINAL_TO_BACKUP)
        rsync \
        -avuq \
        --delete \
        "$ORIGINAL_SYSTEM_PATH/" "$BACKUP_SYSTEM_PATH"
    ;;
    $BACKUP_TO_ORIGINAL)
        rsync \
        -avuq \
        --delete \
        "$BACKUP_SYSTEM_PATH/" "$ORIGINAL_SYSTEM_PATH"
    ;;
    esac
}

finish() {
    ! isCacheMounted && exit
    
    syncFrom $ORIGINAL_TO_BACKUP
    say "Flushed cache to disk" $?
    # Wait until mount point is busy to prevent errors
    while lsof $ORIGINAL_SYSTEM_PATH &>/dev/null; do
        : # busy-wait
    done
    iSudo umount $ORIGINAL_SYSTEM_PATH
    say "Unmounted cache directory from RAM" $?
    say "Terminated successfully!"
}

sendError() {
    if [ "$EXECUTED_IN" = "gui" ]; then
        notificator "Something goes wrong! Check logs in '$STDERR_FILE'"
    fi
}

# Permit only one instance
curScript="$(basename "$0")";
running=$(ps h -C "$curScript" | grep -wv $$ | wc -l);
if [ "$running" -gt 1 ]; then
    zenity \
    --error \
    --ellipsize \
    --timeout=20 \
    --title="Oops!" \
    --text="It seems like phpStorm is already running...\nIn case, if it is not, kill manually the instance of this script" \
    &>/dev/null
    exit
fi

# Handle exits
trap 'finish' 0 1 2 3 6

readonly PHPSTORM_SH_PATH=$(readlink -f $PHPSTORM_SH_PATH)
readonly PHPSTORM_CACHE_PATH=$(readlink -f $PHPSTORM_CACHE_PATH)
readonly ORIGINAL_SYSTEM_PATH="$PHPSTORM_CACHE_PATH/system"
readonly BACKUP_SYSTEM_PATH="$PHPSTORM_CACHE_PATH/system_backup"

# States
readonly ORIGINAL_TO_BACKUP=1
readonly BACKUP_TO_ORIGINAL=2
readonly CANCEL_PRESSED=1
readonly TIMEOUT_EXCEEDED=5
[ -t 1 ] && readonly EXECUTED_IN="terminal" || readonly EXECUTED_IN="gui"

# Rewire all errors for GUI
if [ "$EXECUTED_IN" = "gui" ]; then
    readonly STDERR_FILE="$PHPSTORM_CACHE_PATH/ICache-logs.log"
    truncate -s 0 "$STDERR_FILE"
    exec 2> "$STDERR_FILE"
fi

# Start
main "$@"
