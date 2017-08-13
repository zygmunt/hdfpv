#!/bin/bash
# Original file: /root/.profile comes from: EZ-Wifibroadcast-1.5
# Modified by https://github.com/zygmunt
# Here are only functions

if [ -z HDFPV_SET_FLAG ]; then
    echo "Flag HDFPV_SET_FLAG is not set, look like file: hdfpv_settings.sh is not included"
    exit 1
fi


## runs on RX (ground pi)
function osdrx_function {
    echo
    # Convert osdconfig from DOS format to UNIX format
    ionice -c 3 nice dos2unix -n /boot/osdconfig.txt /tmp/osdconfig.txt
    echo
    cd ${HDFPV_DIR}_osd
    echo Building OSD:
    ionice -c 3 nice make -j2 || {
        echo
        echo "ERROR: Could not build OSD, check osdconfig.txt!"
    }
    echo
    echo -n "Waiting until video is running ..."
    VIDEORXRUNNING=0
    while [ $VIDEORXRUNNING -ne 1 ]; do
    sleep 0.1
    VIDEORXRUNNING=`pidof $DISPLAY_PROGRAM | wc -w`
    echo -n "."
    done
    echo
    echo "Video running, starting OSD processes ..."

    if [ "$TELEMETRY_TRANSMISSION" == "wbc" ]; then
    TELEMETRY_RX_CMD="${HDFPV_RX} -p 1 -t 6 -d 2 -b $TELEMETRY_BLOCKS -r $TELEMETRY_FECS -f $TELEMETRY_BLOCKLENGTH"
    else
    nice stty -F $EXTERNAL_TELEMETRY_SERIALPORT_GROUND $EXTERNAL_TELEMETRY_SERIALPORT_GROUND_STTY_OPTIONS $EXTERNAL_TELEMETRY_SERIALPORT_GROUND_BAUDRATE
    TELEMETRY_RX_CMD="cat $EXTERNAL_TELEMETRY_SERIALPORT_GROUND"
    fi


    if [ "$ENABLE_SERIAL_TELEMETRY_OUTPUT" == "Y" ]; then
    echo "enable_serial_telemetry_output is Y, sending stream to $TELEMETRY_OUTPUT_SERIALPORT_GROUND"
    nice stty -F $TELEMETRY_OUTPUT_SERIALPORT_GROUND $TELEMETRY_OUTPUT_SERIALPORT_GROUND_STTY_OPTIONS $TELEMETRY_OUTPUT_SERIALPORT_GROUND_BAUDRATE
    nice cat ${HDFPV_TELEMETRY_FIFO_6} > $TELEMETRY_OUTPUT_SERIALPORT_GROUND &
    fi

    # telemetryfifo1: local display, osd
    # telemetryfifo2: secondary display, hotspot/usb-tethering
    # telemetryfifo3: recording
    # telemetryfifo4: wbc relay
    # telemetryfifo5: mavproxy downlink
    # telemetryfifo6: serial downlink

    killall wbc_status > /dev/null 2>&1
    ionice -c 3 nice cat ${HDFPV_TELEMETRY_FIFO_3} >> /wbc_tmp/telemetrytmp.raw &
    OSDRUNNING=`pidof /tmp/osd | wc -w`
    if [ $OSDRUNNING  -ge 1 ]; then
    echo "OSD already running!"
    else
    killall wbc_status > /dev/null 2>&1
    cat ${HDFPV_TELEMETRY_FIFO_1} | /tmp/osd >> /wbc_tmp/telemetrytmp.txt &
    fi

    while true; do
        if [ "$RELAY" == "Y" ]; then
            ionice -c 1 -n 4 nice -n -9 cat ${HDFPV_TELEMETRY_FIFO_4} | ${HDFPV_TX} -p 1 -b $RELAY_TELEMETRY_BLOCKS -r $RELAY_TELEMETRY_FECS -f $RELAY_TELEMETRY_BLOCKLENGTH -m $TELEMETRY_MIN_BLOCKLENGTH -t $TELEMETRY_FRAMETYPE -d $TELEMETRY_WIFI_BITRATE -y 0 relay0 > /dev/null 2>&1 &
        fi

        # update NICS variable in case a NIC has been removed (exclude devices with wlanx)
        NICS=`ls /sys/class/net/ | nice grep -v eth0 | nice grep -v lo | nice grep -v usb | nice grep -v intwifi | nice grep -v wlan | nice grep -v relay | nice grep -v wifihotspot`

        if [ "$TELEMETRY_TRANSMISSION" == "wbc" ]; then
            $TELEMETRY_RX_CMD $NICS | tee >(${HDFPV_FTEE} ${HDFPV_TELEMETRY_FIFO_2} > /dev/null 2>&1) \
                                          >(${HDFPV_FTEE} ${HDFPV_TELEMETRY_FIFO_3} > /dev/null 2>&1) \
                                          >(ionice -c 1 nice -n -9 ${HDFPV_FTEE} ${HDFPV_TELEMETRY_FIFO_4} > /dev/null 2>&1) \
                                          >(ionice nice ${HDFPV_FTEE} ${HDFPV_TELEMETRY_FIFO_5} > /dev/null 2>&1) \
                                          >(ionice nice ${HDFPV_FTEE} ${HDFPV_TELEMETRY_FIFO_6} > /dev/null 2>&1) \
                                          | ${HDFPV_FTEE} ${HDFPV_TELEMETRY_FIFO_1} > /dev/null 2>&1
        else
            $TELEMETRY_RX_CMD | tee >(${HDFPV_FTEE} ${HDFPV_TELEMETRY_FIFO_2} > /dev/null 2>&1) >(${HDFPV_FTEE} ${HDFPV_TELEMETRY_FIFO_3} > /dev/null 2>&1) >(ionice -c 1 nice -n -9 ${HDFPV_FTEE} ${HDFPV_TELEMETRY_FIFO_4} > /dev/null 2>&1) >(ionice nice ${HDFPV_FTEE} ${HDFPV_TELEMETRY_FIFO_5} > /dev/null 2>&1) >(ionice nice ${HDFPV_FTEE} ${HDFPV_TELEMETRY_FIFO_6} > /dev/null 2>&1) | ${HDFPV_FTEE} ${HDFPV_TELEMETRY_FIFO_1} > /dev/null 2>&1
        fi
        echo "ERROR: Telemetry RX has been stopped - restarting ..."
        ps -ef | nice grep "rx -p 1" | nice grep -v grep | awk '{print $2}' | xargs kill -9
        ps -ef | nice grep "ftee ${HDFPV_TELEMETRY_FIFO}" | nice grep -v grep | awk '{print $2}' | xargs kill -9
        sleep 1
    done
}

