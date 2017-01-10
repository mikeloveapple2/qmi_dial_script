#!/bin/sh

# TODO add failed time to reconnect

###
# This script automate the setup of QMI supported wwan devices.
#
# Tested on following environment:
#   * Lenovo ThinkPad X220 (4286-CTO)
#   * Gentoo/Linux, Linux Kernel 3.9.6
#   * NTT Docomo UIM card (Xi LTE SIM)
#   * Sierra Wireless, Inc. Gobi 3000 wireless wan module
#     (FRU 60Y3257, vendor and device id is 1199:9013)
#     memo:
#       I recommend to check if your wwan module works fine
#       for your mobile broadband provider with Windows
#       especially if you imported the device from other country.
#       You may have to initialize your device for your region.
#   * Required kernel config (other modules may be also required):
#     - qmi_wwan (CONFIG_USB_NET_QMI_WWAN)
#     - qcserial (CONFIG_USB_SERIAL_QUALCOMM)
#   * Required settings:
#     - you may have to create /etc/qmi-network.conf.
#       My qmi-network.conf has only a line "APN=mopera.net".
#

# your wwan device name created by qmi_wwan kernel module
# check it with "ip a" or "ifconfig -a". it may be wwan0?
WWAN_DEV=wwan0
# your cdc_wdm modem location
CDC_WDM=/dev/cdc-wdm0
# this script uses following qmi commands
QMICLI=/usr/bin/qmicli
QMI_NETWORK=/usr/bin/qmi-network
#QMICLI="/usr/local/bin/qmicli"
#QMI_NETWORK="/usr/local/bin/qmi-network"
# the places of following commands vary depending on your distribution
IFCONFIG=/sbin/ifconfig
DHCPCD=/sbin/dhcpcd
SUDO=/usr/bin/sudo
RESET_CMD="resetusb"
CHECK_INTERVAL=5
DEBUG_FLAG=0

function helpmsg {
    echo "usage: $0 {start|stop|restart|status}"
    exit 1
}

function reset_device(){
    echo "reset the ${CDC_WDM}"
    str=$(lsusb | grep Qualcomm)
    num1=$(echo "${str}" | cut -d ' ' -f 2)
    num2_tmp=$(echo "${str}" | cut -d ' ' -f 4)
    num2=$(echo ${num2_tmp} | cut -d ':' -f 1)
    echo $num1 $num2

    $RESET_CMD /dev/bus/usb/${num1}/${num2}
}

function qmi_start {
    reset_device
    sleep 2 

    $COMMAND_PREFIX $IFCONFIG $WWAN_DEV up
    $COMMAND_PREFIX $QMICLI -d $CDC_WDM --dms-set-operating-mode=online
    if [ $? -ne 0 ]; then
	echo "your wwan device may be RFKilled?"
	exit 1
    fi
    $COMMAND_PREFIX $QMI_NETWORK $CDC_WDM start
    $COMMAND_PREFIX $DHCPCD $WWAN_DEV
}

function qmi_stop {
    $COMMAND_PREFIX $QMI_NETWORK $CDC_WDM stop
    $COMMAND_PREFIX kill `cat /var/run/dhcpcd-${WWAN_DEV}.pid`
    $COMMAND_PREFIX $IFCONFIG $WWAN_DEV down
}

function qmi_strength {
    dbm=`$COMMAND_PREFIX $QMICLI -d $CDC_WDM --nas-get-signal-strength | tr "'" " " | grep Network | head -1 | awk '{print $4}'`
    echo -n "Signal strength is "
    if [ $dbm -ge -73 ]; then
	echo -n 'Excellent'
    elif [ $dbm -ge -83 ]; then
	echo -n 'Good'
    elif [ $dbm -ge -93 ]; then
	echo -n 'OK'
    elif [ $dbm -ge -109 ]; then
	echo -n 'Marginal'
    else
	echo Unknown
    fi
    echo " (${dbm} dBm)"
}

function qmi_status {
    $COMMAND_PREFIX $QMI_NETWORK $CDC_WDM status
    qmi_strength
}

## check argument number
#if [ $# -ne 1 ]
#then
#    helpmsg
#fi

## check permission
if [ `whoami` != 'root' ]
then
    echo "warning: root permission required. setting command prefix to 'sudo'."
    COMMAND_PREFIX=$SUDO
fi

## run commands
#case $1 in
#    start) qmi_start ;;
#    stop) qmi_stop ;;
#    restart) qmi_stop; qmi_start ;;
#    status) qmi_status ;;
#    *) helpmsg ;;
#esac

echo "test redial"
TEST_URL="114.114.114.114"
#TEST_URL="www.o2oc.cn"
RETRY_NUM=3
FAIL_TIME=1

while true; do
    if [ -e ${CDC_WDM} ];then
        parameter="-I ${WWAN_DEV} ${TEST_URL} -c 3"
        
        ping ${parameter} > /dev/null 2>&1
        result=$?

        if [ $DEBUG_FLAG -lt 0 ];then
            echo "result :: ${result}"
            echo "run cmd :: ping " ${parameter}
        fi

        if [ ${result} == 0 ];then
            echo "--------connected-------"
        elif [ ${result} != 0 ];then
            echo "--------discconnected-------"
            if [ $FAIL_TIME -lt $RETRY_NUM ];then
                FAIL_TIME=$((FAIL_TIME + 1))
                echo "fail count : " $FAIL_TIME 
            else
                FAIL_TIME=1
                echo "redial at once"
                qmi_stop;qmi_start
            fi
        fi
    else
        echo "Not exist"
    fi
    sleep  ${CHECK_INTERVAL}
done
