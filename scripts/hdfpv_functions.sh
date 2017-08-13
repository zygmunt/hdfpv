#!/bin/bash
# Original file: /root/.profile comes from: EZ-Wifibroadcast-1.5
# Modified by https://github.com/zygmunt
# Here are only functions

if [ -z HDFPV_SET_FLAG ]; then
    echo "Flag HDFPV_SET_FLAG is not set, look like file: hdfpv_settings.sh is not included"
    exit 1
fi

function tmessage {
    if [ "$QUIET" == "N" ]; then
        echo $1 "$2"
    fi
}

function load_modules {
    modprobe ath9k_htc
}

function create_fifo_files {
    for fifo in ${HDFPV_FIFO_FILES[@]}; do
        if [ -p ${fifo} ]; then
            continue
        elif [ -e ${fifo} ]; then
            rm ${fifo}
        fi
        mkfifo ${fifo}
    done
}

function collect_debug {
    ERR_LOG="/boot/errorlog.txt"
    ERR_PNG="/boot/errorlog.png"

    sleep 3
    echo
    nice mount -o remount,rw /boot
    mv ${ERR_LOG}{,.old} > /dev/null 2>&1
    mv ${ERR_PNG}{,.old} > /dev/null 2>&1
    echo -n "Camera: "
    nice vcgencmd get_camera
    uptime >> ${ERR_LOG}
    echo >> ${ERR_LOG}
    echo -n "Camera: " >> ${ERR_LOG}
    nice vcgencmd get_camera >> ${ERR_LOG}
    echo
    nice dmesg | nice grep disconnect
    nice dmesg | nice grep over-current
    nice dmesg | nice grep disconnect >> ${ERR_LOG}
    nice dmesg | nice grep over-current >> ${ERR_LOG}
    echo >> ${ERR_LOG}
    echo

    NICS=`ls /sys/class/net/ | nice grep -v eth0 | nice grep -v lo | nice grep -v usb`

    for NIC in $NICS; do
        iwconfig $NIC | grep $NIC
    done

    echo
    lsusb

    nice iwconfig >> ${ERR_LOG} > /dev/null 2>&1
    echo >> ${ERR_LOG}
    nice ifconfig >> ${ERR_LOG}
    echo >> ${ERR_LOG}

    nice iw list >> ${ERR_LOG}
    echo >> ${ERR_LOG}

    nice ps ax >> ${ERR_LOG}
    echo >> ${ERR_LOG}

    nice df -h >> ${ERR_LOG}
    echo >> ${ERR_LOG}

    nice mount >> ${ERR_LOG}
    echo >> ${ERR_LOG}

    nice fdisk -l /dev/mmcblk0 >> ${ERR_LOG}
    echo >> ${ERR_LOG}

    nice lsmod >> ${ERR_LOG}
    echo >> ${ERR_LOG}

    nice lsusb >> ${ERR_LOG}
    echo >> ${ERR_LOG}

    echo
    nice vcgencmd measure_temp
    nice vcgencmd get_throttled
    echo >> ${ERR_LOG}
    nice vcgencmd measure_temp >> ${ERR_LOG}
    nice vcgencmd get_throttled >> ${ERR_LOG}
    echo >> ${ERR_LOG}
    nice vcgencmd get_config int >> ${ERR_LOG}

    nice ${HDFPV_RASPI2PNG} -p ${ERR_PNG}
    echo >> ${ERR_LOG}
    nice dmesg >> ${ERR_LOG}
    echo >> ${ERR_LOG}
    echo >> ${ERR_LOG}

    nice cat /etc/modprobe.d/rt2800usb.conf >> ${ERR_LOG}
    nice cat /etc/modprobe.d/ath9k_htc.conf >> ${ERR_LOG}

    echo >> ${ERR_LOG}
    echo >> ${ERR_LOG}
    nice cat ${WIFIBROADCAST_CONF} | egrep -v "^(#|$)" >> ${ERR_LOG}
    echo >> ${ERR_LOG}
    echo >> ${ERR_LOG}
    nice cat ${OSD_CONF} | egrep -v "^(//|$)" >> ${ERR_LOG}
    echo >> ${ERR_LOG}
    echo >> ${ERR_LOG}
    nice cat /boot/joyconfig.txt | egrep -v "^(//|$)" >> ${ERR_LOG}
    echo >> ${ERR_LOG}
    echo >> ${ERR_LOG}
    nice cat /boot/apconfig.txt | egrep -v "^(#|$)" >> ${ERR_LOG}

    sync
    nice mount -o remount,ro /boot
}


