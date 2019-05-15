#!/bin/bash

###############################################################################
#
# This is a simple script to start the yb-master process on a machine.
#
###############################################################################

YB_HOME=/home/ec2-user/yugabyte-db
source ${YB_HOME}/.yb_env.sh

MASTER_EXE=${YB_HOME}/master/bin/yb-master
MASTER_OUT=${YB_HOME}/master/master.out
MASTER_ERR=${YB_HOME}/master/master.err
if [ ! -f /tmp/yb-master-check.lock ]; then
   touch /tmp/yb-master-check.lock
else
   exit 0
fi
ps -ef | grep -v grep | grep yb-master >/dev/null 2>&1
case "$?" in
   0)
   echo "yb-master process is running."
   ;;
   1)
   echo "yb-master process is not running - restarting.."
   nohup ${MASTER_EXE} --flagfile ${YB_HOME}/master/conf/server.conf >>${MASTER_OUT} 2>>${MASTER_ERR} </dev/null &
   ;; 
esac
rm -f /tmp/yb-master-check.lock
exit 0
