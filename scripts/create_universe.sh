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


# Get the name of the cloud
CLOUD_NAME=$1

# Get the region name
REGION=$2

# Get the replication factor.
RF=$3
echo "Replication factor: $RF"

# Get the list of nodes (ips) used for intra-cluster communication.
NODES=$4
echo "Creating universe with nodes: [$NODES]"

# Get the list of ips to ssh to the corresponding nodes.
SSH_IPS=$5
echo "Connecting to nodes with ips: [$SSH_IPS]"

# Get the list of AZs for the nodes.
ZONES=$6

# Get the credentials to connect to the nodes.
SSH_USER=$7
SSH_KEY_PATH=$8

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
MASTER_ADDR_ARRAY=($master_ips)
zone_array=($ZONES)
num_zones=`(IFS=$'\n';sort <<< "${zone_array[*]}") | uniq -c | wc -l`

# Error out if number of AZ's is not 1 but not equal to RF
if (( $num_zones > 1 )); then
   if (( $num_zones < $RF )); then
      echo "Error insufficient AZ's for master placement - must be equal to $RF"
      exit 1
   else
      echo "Multi AZ placement detected. Nodes in ${zone_array[@]}"
   fi
else
   echo "Single AZ placement detected - all nodes in ${zone_array[0]}"
fi

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
# Setup placement information if multi-AZ
###############################################################################

echo "Adding placement information ... number of zones = ${num_zones}"

MASTER_CONF_CLOUDNAME="echo '--placement_cloud=${CLOUD_NAME}' >> ${YB_HOME}/master/conf/server.conf"
TSERVER_CONF_CLOUDNAME="echo '--placement_cloud=${CLOUD_NAME}' >> ${YB_HOME}/tserver/conf/server.conf"
MASTER_CONF_REGIONNAME="echo '--placement_region=${REGION}' >> ${YB_HOME}/master/conf/server.conf"
TSERVER_CONF_REGIONNAME="echo '--placement_region=${REGION}' >> ${YB_HOME}/tserver/conf/server.conf"
if [ $num_zones -eq  1 ]; then
   MASTER_CONF_ZONENAME="echo '--placement_zone=${zone_array[0]}' >> ${YB_HOME}/master/conf/server.conf"
   TSERVER_CONF_ZONENAME="echo '--placement_zone=${zone_array[0]}' >> ${YB_HOME}/tserver/conf/server.conf"
fi

idx=0
for node in $SSH_IPS
do
  if [ $num_zones -gt 1 ]; then
     MASTER_CONF_ZONENAME="echo '--placement_zone=${zone_array[idx]}' >> ${YB_HOME}/master/conf/server.conf"
     TSERVER_CONF_ZONENAME="echo '--placement_zone=${zone_array[idx]}' >> ${YB_HOME}/tserver/conf/server.conf"
  fi
  ssh -o "StrictHostKeyChecking no" -i ${SSH_KEY_PATH} ${SSH_USER}@$node "$MASTER_CONF_CLOUDNAME ; $TSERVER_CONF_CLOUDNAME ; $MASTER_CONF_REGIONNAME ; $TSERVER_CONF_REGIONNAME ; $MASTER_CONF_ZONENAME ; $TSERVER_CONF_ZONENAME"
  idx=`expr $idx + 1`
done

###############################################################################
# Setup YSQL proxies across all nodes
###############################################################################
echo "Enabling YSQL..."
TSERVER_YSQL_PROXY_CMD="echo '--start_pgsql_proxy' >> ${YB_HOME}/tserver/conf/server.conf"
idx=0
for node in $SSH_IPS
do
  ssh -o "StrictHostKeyChecking no" -i ${SSH_KEY_PATH} ${SSH_USER}@$node "$TSERVER_YSQL_PROXY_CMD ; echo '--pgsql_proxy_bind_address=${MASTER_ADDR_ARRAY[idx]}:5433' >> ${YB_HOME}/tserver/conf/server.conf"
  idx=`expr $idx + 1`
done

###############################################################################
# Start the masters.
###############################################################################
echo "Starting masters..."
MASTER_EXE=${YB_HOME}/master/bin/yb-master
MASTER_OUT=${YB_HOME}/master/master.out
MASTER_ERR=${YB_HOME}/master/master.err
MASTER_START_CMD="nohup ${MASTER_EXE} --flagfile ${YB_HOME}/master/conf/server.conf >>${MASTER_OUT} 2>>${MASTER_ERR} </dev/null &"
for node in $SSH_IPS
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
SSH_IPS_array=($SSH_IPS)
echo "Initializing YSQL on node ${MASTER_ADDR_ARRAY[0]} via initdb..."

INITDB_CMD="YB_ENABLED_IN_POSTGRES=1 FLAGS_pggate_master_addresses=${YB_MASTER_ADDRESSES} ${YB_HOME}/tserver/postgres/bin/initdb -D /tmp/yb_pg_initdb_tmp_data_dir -U postgres >>${YB_HOME}/tserver/ysql.out"
ssh -o "StrictHostKeyChecking no" -i ${SSH_KEY_PATH} ${SSH_USER}@${SSH_IPS_array[0]} "$INITDB_CMD"
echo "YSQL initialization complete."

