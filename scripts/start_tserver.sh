#!/bin/bash

###############################################################################
#
# This is a simple script to start the yb-tserver process on a machine.
#
###############################################################################

YB_HOME=/home/ec2-user/yugabyte-db
source ${YB_HOME}/.yb_env.sh

TSERVER_EXE=${YB_HOME}/tserver/bin/yb-tserver
TSERVER_OUT=${YB_HOME}/tserver/tserver.out
TSERVER_ERR=${YB_HOME}/tserver/tserver.err
if [ ! -f /tmp/yb-tserver-check.lock ]; then
   touch /tmp/yb-tserver-check.lock
else
   exit 0
fi
ps -ef | grep -v grep | grep yb-tserver >/dev/null 2>&1
case "$?" in
   0)
   echo "yb-tserver process is running."
   ;;
   1)
   echo "yb-tserver process is not running - restarting.."
   nohup ${TSERVER_EXE} --flagfile ${YB_HOME}/tserver/conf/server.conf >>${TSERVER_OUT} 2>>${TSERVER_ERR} </dev/null &
   ;; 
esac
rm -f /tmp/yb-tserver-check.lock
exit 0
