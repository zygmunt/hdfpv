#!/bin/bash
# Original file: /root/.profile comes from: EZ-Wifibroadcast-1.5
# Modified by https://github.com/zygmunt
# Here are only settings variables

# check if cam is detected to determine if we're going to be RX or TX
CAM=$(vcgencmd get_camera | nice grep -c detected=1)

### DIRS:

HDFPV_DIR="/opt/hdfpv"
HDFPV_BINDIR="${HDFPV_DIR}/bin"
HDFPV_RUNDIR="${HDFPV_DIR}/run"
HDFPV_TMPDIR="/tmp"
HDFPV_BOOT="/boot"

# HDFPV_SET_FLAG="ok"

### FIFO:

HDFPV_MSP_FIFO="${HDFPV_RUNDIR}/mspfifo1"
HDFPV_TELEMETRY_FIFO="${HDFPV_RUNDIR}/telemetryfifo"
HDFPV_TELEMETRY_FIFO_1="${HDFPV_TELEMETRY_FIFO}1"
HDFPV_TELEMETRY_FIFO_2="${HDFPV_TELEMETRY_FIFO}2"
HDFPV_TELEMETRY_FIFO_3="${HDFPV_TELEMETRY_FIFO}3"
HDFPV_TELEMETRY_FIFO_4="${HDFPV_TELEMETRY_FIFO}4"
HDFPV_TELEMETRY_FIFO_5="${HDFPV_TELEMETRY_FIFO}5"
HDFPV_TELEMETRY_FIFO_6="${HDFPV_TELEMETRY_FIFO}6"
HDFPV_VIDEO_FIFO="${HDFPV_RUNDIR}/videofifo"
HDFPV_VIDEO_FIFO_1="${HDFPV_VIDEO_FIFO}1"
HDFPV_VIDEO_FIFO_2="${HDFPV_VIDEO_FIFO}2"
HDFPV_VIDEO_FIFO_3="${HDFPV_VIDEO_FIFO}3"
HDFPV_VIDEO_FIFO_4="${HDFPV_VIDEO_FIFO}4"

HDFPV_FIFO_FILES = (
    $(HDFPV_MSP_FIFO)
    $(HDFPV_TELEMETRY_FIFO_1)
    $(HDFPV_TELEMETRY_FIFO_2)
    $(HDFPV_TELEMETRY_FIFO_3)
    $(HDFPV_TELEMETRY_FIFO_4)
    $(HDFPV_TELEMETRY_FIFO_5)
    $(HDFPV_TELEMETRY_FIFO_6)
    $(HDFPV_VIDEO_FIFO_1)
    $(HDFPV_VIDEO_FIFO_2)
    $(HDFPV_VIDEO_FIFO_3)
    $(HDFPV_VIDEO_FIFO_4)
)

### PROGRAMS:

HDFPV_WBC_STATUS="${HDFPV_BINDIR}/wbc_status"
HDFPV_TX="${HDFPV_BINDIR}/tx"
HDFPV_RX="${HDFPV_BINDIR}/rx"
HDFPV_FTEE="${HDFPV_BINDIR}/ftee"

HDFPV_RCRX="${HDFPV_BINDIR}/rcrx"
HDFPV_RSSITX="${HDFPV_BINDIR}/rssitx"
HDFPV_RSSIRX="${HDFPV_BINDIR}/rssirx"
HDFPV_RASPI2PNG="${HDFPV_BINDIR}/raspi2png"
HDFPV_RSSI_FORWARD="${HDFPV_BINDIR}/rssi_forward"
HDFPV_CHANNELSCAN="${HDFPV_BINDIR}/channelscan"
HDFPV_TRACKER="${HDFPV_BINDIR}/tracker"
HDFPV_CHECK_ALIVE="${HDFPV_BINDIR}/check_alive"

### CONFIG:

OSD_CONF="${HDFPV_BOOT}/osdconfig.txt"
WIFIBROADCAST_CONF="${HDFPV_BOOT}/wifibroadcast.txt"

WIFIBROADCAST_CONF_TMP="${HDFPV_TMPDIR}/settings.sh"
dos2unix -n ${WIFIBROADCAST_CONF} ${WIFIBROADCAST_CONF_TMP} > /dev/null 2>&1

source ${WIFIBROADCAST_CONF_TMP}

