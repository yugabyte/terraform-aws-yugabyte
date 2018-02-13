#!/bin/bash

###############################################################################
#
# This script configures a list of nodes and creates a universe.
#
# Usage:
#   create_universe.sh <rf> <space separated list of ips> <ssh user> <ssh-key file>
#
###############################################################################


# Get the replication factor.
RF=$1
echo "Replication factor: $RF"

# Get the list of nodes.
NODES=$2
echo "Creating universe with nodes: [$NODES]"

# Get the credentials to connect to the nodes.
SSH_USER=$3
SSH_KEY_PATH=$4

YB_HOME=/home/ec2-user/yugabyte-db
YB_MASTER_ADDRESSES=""
MASTER_NODES=""
idx=0
num_masters_added=0


###############################################################################
# Pick the masters as per the replication factor.
###############################################################################
for node in $NODES
do
  if (( $idx < $RF )); then
  	if [ ! -z $YB_MASTER_ADDRESSES ]; then
  	  YB_MASTER_ADDRESSES="$YB_MASTER_ADDRESSES,"
  	fi
    YB_MASTER_ADDRESSES="$YB_MASTER_ADDRESSES$node:7100"
    MASTER_NODES="$MASTER_NODES $node"
  fi
  idx=`expr $idx + 1`
done

# Error out if we do not have sufficient nodes.
if (( $idx < $RF )); then
  echo "Error: insufficient nodes - got $idx node(s) but rf = $RF"
  exit 1
fi
echo "Master addresses: $YB_MASTER_ADDRESSES"


###############################################################################
# Setup master addresses across all the nodes.
###############################################################################
echo "Finalizing configuration..."
MASTER_CONF_CMD="echo '--master_addresses=${YB_MASTER_ADDRESSES}' >> ${YB_HOME}/master/conf/server.conf"
TSERVER_CONF_CMD="echo '--tserver_master_addrs=${YB_MASTER_ADDRESSES}' >> ${YB_HOME}/tserver/conf/server.conf"
for node in $NODES
do
  ssh -o "StrictHostKeyChecking no" -i ${SSH_KEY_PATH} ${SSH_USER}@$node "$MASTER_CONF_CMD ; $TSERVER_CONF_CMD"
done


###############################################################################
# Start the masters.
###############################################################################
echo "Starting masters..."
MASTER_CONF_CMD="echo '--master_addresses=${YB_MASTER_ADDRESSES}' >> ${YB_HOME}/master/conf/server.conf"
MASTER_EXE=${YB_HOME}/master/bin/yb-master
MASTER_OUT=${YB_HOME}/master/master.out
MASTER_ERR=${YB_HOME}/master/master.err
MASTER_START_CMD="nohup ${MASTER_EXE} --flagfile ${YB_HOME}/master/conf/server.conf >>${MASTER_OUT} 2>>${MASTER_ERR} </dev/null &"
for node in $NODES
do
  ssh -o "StrictHostKeyChecking no" -i ${SSH_KEY_PATH} ${SSH_USER}@$node "$MASTER_START_CMD"
done


###############################################################################
# Start the tservers.
###############################################################################
echo "Starting tservers..."
TSERVER_CONF_CMD="echo '--tserver_master_addrs=${YB_MASTER_ADDRESSES}' >> ${YB_HOME}/tserver/conf/server.conf"
TSERVER_EXE=${YB_HOME}/tserver/bin/yb-tserver
TSERVER_OUT=${YB_HOME}/tserver/tserver.out
TSERVER_ERR=${YB_HOME}/tserver/tserver.err
TSERVER_START_CMD="nohup ${TSERVER_EXE} --flagfile ${YB_HOME}/tserver/conf/server.conf >>${TSERVER_OUT} 2>>${TSERVER_ERR} </dev/null &"
for node in $NODES
do
  ssh -o "StrictHostKeyChecking no" -i ${SSH_KEY_PATH} ${SSH_USER}@$node "$TSERVER_START_CMD"
done
