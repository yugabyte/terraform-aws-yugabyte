#!/bin/bash

###############################################################################
#
# This script configures a list of nodes and creates a universe.
#
# Usage:
#   create_universe.sh <rf> <config ips> <ssh ips> <ssh user> <ssh-key file>
#       <config ips> : space separated set of ips the nodes should use to talk to
#                      each other
#       <ssh ips>    : space separated set of ips used to ssh to the nodes in
#                      order to configure them
#
###############################################################################


# Get the replication factor.
RF=$1
echo "Replication factor: $RF"

# Get the list of nodes (ips) used for intra-cluster communication.
NODES=$2
echo "Creating universe with nodes: [$NODES]"

# Get the list of ips to ssh to the corresponding nodes.
SSH_IPS=$3
echo "Connecting to nodes with ips: [$SSH_IPS]"

# Get the credentials to connect to the nodes.
SSH_USER=$4
SSH_KEY_PATH=$5

YB_HOME=/home/ec2-user/yugabyte-db
YB_MASTER_ADDRESSES=""
idx=0
master_ips=""


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
    master_ips="$master_ips $node"
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
for node in $SSH_IPS
do
  ssh -o "StrictHostKeyChecking no" -i ${SSH_KEY_PATH} ${SSH_USER}@$node "$MASTER_CONF_CMD ; $TSERVER_CONF_CMD"
done

###############################################################################
# Setup PGSQL proxies across all nodes
###############################################################################
echo "Enabling Postgres proxies..."
TSERVER_PGSQL_PROXY_CMD="echo '--start_pgsql_proxy >> ${YB_HOME}/tserver/conf/server.conf"
for node in $SSH_IPS
do
  ssh -o "StrictHostKeyChecking no" -i ${SSH_KEY_PATH} ${SSH_USER}@$node "$TSERVER_PGSQL_PROXY_CMD ; echo '--pgsql_proxy_bind_address=$node:5433' >> ${YB_HOME}/tserver/server.conf"

###############################################################################
# Start the masters.
###############################################################################
echo "Starting masters..."
MASTER_EXE=${YB_HOME}/master/bin/yb-master
MASTER_OUT=${YB_HOME}/master/master.out
MASTER_ERR=${YB_HOME}/master/master.err
MASTER_START_CMD="nohup ${MASTER_EXE} --flagfile ${YB_HOME}/master/conf/server.conf >>${MASTER_OUT} 2>>${MASTER_ERR} </dev/null &"
for node in $master_ips
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
for node in $SSH_IPS
do
  ssh -o "StrictHostKeyChecking no" -i ${SSH_KEY_PATH} ${SSH_USER}@$node "$TSERVER_START_CMD"
done

###############################################################################
# Run initdb on one of the nodes
###############################################################################
echo "Initializing postgres via initdb..."

INITDB_CMD="YB_ENABLED_IN_POSTGRES=1 FLAGS_pggate_master_addresses=${YB_MASTER_ADDRESSES} ${YB_HOME}/postgres/bin/initdb -D /tmp/yb_pg_initdb_tmp_data_dir -U postgres >>${YB_HOME}/tserver/postgres.out"
ssh -o "StrictHostKeyChecking no" -i ${SSH_KEY_PATH} ${SSH_USER}@${NODES[1]} "$INITDB_CMD"
echo "Postgres initialization complete."