function prepare_nic {
    DRIVER=`cat /sys/class/net/$1/device/uevent | nice grep DRIVER | sed 's/DRIVER=//'`
    tmessage -n "Setting up $1: "
    if [ "$DRIVER" == "ath9k_htc" ]; then # set bitrates for Atheros via iw
        tmessage -n "Bringing up.. "
        ifconfig $1 up || {
            echo
            echo "ERROR: Bringing up interface $1 failed!"
            collect_debug
            sleep 365d
        }
        sleep 0.2
        tmessage -n "done. "

        tmessage -n "bitrate "
        if [ "$CAM" == "0" ]; then # we are RX, set bitrate to uplink bitrate
            tmessage -n "$UPLINK_WIFI_BITRATE Mbit "
            iw dev $1 set bitrates legacy-2.4 $UPLINK_WIFI_BITRATE || {
                echo
                echo "ERROR: Setting bitrate on $1 failed!"
                collect_debug
                sleep 365d
            }
        else # we are TX, set bitrate to downstream bitrate
            tmessage -n "$VIDEO_WIFI_BITRATE Mbit "
            iw dev $1 set bitrates legacy-2.4 $VIDEO_WIFI_BITRATE || {
                echo
                echo "ERROR: Setting bitrate on $1 failed!"
                collect_debug
                sleep 365d
            }

        fi
        sleep 0.2
        tmessage -n "done. "

        tmessage -n "down.. "
        ifconfig $1 down || {
            echo
            echo "ERROR: Bringing down interface $1 failed!"
            collect_debug
            sleep 365d
        }
        sleep 0.2
        tmessage -n "done. "
    fi

# doesnt work, local variable ...
#    VIDEO_FRAMETYPE=1 # set video frametype to 1 (data) for non-Atheros, CTS generation is not supported anyway
#    TELEMETRY_FRAMETYPE=1 # set telemetry frametype to 1 (data) for non-Atheros, CTS generation is not supported anyway
#    fi

    tmessage -n "monitor mode.. "
    iw dev $1 set monitor none || {
        echo
        echo "ERROR: Setting monitor mode on $1 failed!"
        collect_debug
        sleep 365d
    }
    sleep 0.2
    tmessage -n "done. "

    tmessage -n "bringing up.. "
    ifconfig $1 up || {
        echo
        echo "ERROR: Bringing up interface $1 failed!"
        collect_debug
        sleep 365d
    }
    sleep 0.2
    tmessage -n "done. "

    if [ "$2" != "0" ]; then
        tmessage -n "frequency $2 MHz.. "
        iw dev $1 set freq $2 || {
            echo
            echo "ERROR: Setting frequency $2 MHz on $1 failed!"
            collect_debug
            sleep 365d
        }
        tmessage "done!"
    else
        echo
    fi
}