case $BITRATE in
    1)
    UPLINK_WIFI_BITRATE=6
    TELEMETRY_WIFI_BITRATE=6
    if [ "$CTS_PROTECTION" == "Y" ]; then
        VIDEO_WIFI_BITRATE=12
    else
        VIDEO_WIFI_BITRATE=6
    fi
    if [ "$TXMODE" != "single" ]; then
        VIDEO_WIFI_BITRATE=12
    fi
    BITRATE=2500000
    ;;
    2)
    UPLINK_WIFI_BITRATE=12
    TELEMETRY_WIFI_BITRATE=12
    if [ "$CTS_PROTECTION" == "Y" ]; then
        VIDEO_WIFI_BITRATE=18
    else
        VIDEO_WIFI_BITRATE=12
    fi
    if [ "$TXMODE" != "single" ]; then
        VIDEO_WIFI_BITRATE=18
    fi
    BITRATE=4500000
    ;;
    3)
    UPLINK_WIFI_BITRATE=18
    TELEMETRY_WIFI_BITRATE=18
    if [ "$CTS_PROTECTION" == "Y" ]; then
        VIDEO_WIFI_BITRATE=24
    else
        VIDEO_WIFI_BITRATE=18
    fi
    if [ "$TXMODE" != "single" ]; then
        VIDEO_WIFI_BITRATE=24
    fi
    BITRATE=6000000
    ;;
    4)
    UPLINK_WIFI_BITRATE=18
    TELEMETRY_WIFI_BITRATE=24
    if [ "$CTS_PROTECTION" == "Y" ]; then
        VIDEO_WIFI_BITRATE=36
    else
        VIDEO_WIFI_BITRATE=24
    fi
    if [ "$TXMODE" != "single" ]; then
        VIDEO_WIFI_BITRATE=36
    fi
    BITRATE=8500000
    ;;
    5)
    UPLINK_WIFI_BITRATE=24
    TELEMETRY_WIFI_BITRATE=36
    if [ "$CTS_PROTECTION" == "Y" ]; then
        VIDEO_WIFI_BITRATE=48
    else
        VIDEO_WIFI_BITRATE=36
    fi
    if [ "$TXMODE" != "single" ]; then
        VIDEO_WIFI_BITRATE=48
    fi
    BITRATE=11500000
    ;;
esac

TELEMETRY_BLOCKS=1
TELEMETRY_FECS=0
TELEMETRY_BLOCKLENGTH=32
TELEMETRY_MIN_BLOCKLENGTH=10

FC_TELEMETRY_STTY_OPTIONS="-imaxbel -opost -isig -icanon -echo -echoe -ixoff -ixon"

# mmormota's stutter-free hello_video.bin: "hello_video.bin.30-mm" (for 30fps) or "hello_video.bin.48-mm" (for 48 and 59.9fps)
# befinitiv's hello_video.bin: "hello_video.bin.240-befi" (for any fps, use this for higher than 59.9fps)

if [ "$FPS" == "59.9" ]; then
    DISPLAY_PROGRAM="${HDFPV_DIR}/video-48-mm"
else
    if [ "$FPS" -eq 30 ]; then
        DISPLAY_PROGRAM="${HDFPV_DIR}/video-30-mm"
    fi
    if [ "$FPS" -lt 60 ]; then
        DISPLAY_PROGRAM="${HDFPV_DIR}/video-48-mm"
    fi
    if [ "$FPS" -gt 60 ]; then
        DISPLAY_PROGRAM="${HDFPV_DIR}/video-240-befi"
    fi
fi

VIDEO_UDP_BLOCKSIZE=1024
TELEMETRY_UDP_BLOCKSIZE=128

RELAY_VIDEO_BLOCKS=8
RELAY_VIDEO_FECS=4
RELAY_VIDEO_BLOCKLENGTH=1024

RELAY_TELEMETRY_BLOCKS=1
RELAY_TELEMETRY_FECS=0
RELAY_TELEMETRY_BLOCKLENGTH=32

EXTERNAL_TELEMETRY_SERIALPORT_GROUND_STTY_OPTIONS="-imaxbel -opost -isig -icanon -echo -echoe -ixoff -ixon"
TELEMETRY_OUTPUT_SERIALPORT_GROUND_STTY_OPTIONS="-imaxbel -opost -isig -icanon -echo -echoe -ixoff -ixon"

VIDEO_UDP_PORT=5000
RSSI_UDP_PORT=5003

if cat ${OSD_CONF} | grep -q "^#define LTM"; then
    TELEMETRY_UDP_PORT=5001
fi
if cat ${OSD_CONF} | grep -q "^#define FRSKY"; then
    TELEMETRY_UDP_PORT=5002
fi
if cat ${OSD_CONF} | grep -q "^#define MAVLINK"; then
    TELEMETRY_UDP_PORT=5004
fi

if [ "$CTS_PROTECTION" == "Y" ]; then
    VIDEO_FRAMETYPE=1 # use standard data frames, so that CTS is generated for Atheros
    TELEMETRY_FRAMETYPE=1
    VIDEO_BLOCKLENGTH=1400
else
    VIDEO_FRAMETYPE=5 # use beacon frames, no CTS
    TELEMETRY_FRAMETYPE=5 # use beacon frames, no CTS
fi

if [ "$TXMODE" != "single" ]; then # always type 1 in dual tx mode since ralink beacon injection broken
    VIDEO_FRAMETYPE=1
    TELEMETRY_FRAMETYPE=1
    VIDEO_BLOCKLENGTH=1400
fi

if [ "$CAM" == "0" ]; then # we are RX
    # use fixed 1400bytes on RX to make sure both CTS and no CTS protection works
    VIDEO_BLOCKLENGTH=1400
fi