## runs on TX (air pi)
function osdtx_function {
    # setup serial port
    stty -F $FC_TELEMETRY_SERIALPORT $FC_TELEMETRY_STTY_OPTIONS $FC_TELEMETRY_BAUDRATE

    # wait until tx is running to make sure NICS are configured
    echo
    echo -n "Waiting until video TX is running ..."
    VIDEOTXRUNNING=0
    while [ $VIDEOTXRUNNING -ne 1 ]; do
    sleep 0.5
    VIDEOTXRUNNING=`pidof raspivid | wc -w`
    echo -n "."
    done
    echo

    echo "Video running, starting OSD processes ..."

    NICS=`ls /sys/class/net/ | nice grep -v eth0 | nice grep -v lo | nice grep -v usb | nice grep -v intwifi`

    DRIVER=`cat /sys/class/net/$NICS/device/uevent | nice grep DRIVER | sed 's/DRIVER=//'`
    if [ "$DRIVER" != "ath9k_htc" ]; then # set frametype to 1 for non-atheros fixed regardless of cts-protection mode
        TELEMETRY_FRAMETYPE=1
    fi

    echo "telemetry frametype: $TELEMETRY_FRAMETYPE"

    echo
    while true; do
        echo "Starting downlink telemetry transmission in $TXMODE mode (FEC: $TELEMETRY_BLOCKS/$TELEMETRY_FECS/$TELEMETRY_BLOCKLENGTH, FC Serialport: $FC_TELEMETRY_SERIALPORT)"
        nice cat $FC_TELEMETRY_SERIALPORT | nice ${HDFPV_TX} -p 1 -b $TELEMETRY_BLOCKS -r $TELEMETRY_FECS -f $TELEMETRY_BLOCKLENGTH -m $TELEMETRY_MIN_BLOCKLENGTH -t $TELEMETRY_FRAMETYPE -d $TELEMETRY_WIFI_BITRATE -y 0 $NICS
        ps -ef | nice grep "cat $FC_TELEMETRY_SERIALPORT" | nice grep -v grep | awk '{print $2}' | xargs kill -9
        ps -ef | nice grep "tx -p 1" | nice grep -v grep | awk '{print $2}' | xargs kill -9
    echo "Downlink Telemetry TX exited - restarting ..."
        sleep 1
    done
}




# runs on RX (ground pi)
function mspdownlinkrx_function {
    echo
    echo -n "Waiting until video is running ..."
    VIDEORXRUNNING=0
    while [ $VIDEORXRUNNING -ne 1 ]; do
    sleep 0.1
    VIDEORXRUNNING=`pidof $DISPLAY_PROGRAM | wc -w`
    echo -n "."
    done
    echo
    echo "Video running ..."

    while true; do
    #
    #if [ "$RELAY" == "Y" ]; then
    #    ionice -c 1 -n 4 nice -n -9 cat ${HDFPV_TELEMETRY_FIFO_4} | ${HDFPV_TX} -p 1 -b $RELAY_TELEMETRY_BLOCKS -r $RELAY_TELEMETRY_FECS -f $RELAY_TELEMETRY_BLOCKLENGTH -m $TELEMETRY_MIN_BLOCKLENGTH -y 0 relay0 > /dev/null 2>&1 &
    #fi
    # update NICS variable in case a NIC has been removed (exclude devices with wlanx)
    NICS=`ls /sys/class/net/ | nice grep -v eth0 | nice grep -v lo | nice grep -v usb | nice grep -v intwifi | nice grep -v wlan | nice grep -v relay | nice grep -v wifihotspot`
    nice ${HDFPV_RX} -p 4 -t 6 -d 2 -b $TELEMETRY_BLOCKS -r $TELEMETRY_FECS -f $TELEMETRY_BLOCKLENGTH $NICS | ionice nice ${HDFPV_FTEE} ${HDFPV_MSP_FIFO} > /dev/null 2>&1
    echo "ERROR: MSP RX has been stopped - restarting ..."
    ps -ef | nice grep "rx -p 4" | nice grep -v grep | awk '{print $2}' | xargs kill -9
    ps -ef | nice grep "ftee ${HDFPV_MSP_FIFO}" | nice grep -v grep | awk '{print $2}' | xargs kill -9
    sleep 1
    done
}