function detect_nics {
    tmessage "Setting up wifi cards ... "
    echo

    iw reg set DE

    NUM_CARDS=-1
    NICSWL=`ls /sys/class/net | nice grep wlan`

    for NIC in $NICSWL; do
        # re-name wifi interface to MAC address
        NAME=`cat /sys/class/net/$NIC/address`
        ip link set $NIC name ${NAME//:}
        let "NUM_CARDS++"
        #sleep 0.1
    done

    if [ "$NUM_CARDS" == "-1" ]; then
        echo "ERROR: No wifi cards detected"
        collect_debug
        sleep 365d
    fi

    if [ "$CAM" == "0" ]; then
        # only do relay/hotspot stuff if RX
        # get wifi hotspot card out of the way
        if [ "$WIFI_HOTSPOT" == "Y" ]; then
            if [ "$WIFI_HOTSPOT_NIC" != "internal" ]; then
                # only configure it if it's there
                if ls /sys/class/net/ | grep -q $WIFI_HOTSPOT_NIC; then
                    tmessage -n "Setting up $WIFI_HOTSPOT_NIC for Wifi Hotspot operation.."
                    ip link set $WIFI_HOTSPOT_NIC name wifihotspot0
                    ifconfig wifihotspot0 192.168.2.1 up
                    tmessage "done!"
                    let "NUM_CARDS--"
                else
                    tmessage "Wifi Hotspot card $WIFI_HOTSPOT_NIC not found!"
                    sleep 0.5
                fi
            else
                # only configure it if it's there
                if ls /sys/class/net/ | grep -q intwifi0; then
                    tmessage -n "Setting up intwifi0 for Wifi Hotspot operation.."
                    ip link set intwifi0 name wifihotspot0
                    ifconfig wifihotspot0 192.168.2.1 up
                    tmessage "done!"
                else
                    tmessage "Pi3 Onboard Wifi Hotspot card not found!"
                    sleep 0.5
                fi
            fi
        fi
        # get relay card out of the way
        if [ "$RELAY" == "Y" ]; then
            # only configure it if it's there
            if ls /sys/class/net/ | grep -q $RELAY_NIC; then
                ip link set $RELAY_NIC name relay0
                prepare_nic relay0 $RELAY_FREQ
                let "NUM_CARDS--"
            else
                tmessage "Relay card $RELAY_NIC not found!"
                sleep 0.5
            fi
        fi
    fi

    NICS=`ls /sys/class/net/ | nice grep -v eth0 | nice grep -v lo | nice grep -v usb | nice grep -v intwifi | nice grep -v relay | nice grep -v wifihotspot`
    echo "NICS: $NICS"

    if [ "$TXMODE" != "single" ]; then
        for i in $(eval echo {0..$NUM_CARDS}); do
            if [ "$CAM" == "0" ]; then
                prepare_nic ${MAC_RX[$i]} ${FREQ_RX[$i]}
            else
                prepare_nic ${MAC_TX[$i]} ${FREQ_TX[$i]}
            fi
        sleep 0.1
        done
    else
        # check if auto scan is enabled, if yes, set freq to 0 to let prepare_nic know not to set channel
        if [ "$FREQSCAN" == "Y" ] && [ "$CAM" == "0" ]; then
            for NIC in $NICS; do
                prepare_nic $NIC 2484
                sleep 0.1
            done
            # make sure check_alive function doesnt restart hello_video while we are still scanning for channel
            touch /tmp/pausewhile
            ${HDFPV_RX} -p 0 -d 1 -t 6 -b $VIDEO_BLOCKS -r $VIDEO_FECS -f $VIDEOBLOCKLENGTH $NICS >/dev/null &
            sleep 0.5
            echo
            echo -n "Please wait, scanning for TX ..."
            FREQ=0

            if iw list | nice grep -q 5180; then # cards support 5G and 2.4G
                FREQCMD="${HDFPV_CHANNELSCAN} 245 $NICS"
            else
                if iw list | nice grep -q 2312; then # cards support 2.3G and 2.4G
                    FREQCMD="${HDFPV_CHANNELSCAN} 2324 $NICS"
                else # cards support only 2.4G
                    FREQCMD="${HDFPV_CHANNELSCAN} 24 $NICS"
                fi
            fi

            while [ $FREQ -eq 0 ]; do
                FREQ=`$FREQCMD`
            done

            echo "found on $FREQ MHz"
            echo
            ps -ef | nice grep "rx -p 0" | nice grep -v grep | awk '{print $2}' | xargs kill -9
            for NIC in $NICS; do
                echo -n "Setting frequency on $NIC to $FREQ MHz.. "
                iw dev $NIC set freq $FREQ
                echo "done."
                sleep 0.1
            done
            # all done
            rm /tmp/pausewhile
        else
            for NIC in $NICS; do
                prepare_nic $NIC $FREQ
                sleep 0.1
            done
        fi
    fi
}


function check_health_function {
    # not used, somehow calling vgencmd seems to cause badblocks

    # check if over-temperature or under-voltage occured
    if nice vcgencmd get_throttled | nice nice grep -q -v "0x0"; then
        TEMP=`nice vcgencmd measure_temp | cut -f 2 -d "="`
        echo "ERROR: Over-Temperature or unstable power supply! Current temp:$TEMP"
        collect_debug
        ps -ef | nice grep "osd" | nice grep -v grep | awk '{print $2}' | xargs kill -9
        ps -ef | nice grep "cat ${HDFPV_TELEMETRY_FIFO_1}" | nice grep -v grep | awk '{print $2}' | xargs kill -9
        while true; do
            killall wbc_status > /dev/null 2>&1
            nice ${HDFPV_WBC_STATUS} "ERROR: Undervoltage or Overtemp, current temp: $TEMP" 7 55 0
            sleep 6
        done
    fi
}


function check_alive_function {
    # function to check if packets coming in, if not, re-start hello_video to clear frozen display
    while true; do
        # pause while saving is in progress
        pause_while
        ALIVE=`nice ${HDFPV_CHECK_ALIVE}`
        if [ $ALIVE == "0" ]; then
            echo "no new packets, restarting hello_video and sleeping for 5s ..."
            ps -ef | nice grep "cat ${HDFPV_VIDEO_FIFO_1}" | nice grep -v grep | awk '{print $2}' | xargs kill -9
            ps -ef | nice grep "$DISPLAY_PROGRAM" | nice grep -v grep | awk '{print $2}' | xargs kill -9
            ionice -c 1 -n 4 nice -n -10 cat ${HDFPV_VIDEO_FIFO_1} | ionice -c 1 -n 4 nice -n -10 $DISPLAY_PROGRAM > /dev/null 2>&1 &
            sleep 5
        else
            echo "received packets, doing nothing ..."
        fi
    done
}


function check_exitstatus {
    STATUS=$1
    case $STATUS in
    9)
    # rx returned with exit code 9 = the interface went down
    # wifi card must've been removed during running
    # check if wifi card is really gone
    NICS2=`ls /sys/class/net/ | nice grep -v eth0 | nice grep -v lo | nice grep -v usb | nice grep -v intwifi | nice grep -v relay | nice grep -v wifihotspot`
    if [ "$NICS" == "$NICS2" ]; then
        # wifi card has not been removed, something else must've gone wrong
        echo "ERROR: RX stopped, wifi card _not_ removed!             "
    else
        # wifi card has been removed
        echo "ERROR: Wifi card removed!                               "
    fi
    ;;
    2)
    # something else that is fatal happened during running
    echo "ERROR: RX chain stopped wifi card _not_ removed!             "
    ;;
    1)
    # something that is fatal went wrong at rx startup
    echo "ERROR: could not start RX                           "
    #echo "ERROR: could not start RX                           "
    ;;
    *)
    if [  $RX_EXITSTATUS -lt 128 ]; then
        # whatever it was ...
        echo "RX exited with status: $RX_EXITSTATUS                        "
    fi
    esac
}


