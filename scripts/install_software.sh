#!/bin/bash

###############################################################################
#
# This is a simple script to install yugabyte-db software on a machine.
#
###############################################################################

YB_HOME=/home/ec2-user/yugabyte-db
if [[ $# -eq 3 ]]; then
   YB_EDITION=$1
   YB_VERSION=$2
   YB_DOWNLOAD_LOCATION=$3
   if [[ "${YB_EDITION}" == "ce" ]]; then
      YB_PACKAGE_URL="${YB_DOWNLOAD_LOCATION}/yugabyte-${YB_EDITION}-${YB_VERSION}-linux.tar.gz"
   fi
else
   YB_VERSION=1.2.8.0
   YB_PACKAGE_URL="https://downloads.yugabyte.com/yugabyte-ce-${YB_VERSION}-linux.tar.gz"
fi
YB_PACKAGE_NAME="${YB_PACKAGE_URL##*/}"

###############################################################################
# Create the necessary directories.
###############################################################################
mkdir -p ${YB_HOME}/yb-software
mkdir -p ${YB_HOME}/master
mkdir -p ${YB_HOME}/tserver

# Save the current directory.
pushd ${YB_HOME}

###############################################################################
# Set appropriate ulimits according to https://docs.yugabyte.com/latest/deploy/manual-deployment/system-config/#setting-ulimits
###############################################################################
echo "Setting appropriate YB ulimits.."

cat > /tmp/99-yugabyte-limits.conf <<EOF
ec2-user	soft 	core	unlimited
ec2-user	hard	core 	unlimited
ec2-user  	soft	data	unlimited
ec2-user	hard	data	unlimited
ec2-user	soft	priority	0
ec2-user	hard	priority	0
ec2-user	soft	fsize	unlimited
ec2-user	hard	fsize	unlimited
ec2-user	soft	sigpending	119934
ec2-user	hard	sigpending	119934
ec2-user	soft    memlock	64
ec2-user	hard 	memlock	64
ec2-user	soft  	nofile	1048576
ec2-user	hard  	nofile	1048576
ec2-user	soft	stack	8192
ec2-user	hard	stack	8192
ec2-user	soft	rtprio	0
ec2-user	hard	rtprio	0
ec2-user	soft	nproc	12000
ec2-user	hard	nproc	12000
EOF

sudo cp /tmp/99-yugabyte-limits.conf /etc/security/limits.d/99-yugabyte-limits.conf
###############################################################################
# Download and install the software.
###############################################################################
echo "Fetching package $YB_PACKAGE_URL..."
wget -q $YB_PACKAGE_URL

echo "Extracting package..."
tar zxvf ${YB_PACKAGE_NAME} > /dev/null

echo "Installing..."
mv yugabyte-${YB_VERSION} yb-software
yb-software/yugabyte-${YB_VERSION}/bin/post_install.sh 2>&1 > /dev/null


###############################################################################
# Install master.
###############################################################################
pushd master
for i in ../yb-software/yugabyte-${YB_VERSION}/*
do
  YB_TARGET_FILE="${i#../yb-software/yugabyte-${YB_VERSION}/}"
  if [[ ! -L "${YB_TARGET_FILE}" ]]; then
     ln -s $i > /dev/null
  else
     echo "rm -f ${YB_TARGET_FILE}" >> .master_relink
     echo "ln -s $i" >> .master_relink
  fi
done
mkdir -p conf
popd


###############################################################################
# Install tserver.
###############################################################################
pushd tserver
for i in ../yb-software/yugabyte-${YB_VERSION}/*
do
  YB_TARGET_FILE="${i#../yb-software/yugabyte-${YB_VERSION}/}"
  if [[ ! -L "${YB_TARGET_FILE}" ]]; then
     ln -s $i > /dev/null
  else
     echo "rm -f ${YB_TARGET_FILE}" >> .tserver_relink
     echo "ln -s $i" >> .tserver_relink
  fi
done
mkdir -p conf
popd


###############################################################################
# Create the data drives.
###############################################################################
mkdir -p ${YB_HOME}/data/disk0
mkdir -p ${YB_HOME}/data/disk1
if [[ ! -f master/conf/server.conf ]]; then
   echo "--fs_data_dirs=${YB_HOME}/data/disk0,${YB_HOME}/data/disk1" >> master/conf/server.conf
fi
if [[ ! -f tserver/conf/server.conf ]]; then
   echo "--fs_data_dirs=${YB_HOME}/data/disk0,${YB_HOME}/data/disk1" >> tserver/conf/server.conf
fi
# Restore the original directory.
popd

###############################################################################
# Create an environment file
###############################################################################
echo "YB_HOME=${YB_HOME}" >> ${YB_HOME}/.yb_env.sh
echo "export PATH='$PATH':${YB_HOME}/master/bin:${YB_HOME}/tserver/bin" >> ${YB_HOME}/.yb_env.sh
echo "export YB_EDITION=${YB_EDITION}" >> ${YB_HOME}/.yb_env.sh
echo "source ${YB_HOME}/.yb_env.sh" >> /home/ec2-user/.bash_profile
chmod 755 ${YB_HOME}/.yb_env.sh