## runs on TX (air pi)
function mspdownlinktx_function {
    # setup serial port
    stty -F $FC_MSP_SERIALPORT -imaxbel -opost -isig -icanon -echo -echoe -ixoff -ixon $FC_MSP_BAUDRATE

    # wait until tx is running to make sure NICS are configured
    echo
    echo -n "Waiting until video TX is running ..."
    VIDEOTXRUNNING=0
    while [ $VIDEOTXRUNNING -ne 1 ]; do
    sleep 0.5
    VIDEOTXRUNNING=`pidof raspivid | wc -w`
    echo -n "."
    done
    echo

    echo "Video running, starting MSP processes ..."

    NICS=`ls /sys/class/net/ | nice grep -v eth0 | nice grep -v lo | nice grep -v usb | nice grep -v intwifi`

    echo
    while true; do
        echo "Starting MSP transmission in $TXMODE mode (FEC: $TELEMETRY_BLOCKS/$TELEMETRY_FECS/$TELEMETRY_BLOCKLENGTH, FC MSP Serialport: $FC_MSP_SERIALPORT)"
        nice cat $FC_MSP_SERIALPORT | nice ${HDFPV_TX} -p 4 -b $TELEMETRY_BLOCKS -r $TELEMETRY_FECS -f $TELEMETRY_BLOCKLENGTH -m $TELEMETRY_MIN_BLOCKLENGTH -t $TELEMETRY_FRAMETYPE -d $TELEMETRY_WIFI_BITRATE -y 0 $NICS
        ps -ef | nice grep "cat $FC_MSP_SERIALPORT" | nice grep -v grep | awk '{print $2}' | xargs kill -9
        ps -ef | nice grep "tx -p 1" | nice grep -v grep | awk '{print $2}' | xargs kill -9
    echo "MSP telemetry TX exited - restarting ..."
        sleep 1
    done
}



## runs on RX (ground pi)
function uplinktx_function {
    # wait until video is running to make sure NICS are configured
    echo
    echo -n "Waiting until video is running ..."
    VIDEORXRUNNING=0
    while [ $VIDEORXRUNNING -ne 1 ]; do
    VIDEORXRUNNING=`pidof $DISPLAY_PROGRAM | wc -w`
    sleep 1
    echo -n "."
    done
    sleep 1
    echo
    echo

    if [ "$TELEMETRY_TRANSMISSION" == "wbc" ]; then # if we use wbc for transmission, set tx command to use wbc TX
    NICS=`ls /sys/class/net/ | nice grep -v eth0 | nice grep -v lo | nice grep -v usb | nice grep -v intwifi | nice grep -v relay | nice grep -v wifihotspot`
    echo -n "NICS:"
    echo $NICS
    UPLINK_TX_CMD="nice ${HDFPV_TX} -p 3 -b $TELEMETRY_BLOCKS -r $TELEMETRY_FECS -f $TELEMETRY_BLOCKLENGTH -m $TELEMETRY_MIN_BLOCKLENGTH -t $TELEMETRY_FRAMETYPE -d $UPLINK_WIFI_BITRATE -y 1 $NICS"
    else # else setup serial port and use cat
    nice stty -F $EXTERNAL_TELEMETRY_SERIALPORT_GROUND $EXTERNAL_TELEMETRY_SERIALPORT_GROUND_STTY_OPTIONS $EXTERNAL_TELEMETRY_SERIALPORT_GROUND_BAUDRATE
    UPLINK_TX_CMD="nice cat $EXTERNAL_TELEMETRY_SERIALPORT_GROUND"
    fi

    VSERIALPORT=/dev/pts/0

    while true; do
        echo "Starting uplink telemetry transmission (FEC: $TELEMETRY_BLOCKS/$TELEMETRY_FECS/$TELEMETRY_BLOCKLENGTH)"
        nice cat $VSERIALPORT | $UPLINK_TX_CMD
        ps -ef | nice grep "cat $EXTERNAL_TELEMETRY_SERIALPORT_GROUND" | nice grep -v grep | awk '{print $2}' | xargs kill -9
        ps -ef | nice grep "cat $TELEMETRY_OUTPUT_SERIALPORT_GROUND" | nice grep -v grep | awk '{print $2}' | xargs kill -9
        ps -ef | nice grep "cat $VSERIALPORT" | nice grep -v grep | awk '{print $2}' | xargs kill -9
        ps -ef | nice grep "tx -p 3" | nice grep -v grep | awk '{print $2}' | xargs kill -9
    done
}