function tx_function {
    if [ "$TXMODE" == "single" ]; then
        echo -n "Waiting for wifi card to become ready ..."
        COUNTER=0
        # loop until card is initialized
        while [ $COUNTER -lt 10 ]; do
            sleep 0.5
            echo -n "."
            let "COUNTER++"
            if [ -d "/sys/class/net/wlan0" ]; then
                echo -n "card ready"
                break
            fi
        done
    else
        # just wait some time
        echo -n "Waiting for wifi cards to become ready ..."
        sleep 3
    fi

    echo
    echo
    detect_nics

    sleep 1
    echo

    DRIVER=`cat /sys/class/net/$NICS/device/uevent | nice grep DRIVER | sed 's/DRIVER=//'`
    if [ "$DRIVER" != "ath9k_htc" ]; then #
        VIDEO_FRAMETYPE=1
    fi

    echo "video frametype: $VIDEO_FRAMETYPE"


    # check if over-temperature or under-voltage occured
    if vcgencmd get_throttled | nice grep -q -v "0x0"; then
        TEMP=`nice vcgencmd measure_temp | cut -f 2 -d "="`
        echo "ERROR: Over-Temperature or unstable power supply! Temp:$TEMP"
        collect_debug
        nice -n -9 raspivid -w $WIDTH -h $HEIGHT -fps $FPS -b 3000000 -g $KEYFRAMERATE -t 0 \
            $EXTRAPARAMS -ae 40,0x00,0x8080FF -a "\n\nunder-voltage or over-temperature on TX!" -o - | \
            nice -n -9 ${HDFPV_TX} -p 0 -b $VIDEO_BLOCKS -r $VIDEO_FECS -f $VIDEO_BLOCKLENGTH -t $VIDEO_FRAMETYPE -d $VIDEO_WIFI_BITRATE -y 0 $NICS
        sleep 365d
    fi

    # check for potential power-supply problems
    if nice dmesg | nice grep -q over-current; then
        echo "ERROR: Over-current detected - potential power supply problems!"
        collect_debug
        sleep 365d
    fi

    # check for USB disconnects (due to power-supply problems)
    if nice dmesg | nice grep -q disconnect; then
        echo "ERROR: USB disconnect detected - potential power supply problems!"
        collect_debug
        sleep 365d
    fi

    echo "Starting transmission in $TXMODE mode: $WIDTH x $HEIGHT $FPS fps, Bitrate: $BITRATE Bit/s, Keyframerate: $KEYFRAMERATE, Wifi Bitrate: $VIDEO_WIFI_BITRATE"
    nice -n -9 raspivid -w $WIDTH -h $HEIGHT -fps $FPS -b $BITRATE -g $KEYFRAMERATE -t 0 $EXTRAPARAMS $ANNOTATION -o - | \
        nice -n -9 ${HDFPV_TX} -p 0 -b $VIDEO_BLOCKS -r $VIDEO_FECS -f $VIDEO_BLOCKLENGTH -t $VIDEO_FRAMETYPE -d $VIDEO_WIFI_BITRATE -y 0 $NICS
    TX_EXITSTATUS=${PIPESTATUS[1]}
    # if we arrive here, either raspivid or tx did not start, or were terminated later
    # check if NIC has been removed
    NICS2=`ls /sys/class/net/ | nice grep -v eth0 | nice grep -v lo | nice grep -v usb | nice grep -v intwifi | nice grep -v relay | nice grep -v wifihotspot`
    if [ "$NICS" == "$NICS2" ]; then
        # wifi card has not been removed
        if [ "$TX_EXITSTATUS" != "0" ]; then
            echo "ERROR: could not start tx or tx terminated!"
        fi
        collect_debug
        sleep 365d
    else
        # wifi card has been removed
        echo "ERROR: Wifi card removed!"
        collect_debug
        sleep 365d
    fi
}



