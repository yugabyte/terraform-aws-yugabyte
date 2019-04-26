#!/bin/bash

###############################################################################
#
# This is a simple script to install yugabyte-db software on a machine.
#
###############################################################################

YB_HOME=/home/ec2-user/yugabyte-db
YB_VERSION=1.2.6.0
YB_PACKAGE_URL="https://downloads.yugabyte.com/yugabyte-ce-${YB_VERSION}-linux.tar.gz"

###############################################################################
# Create the necessary directories.
###############################################################################
mkdir -p ${YB_HOME}/yb-software
mkdir -p ${YB_HOME}/master
mkdir -p ${YB_HOME}/tserver

# Save the current directory.
pushd ${YB_HOME}


###############################################################################
# Download and install the software.
###############################################################################
echo "Fetching package $YB_PACKAGE_URL..."
wget -q $YB_PACKAGE_URL

echo "Extracting package..."
tar zxvf yugabyte-ce-${YB_VERSION}-linux.tar.gz > /dev/null

echo "Installing..."
mv yugabyte-${YB_VERSION} yb-software
yb-software/yugabyte-${YB_VERSION}/bin/post_install.sh 2>&1 > /dev/null


###############################################################################
# Install master.
###############################################################################
pushd master
for i in ../yb-software/yugabyte-${YB_VERSION}/*
do
  ln -s $i > /dev/null
done
mkdir conf
popd


###############################################################################
# Install tserver.
###############################################################################
pushd tserver
for i in ../yb-software/yugabyte-${YB_VERSION}/*
do
  ln -s $i > /dev/null
done
mkdir conf
popd


###############################################################################
# Create the data drives.
###############################################################################
mkdir -p ${YB_HOME}/data/disk0
mkdir -p ${YB_HOME}/data/disk1
echo "--fs_data_dirs=${YB_HOME}/data/disk0,${YB_HOME}/data/disk1" >> master/conf/server.conf
echo "--fs_data_dirs=${YB_HOME}/data/disk0,${YB_HOME}/data/disk1" >> tserver/conf/server.conf

# Restore the original directory.
popd