## runs on TX (air pi)
function uplinkrx_function {
    echo "FC_TELEMETRY_SERIALPORT: $FC_TELEMETRY_SERIALPORT"
    echo "FC_MSP_SERIALPORT: $FC_MSP_SERIALPORT"

    # wait until tx is running to make sure NICS are configured
    echo
    echo -n "Waiting until video TX is running ..."
    VIDEOTXRUNNING=0
    while [ $VIDEOTXRUNNING -ne 1 ]; do
    VIDEOTXRUNNING=`pidof raspivid | wc -w`
    sleep 1
    echo -n "."
    done
    echo

    NICS=`ls /sys/class/net/ | nice grep -v eth0 | nice grep -v lo | nice grep -v usb | nice grep -v intwifi | nice grep -v relay | nice grep -v wifihotspot`
    echo -n "NICS:"
    echo $NICS
    echo

    stty -F $FC_TELEMETRY_SERIALPORT $FC_TELEMETRY_STTY_OPTIONS $FC_TELEMETRY_BAUDRATE
    #sleep 2

    echo "Starting Uplink telemetry RX (FEC: $TELEMETRY_BLOCKS/$TELEMETRY_FECS/$TELEMETRY_BLOCKLENGTH)"
    if [ "$TELEMETRY_UPLINK" == "mavlink" ]; then
    nice ${HDFPV_RX} -p 3 -t 6 -d 2 -b $TELEMETRY_BLOCKS -r $TELEMETRY_FECS -f $TELEMETRY_BLOCKLENGTH $NICS > $FC_TELEMETRY_SERIALPORT
    else # msp
    nice ${HDFPV_RX} -p 3 -t 6 -d 2 -b $TELEMETRY_BLOCKS -r $TELEMETRY_FECS -f $TELEMETRY_BLOCKLENGTH $NICS > $FC_MSP_SERIALPORT
    fi
}


function rctx_function {
    # Convert joystick config from DOS format to UNIX format
    ionice -c 3 nice dos2unix -n /boot/joyconfig.txt /tmp/rctx.h > /dev/null 2>&1
    echo
    echo Building RC ...
    cd ${HDFPV_DIR}_rc
    ionice -c 3 nice gcc -lrt -lpcap rctx.c -o /tmp/rctx `sdl-config --libs` `sdl-config --cflags` || {
    echo "ERROR: Could not build RC, check joyconfig.txt!"
    }
    # wait until video is running to make sure NICS are configured and wifibroadcast_rx_status shmem is available
    echo
    echo -n "Waiting until video is running ..."
    VIDEORXRUNNING=0
    while [ $VIDEORXRUNNING -ne 1 ]; do
    VIDEORXRUNNING=`pidof $DISPLAY_PROGRAM | wc -w`
    sleep 1
        echo -n "."
    done
    echo

    NICS=`ls /sys/class/net/ | nice grep -v eth0 | nice grep -v lo | nice grep -v usb | nice grep -v intwifi | nice grep -v relay | nice grep -v wifihotspot`
    echo -n "NICS:"
    echo $NICS

    echo
    echo
    echo "Starting R/C RSSI RX ..."
    nice ${HDFPV_RSSIRX} $NICS &

    echo "Starting R/C TX ..."
    while true; do
        nice -n -5 /tmp/rctx $NICS
    done
}

# runs on TX (air pi)
function rcrx_function {
    echo "FC_RC_SERIALPORT: $FC_RC_SERIALPORT"
    # wait until tx is running to make sure NICS are configured
    echo
    echo -n "Waiting until video TX is running ..."
    VIDEOTXRUNNING=0
    while [ $VIDEOTXRUNNING -ne 1 ]; do
        VIDEOTXRUNNING=`pidof raspivid | wc -w`
        sleep 1
        echo -n "."
    done
    echo

    NICS=`ls /sys/class/net/ | nice grep -v eth0 | nice grep -v lo | nice grep -v usb | nice grep -v intwifi | nice grep -v relay | nice grep -v wifihotspot`
    echo -n "NICS:"
    echo $NICS
    echo

    # TODO: make sure only Atheros cards are used for rc RX
    echo "Starting R/C RX ..."

    nice -n -9 ${HDFPV_RCRX} -s $FC_RC_SERIALPORT -b $FC_RC_BAUDRATE $NICS &
    nice ${HDFPV_RSSITX} $NICS

}


function screenshot_function {
    while true; do
        # pause loop while saving is in progress
        pause_while
        SCALIVE=`nice ${HDFPV_CHECK_ALIVE}`
        # do nothing if no video being received (so we don't take unnecessary screeshots)
        if [ "$SCALIVE" == "1" ]; then
            FREETMPSPACE=`df -BM /wbc_tmp | nice grep wbc_tmp | awk '{ print $4 }'`
            if [ $FREETMPSPACE != "0M" ]; then
                PNG_NAME=/wbc_tmp/screenshot`ls /wbc_tmp/screenshot* | wc -l`.png
                echo "Taking screenshot: $PNG_NAME"
                ionice -c 3 nice -n 19 ${HDFPV_RASPI2PNG} -p $PNG_NAME
            else
                echo "RAM disk full - no screenshot taken ..."
            fi

        else
            echo "Video not running - no screenshot taken ..."
        fi
        sleep 5
    done
}