function rx_function {
    # start virtual serial port for cmavnode
    ionice -c 3 nice socat -d -d pty,raw,echo=0 pty,raw,echo=0 & > /dev/null 2>&1

    # wait some time so that wifi cards are ready
    sleep 1
    echo

    # if USB memory stick is already connected during startup, notify user
    # and pause as long as stick is not removed
    # some sticks show up as sda1, others as sda, check for both
    if [ -e "/dev/sda1" ]; then
        STARTUSBDEV="/dev/sda1"
    else
        STARTUSBDEV="/dev/sda"
    fi

    if [ -e $STARTUSBDEV ]; then
        touch /tmp/donotsave
        STICKGONE=0
        while [ $STICKGONE -ne 1 ]; do
            killall wbc_status > /dev/null 2>&1
            nice ${HDFPV_WBC_STATUS} "USB memory stick detected - please remove and re-plug after flight" 7 65 0 &
            sleep 4
            if [ ! -e $STARTUSBDEV ]; then
                STICKGONE=1
                rm /tmp/donotsave
            fi
        done
    fi

    # kill wbc_status (the ez-wifibroadcast splash screen) only if verbose
    if [ "$QUIET" == "N" ]; then
        killall wbc_status > /dev/null 2>&1
    fi

    detect_nics
    echo

    sleep 0.5

    # videofifo1: local display, hello_video.bin
    # videofifo2: secondary display, hotspot/usb-tethering
    # videofifo3: recording
    # videofifo4: wbc relay

    if [ "$VIDEO_TMP" == "sdcard" ]; then
        tmessage "Saving to SDCARD enabled, preparing video storage ..."
        if cat /proc/partitions | nice grep -q mmcblk0p3; then # partition has not been created yet
            echo
        else
            echo
            echo -e "n\np\n3\n3674112\n\nw" | fdisk /dev/mmcblk0 > /dev/null 2>&1
            partprobe > /dev/null 2>&1
            mkfs.ext4 /dev/mmcblk0p3 -F > /dev/null 2>&1 || {
            tmessage "ERROR: Could not format video storage on SDCARD!"
            collect_debug
            sleep 365d
            }
        fi
        e2fsck -p /dev/mmcblk0p3 > /dev/null 2>&1
        mount -t ext4 -o noatime /dev/mmcblk0p3 /video_tmp > /dev/null 2>&1 || {
            tmessage "ERROR: Could not mount video storage on SDCARD!"
            collect_debug
            sleep 365d
        }
        VIDEOFILE=/video_tmp/videotmp.raw
        echo "VIDEOFILE=/video_tmp/videotmp.raw" > /tmp/videofile
        rm $VIDEOFILE > /dev/null 2>&1
    else
        VIDEOFILE=/wbc_tmp/videotmp.raw
        echo "VIDEOFILE=/wbc_tmp/videotmp.raw" > /tmp/videofile
    fi

    #${HDFPV_TRACKER} /wifibroadcast_rx_status_0 >> /wbc_tmp/tracker.txt &
    #sleep 1

    killall wbc_status > /dev/null 2>&1

    while true; do
    ionice -c 1 -n 4 nice -n -10 cat ${HDFPV_VIDEO_FIFO_1} | ionice -c 1 -n 4 nice -n -10 $DISPLAY_PROGRAM > /dev/null 2>&1 &
    ionice -c 3 nice cat ${HDFPV_VIDEO_FIFO_3} >> $VIDEOFILE &

    if [ "$RELAY" == "Y" ]; then
        ionice -c 1 -n 4 nice -n -10 cat ${HDFPV_VIDEO_FIFO_4} | ${HDFPV_TX} -p 0 -b $RELAY_VIDEO_BLOCKS -r $RELAY_VIDEO_FECS -f $RELAY_VIDEO_BLOCKLENGTH -t $VIDEO_FRAMETYPE -d $VIDEO_WIFI_BITRATE -y 0 relay0 > /dev/null 2>&1 &
    fi

    # update NICS variable in case a NIC has been removed (exclude devices with wlanx)
    NICS=`ls /sys/class/net/ | nice grep -v eth0 | nice grep -v lo | nice grep -v usb | nice grep -v intwifi | nice grep -v wlan | nice grep -v relay | nice grep -v wifihotspot`
    tmessage "Starting RX ... (FEC: $VIDEO_BLOCKS/$VIDEO_FECS/$VIDEO_BLOCKLENGTH)"
    ionice -c 1 -n 3 ${HDFPV_RX} -p 0 -t 6 -d 2 -b $VIDEO_BLOCKS -r $VIDEO_FECS -f $VIDEO_BLOCKLENGTH $NICS \
        | ionice -c 1 -n 4 nice -n -10 tee >(ionice -c 1 -n 4 nice -n -10 ${HDFPV_FTEE} ${HDFPV_VIDEO_FIFO_2} > /dev/null 2>&1) \
                                           >(ionice -c 1 nice -n -10 ${HDFPV_FTEE} ${HDFPV_VIDEO_FIFO_4} > /dev/null 2>&1) \
                                           >(ionice -c 3 nice ${HDFPV_FTEE} ${HDFPV_VIDEO_FIFO_3} > /dev/null 2>&1) \
                                           | ionice -c 1 -n 4 nice -n -10 ${HDFPV_FTEE} ${HDFPV_VIDEO_FIFO_1} > /dev/null 2>&1
    RX_EXITSTATUS=${PIPESTATUS[0]}
    check_exitstatus $RX_EXITSTATUS
    ps -ef | nice grep "$DISPLAY_PROGRAM" | nice grep -v grep | awk '{print $2}' | xargs kill -9
    ps -ef | nice grep "rx -p 0" | nice grep -v grep | awk '{print $2}' | xargs kill -9
    ps -ef | nice grep "ftee ${HDFPV_VIDEO_FIFO}" | nice grep -v grep | awk '{print $2}' | xargs kill -9
    ps -ef | nice grep "cat ${HDFPV_VIDEO_FIFO}" | nice grep -v grep | awk '{print $2}' | xargs kill -9
    done
}





