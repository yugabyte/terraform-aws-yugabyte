#!/usr/bin/env bash

set -o errexit -o pipefail

# Following file will modify to update YugabyteDB version
readonly FILE_TO_UPDATE="variables.tf"

# version_gt compares the given two versions.
# It returns 0 exit code if the version1 is greater than version2.
function version_gt() {
  test "$(echo -e "$1\n$2" | sort -V | head -n 1)" != "$1"
}

# Verify number of arguments
if [[ $# -ne 1 ]]; then
  echo "No arguments supplied. Please provide release version" 1>&2
  echo "Terminating the script execution." 1>&2
  exit 1
fi

release_version="$1"
echo "Release Version - ${release_version}"

# Verify release version
if ! [[ "${release_version}" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "Something wrong with the version. Release version format - *.*.*.*" 1>&2
  exit 1
fi

# Current Version in variables.tf
current_version="$(grep -A 2 "yb_version" "${FILE_TO_UPDATE}" | grep "default" | cut -d '"' -f 2)"
echo "Current Release Version - ${current_version}"

# Version comparison
if ! version_gt "${release_version}" "${current_version}" ; then
  echo "Release version is either older or equal to the current version: '${release_version}' <= '${current_version}'" 1>&2
  exit 1
fi

# Following parameter will be updated.
# 1. value: "2.1.4.0"

echo "Updating..."

# Update Version
sed -i -E "/^variable \"yb_version\"/,+2 s/[0-9]+.[0-9]+.[0-9]+.[0-9]+/"${release_version}"/" "${FILE_TO_UPDATE}"

echo "Completed"