function save_function {
    # let screenshot and check_alive function know that saving is in progrss
    touch /tmp/pausewhile
    # kill OSD so we can safeley start wbc_status
    ps -ef | nice grep "osd" | nice grep -v grep | awk '{print $2}' | xargs kill -9
    ps -ef | nice grep "cat ${HDFPV_TELEMETRY_FIFO_1}" | nice grep -v grep | awk '{print $2}' | xargs kill -9
    # kill video and telemetry recording and also local video display
    ps -ef | nice grep "cat ${HDFPV_VIDEO_FIFO_3}" | nice grep -v grep | awk '{print $2}' | xargs kill -9
    ps -ef | nice grep "cat ${HDFPV_TELEMETRY_FIFO_3}" | nice grep -v grep | awk '{print $2}' | xargs kill -9
    ps -ef | nice grep "$DISPLAY_PROGRAM" | nice grep -v grep | awk '{print $2}' | xargs kill -9
    ps -ef | nice grep "cat ${HDFPV_VIDEO_FIFO_1}" | nice grep -v grep | awk '{print $2}' | xargs kill -9

    # find out if video is on ramdisk or sd
    source /tmp/videofile
    echo "VIDEOFILE: $VIDEOFILE"

    # start re-play of recorded video ....
    nice /opt/vc/src/hello_pi/hello_video/hello_video.bin.player $VIDEOFILE $FPS &

    killall wbc_status > /dev/null 2>&1
    nice ${HDFPV_WBC_STATUS} "Saving to USB. This may take some time ..." 7 55 0 &

    echo -n "Accessing file system.. "

    # some sticks show up as sda1, others as sda, check for both
    if [ -e "/dev/sda1" ]; then
    USBDEV="/dev/sda1"
    else
    USBDEV="/dev/sda"
    fi

    echo "USBDEV: $USBDEV"

    if mount $USBDEV /media/usb; then
    TELEMETRY_SAVE_PATH="/telemetry"
    SCREENSHOT_SAVE_PATH="/screenshot"
    VIDEO_SAVE_PATH="/video"

    if [ -s "/wbc_tmp/telemetrytmp.raw" ]; then
        if [ -d "/media/usb$TELEMETRY_SAVE_PATH" ]; then
        echo "Telemetry save path $TELEMETRY_SAVE_PATH found"
        else
        echo "Creating telemetry save path $TELEMETRY_SAVE_PATH.. "
        mkdir /media/usb$TELEMETRY_SAVE_PATH
        fi
        cp /wbc_tmp/telemetrytmp.raw /media/usb$TELEMETRY_SAVE_PATH/telemetry`ls /media/usb$TELEMETRY_SAVE_PATH/*.raw | wc -l`.raw
        cp /wbc_tmp/telemetrytmp.txt /media/usb$TELEMETRY_SAVE_PATH/telemetry`ls /media/usb$TELEMETRY_SAVE_PATH/*.txt | wc -l`.txt
        cp /wbc_tmp/cmavnode.log /media/usb$TELEMETRY_SAVE_PATH/cmavnode`ls /media/usb$TELEMETRY_SAVE_PATH/*.log | wc -l`.log
    fi

    if [ "$ENABLE_SCREENSHOTS" == "Y" ]; then
        if [ -d "/media/usb$SCREENSHOT_SAVE_PATH" ]; then
        echo "Screenshots save path $SCREENSHOT_SAVE_PATH found"
        else
        echo "Creating screenshots save path $SCREENSHOT_SAVE_PATH.. "
        mkdir /media/usb$SCREENSHOT_SAVE_PATH
        fi
        DIR_NAME_SCREENSHOT=/media/usb$SCREENSHOT_SAVE_PATH/`ls /media/usb$SCREENSHOT_SAVE_PATH | wc -l`
        mkdir $DIR_NAME_SCREENSHOT
        cp /wbc_tmp/screenshot* $DIR_NAME_SCREENSHOT > /dev/null 2>&1
    fi

    if [ -s "$VIDEOFILE" ]; then
        if [ -d "/media/usb$VIDEO_SAVE_PATH" ]; then
        echo "Video save path $VIDEO_SAVE_PATH found"
        else
        echo "Creating video save path $VIDEO_SAVE_PATH.. "
        mkdir /media/usb$VIDEO_SAVE_PATH
        fi
        FILE_NAME_AVI=/media/usb$VIDEO_SAVE_PATH/video`ls /media/usb$VIDEO_SAVE_PATH | wc -l`.avi
        echo "FILE_NAME_AVI: $FILE_NAME_AVI"
        nice avconv -framerate $FPS -i $VIDEOFILE -vcodec copy $FILE_NAME_AVI > /dev/null 2>&1 &
        AVCONVRUNNING=1
        while [ $AVCONVRUNNING -eq 1 ]; do
        AVCONVRUNNING=`pidof avconv | wc -w`
        #echo "AVCONVRUNNING: $AVCONVRUNNING"
        sleep 4
        killall wbc_status > /dev/null 2>&1
        nice ${HDFPV_WBC_STATUS} "Saving - please wait ..." 7 65 0 &
        done
    fi
    #cp /wbc_tmp/tracker.txt /media/usb/
    nice umount /media/usb
    STICKGONE=0
    while [ $STICKGONE -ne 1 ]; do
        killall wbc_status > /dev/null 2>&1
        nice ${HDFPV_WBC_STATUS} "Done - USB memory stick can be removed now" 7 65 0 &
        sleep 4
        if [ ! -e "/dev/sda" ]; then
        STICKGONE=1
        fi
    done
    killall wbc_status > /dev/null 2>&1
    killall hello_video.bin.player > /dev/null 2>&1
    rm /wbc_tmp/* > /dev/null 2>&1
    rm /video_tmp/* > /dev/null 2>&1
    sync
    else
    STICKGONE=0
    while [ $STICKGONE -ne 1 ]; do
        killall wbc_status > /dev/null 2>&1
        nice ${HDFPV_WBC_STATUS} "ERROR: Could not access USB memory stick!" 7 65 0 &
        sleep 4
        if [ ! -e "/dev/sda" ]; then
        STICKGONE=1
        fi
    done
    killall wbc_status > /dev/null 2>&1
    killall hello_video.bin.player > /dev/null 2>&1
    fi

    #killall tracker
    # re-start video/telemetry recording
    ionice -c 3 nice cat ${HDFPV_VIDEO_FIFO_3} >> $VIDEOFILE &
    ionice -c 3 nice cat ${HDFPV_TELEMETRY_FIFO_3} >> /wbc_tmp/telemetrytmp.raw &
    # re-start local video display and osd
    ionice -c 1 -n 4 nice -n -10 cat ${HDFPV_VIDEO_FIFO_1} | ionice -c 1 -n 4 nice -n -10 $DISPLAY_PROGRAM > /dev/null 2>&1 &
    killall wbc_status > /dev/null 2>&1

    OSDRUNNING=`pidof /tmp/osd | wc -w`
    if [ $OSDRUNNING  -ge 1 ]; then
    echo "OSD already running!"
    else
    killall wbc_status > /dev/null 2>&1
    cat ${HDFPV_TELEMETRY_FIFO_1} | /tmp/osd >> /wbc_tmp/telemetrytmp.txt &
    fi
    # let screenshot function know that it can continue taking screenshots
    rm /tmp/pausewhile
}

function pause_while {
        if [ -f "/tmp/pausewhile" ]; then
        PAUSE=1
            while [ $PAUSE -ne 0 ]; do
            if [ ! -f "/tmp/pausewhile" ]; then
                    PAUSE=0
            fi
            sleep 1
        done
    fi
}

function tether_check_function {
    while true; do
        # pause loop while saving is in progress
        pause_while
        if [ -d "/sys/class/net/usb0" ]; then
            echo
        echo "USB tethering device detected. Configuring IP ..."
        nice pump -h wifibrdcast -i usb0 --no-dns --keep-up --no-resolvconf --no-ntp || {
            echo "ERROR: Could not configure IP for USB tethering device!"
            nice killall wbc_status > /dev/null 2>&1
            nice ${HDFPV_WBC_STATUS} "ERROR: Could not configure IP for USB tethering device!" 7 55 0
            collect_debug
            sleep 365d
        }
        # find out smartphone IP to send video stream to
        PHONE_IP=`ip route show 0.0.0.0/0 dev usb0 | cut -d\  -f3`
        echo "Android IP: $PHONE_IP"

        #ionice -c 1 -n 4 nice -n -10 socat -b $VIDEO_UDP_BLOCKSIZE GOPEN:${HDFPV_VIDEO_FIFO_2} UDP4-SENDTO:$PHONE_IP:$VIDEO_UDP_PORT &
        nice socat -b $TELEMETRY_UDP_BLOCKSIZE GOPEN:${HDFPV_TELEMETRY_FIFO_2} UDP4-SENDTO:$PHONE_IP:$TELEMETRY_UDP_PORT &
        nice ${HDFPV_RSSI_FORWARD} /wifibroadcast_rx_status_0 $PHONE_IP &

        if [ "$FORWARD_STREAM" == "rtp" ]; then
            ionice -c 1 -n 4 nice -n -5 cat ${HDFPV_VIDEO_FIFO_2} | nice -n -5 gst-launch-1.0 fdsrc ! h264parse ! rtph264pay pt=96 config-interval=5 ! udpsink port=$VIDEO_UDP_PORT host=$PHONE_IP > /dev/null 2>&1 &
        else
            ionice -c 1 -n 4 nice -n -10 socat -b $VIDEO_UDP_BLOCKSIZE GOPEN:${HDFPV_VIDEO_FIFO_2} UDP4-SENDTO:$PHONE_IP:$VIDEO_UDP_PORT &
        fi
        cat ${HDFPV_TELEMETRY_FIFO_5} > /dev/pts/0 &
        cp /root/cmavnode/cmavnode.conf /tmp/
        echo "targetip=$PHONE_IP" >> /tmp/cmavnode.conf
        ionice -c 3 nice /root/cmavnode/cmavnode --file /tmp/cmavnode.conf &

        # kill and pause OSD so we can safeley start wbc_status
        ps -ef | nice grep "osd" | nice grep -v grep | awk '{print $2}' | xargs kill -9
        ps -ef | nice grep "cat ${HDFPV_TELEMETRY_FIFO_1}" | nice grep -v grep | awk '{print $2}' | xargs kill -9

        killall wbc_status > /dev/null 2>&1
        nice ${HDFPV_WBC_STATUS} "Secondary display connected (USB)" 7 55 0

        # re-start osd
        killall wbc_status > /dev/null 2>&1

        OSDRUNNING=`pidof /tmp/osd | wc -w`
        if [ $OSDRUNNING  -ge 1 ]; then
            echo "OSD already running!"
        else
            killall wbc_status > /dev/null 2>&1
            cat ${HDFPV_TELEMETRY_FIFO_1} | /tmp/osd >> /wbc_tmp/telemetrytmp.txt &
        fi

        # check if smartphone has been disconnected
        PHONETHERE=1
        while [  $PHONETHERE -eq 1 ]; do
                if [ -d "/sys/class/net/usb0" ]; then
            PHONETHERE=1
            echo "Android device still connected ..."
            else
            echo "Android device gone"
            # re-start local video display
            #ionice -c 1 -n 4 nice -n -10 cat ${HDFPV_VIDEO_FIFO_1} | ionice -c 1 -n 4 nice -n -10 $DISPLAY_PROGRAM > /dev/null 2>&1 &
            # kill and pause OSD so we can safeley start wbc_status
            ps -ef | nice grep "osd" | nice grep -v grep | awk '{print $2}' | xargs kill -9
            ps -ef | nice grep "cat ${HDFPV_TELEMETRY_FIFO_1}" | nice grep -v grep | awk '{print $2}' | xargs kill -9
            killall wbc_status > /dev/null 2>&1
            nice ${HDFPV_WBC_STATUS} "Secondary display disconnected (USB)" 7 55 0
            # re-start osd
            OSDRUNNING=`pidof /tmp/osd | wc -w`
            if [ $OSDRUNNING  -ge 1 ]; then
                echo "OSD already running!"
            else
                killall wbc_status > /dev/null 2>&1
            cat ${HDFPV_TELEMETRY_FIFO_1} | /tmp/osd >> /wbc_tmp/telemetrytmp.txt &
            fi
            PHONETHERE=0
            # kill forwarding of video and osd to secondary display
            ps -ef | nice grep "socat -b $VIDEO_UDP_BLOCKSIZE GOPEN:${HDFPV_VIDEO_FIFO_2}" | nice grep -v grep | awk '{print $2}' | xargs kill -9
            ps -ef | nice grep "gst-launch-1.0" | nice grep -v grep | awk '{print $2}' | xargs kill -9
            ps -ef | nice grep "cat ${HDFPV_VIDEO_FIFO_2}" | nice grep -v grep | awk '{print $2}' | xargs kill -9
            ps -ef | nice grep "socat -b $TELEMETRY_UDP_BLOCKSIZE GOPEN:${HDFPV_TELEMETRY_FIFO_2}" | nice grep -v grep | awk '{print $2}' | xargs kill -9
            ps -ef | nice grep "cat ${HDFPV_TELEMETRY_FIFO_5}" | nice grep -v grep | awk '{print $2}' | xargs kill -9
            ps -ef | nice grep "cmavnode" | nice grep -v grep | awk '{print $2}' | xargs kill -9
            ps -ef | nice grep "rssi_forward" | nice grep -v grep | awk '{print $2}' | xargs kill -9
            fi
            sleep 1
        done
        else
        echo "Android device not detected ..."
        fi
        sleep 1
    done
}

function hotspot_check_function {
        # Convert hostap config from DOS format to UNIX format
    ionice -c 3 nice dos2unix -n /boot/apconfig.txt /tmp/apconfig.txt

    if [ "$ETHERNET_HOTSPOT" == "Y" ]; then
        # setup hotspot on RPI3 internal ethernet chip
        nice ifconfig eth0 192.168.1.1 up
        nice udhcpd -I 192.168.1.1 /etc/udhcpd-eth.conf
    fi

    if [ "$WIFI_HOTSPOT" == "Y" ]; then
        nice udhcpd -I 192.168.2.1 /etc/udhcpd-wifi.conf
        nice -n 5 hostapd -B -d /tmp/apconfig.txt
    fi

    while true; do
        # pause loop while saving is in progress
        pause_while
        IP=0
        if [ "$ETHERNET_HOTSPOT" == "Y" ]; then
        if nice ping -I eth0 -c 1 -W 1 -n -q 192.168.1.2 > /dev/null 2>&1; then
            IP="192.168.1.2"
            echo "Ethernet device detected. IP: $IP"
            nice socat -b $TELEMETRY_UDP_BLOCKSIZE GOPEN:${HDFPV_TELEMETRY_FIFO_2} UDP4-SENDTO:$IP:$TELEMETRY_UDP_PORT &
            nice ${HDFPV_RSSI_FORWARD} /wifibroadcast_rx_status_0 $IP &
            if [ "$FORWARD_STREAM" == "rtp" ]; then
            ionice -c 1 -n 4 nice -n -5 cat ${HDFPV_VIDEO_FIFO_2} | nice -n -5 gst-launch-1.0 fdsrc ! h264parse ! rtph264pay pt=96 config-interval=5 ! udpsink port=$VIDEO_UDP_PORT host=$IP > /dev/null 2>&1 &
            else
            ionice -c 1 -n 4 nice -n -10 socat -b $VIDEO_UDP_BLOCKSIZE GOPEN:${HDFPV_VIDEO_FIFO_2} UDP4-SENDTO:$IP:$VIDEO_UDP_PORT &
            fi
            nice cat ${HDFPV_TELEMETRY_FIFO_5} > /dev/pts/0 &
            cp /root/cmavnode/cmavnode.conf /tmp/
            echo "targetip=$IP" >> /tmp/cmavnode.conf
            ionice -c 3 nice /root/cmavnode/cmavnode --file /tmp/cmavnode.conf &
        fi
        fi
        if [ "$WIFI_HOTSPOT" == "Y" ]; then
        if nice ping -I wifihotspot0 -c 2 -W 1 -n -q 192.168.2.2 > /dev/null 2>&1; then
            IP="192.168.2.2"
            echo "Wifi device detected. IP: $IP"
            nice socat -b $TELEMETRY_UDP_BLOCKSIZE GOPEN:${HDFPV_TELEMETRY_FIFO_2} UDP4-SENDTO:$IP:$TELEMETRY_UDP_PORT &
            nice ${HDFPV_RSSI_FORWARD} /wifibroadcast_rx_status_0 $IP &
            if [ "$FORWARD_STREAM" == "rtp" ]; then
            ionice -c 1 -n 4 nice -n -5 cat ${HDFPV_VIDEO_FIFO_2} | nice -n -5 gst-launch-1.0 fdsrc ! h264parse ! rtph264pay pt=96 config-interval=5 ! udpsink port=$VIDEO_UDP_PORT host=$IP > /dev/null 2>&1 &
            else
            ionice -c 1 -n 4 nice -n -10 socat -b $VIDEO_UDP_BLOCKSIZE GOPEN:${HDFPV_VIDEO_FIFO_2} UDP4-SENDTO:$IP:$VIDEO_UDP_PORT &
            fi
            cat ${HDFPV_TELEMETRY_FIFO_5} > /dev/pts/0 &
            cp /root/cmavnode/cmavnode.conf /tmp/
            echo "targetip=$IP" >> /tmp/cmavnode.conf
            ionice -c 3 nice /root/cmavnode/cmavnode --file /tmp/cmavnode.conf &
        fi
        fi
        if [ "$IP" != "0" ]; then
        # kill and pause OSD so we can safeley start wbc_status
        ps -ef | nice grep "osd" | nice grep -v grep | awk '{print $2}' | xargs kill -9
        ps -ef | nice grep "cat ${HDFPV_TELEMETRY_FIFO_1}" | nice grep -v grep | awk '{print $2}' | xargs kill -9

            killall wbc_status > /dev/null 2>&1
        nice ${HDFPV_WBC_STATUS} "Secondary display connected (Hotspot)" 7 55 0

        # re-start osd
        OSDRUNNING=`pidof /tmp/osd | wc -w`
        if [ $OSDRUNNING  -ge 1 ]; then
            echo "OSD already running!"
        else
            killall wbc_status > /dev/null 2>&1
            cat ${HDFPV_TELEMETRY_FIFO_1} | /tmp/osd >> /wbc_tmp/telemetrytmp.txt &
        fi

        # check if connection is still connected
        IPTHERE=1
        while [  $IPTHERE -eq 1 ]; do
            if ping -c 2 -W 1 -n -q $IP > /dev/null 2>&1; then
            IPTHERE=1
            echo "IP $IP still connected ..."
            else
            echo "IP $IP gone"
            # kill and pause OSD so we can safeley start wbc_status
            ps -ef | nice grep "osd" | nice grep -v grep | awk '{print $2}' | xargs kill -9
            ps -ef | nice grep "cat ${HDFPV_TELEMETRY_FIFO_1}" | nice grep -v grep | awk '{print $2}' | xargs kill -9

            killall wbc_status > /dev/null 2>&1
            nice ${HDFPV_WBC_STATUS} "Secondary display disconnected (Hotspot)" 7 55 0
            # re-start osd
            OSDRUNNING=`pidof /tmp/osd | wc -w`
            if [ $OSDRUNNING  -ge 1 ]; then
                echo "OSD already running!"
            else
                killall wbc_status > /dev/null 2>&1
                OSDRUNNING=`pidof /tmp/osd | wc -w`
                if [ $OSDRUNNING  -ge 1 ]; then
                echo "OSD already running!"
                else
                killall wbc_status > /dev/null 2>&1
                    cat ${HDFPV_TELEMETRY_FIFO_1} | /tmp/osd >> /wbc_tmp/telemetrytmp.txt &
                fi
            fi
            IPTHERE=0
            # kill forwarding of video and telemetry to secondary display
            ps -ef | nice grep "socat -b $VIDEO_UDP_BLOCKSIZE GOPEN:${HDFPV_VIDEO_FIFO_2}" | nice grep -v grep | awk '{print $2}' | xargs kill -9
            ps -ef | nice grep "gst-launch-1.0" | nice grep -v grep | awk '{print $2}' | xargs kill -9
            ps -ef | nice grep "cat ${HDFPV_VIDEO_FIFO_2}" | nice grep -v grep | awk '{print $2}' | xargs kill -9
            ps -ef | nice grep "socat -b $TELEMETRY_UDP_BLOCKSIZE GOPEN:${HDFPV_TELEMETRY_FIFO_2}" | nice grep -v grep | awk '{print $2}' | xargs kill -9
            ps -ef | nice grep "cat ${HDFPV_TELEMETRY_FIFO_5}" | nice grep -v grep | awk '{print $2}' | xargs kill -9
            ps -ef | nice grep "cmavnode" | nice grep -v grep | awk '{print $2}' | xargs kill -9
            ps -ef | nice grep "rssi_forward" | nice grep -v grep | awk '{print $2}' | xargs kill -9
            fi
                sleep 1
        done
        else
        echo "No IP detected ..."
        fi
        sleep 1
    done
}
