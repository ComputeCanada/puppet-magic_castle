#!/bin/sh
PROCESSOR=$(uname -p)
VERSION="$(source /etc/os-release; echo $VERSION_ID)"
PACKAGE="nvidia-driver-latest-dkms-cuda"
PACKAGE_REGEX="${PACKAGE}-\([0-9.]\{1,\}\)[-0-9]*.el${VERSION}\.${PROCESSOR}"
DRIVER_VERSION=$(test -f /usr/sbin/dkms && /usr/sbin/dkms status | grep -Po 'nvidia, \K(\d+.\d+[\.]\d*)')
if [ -z $DRIVER_VERSION ]; then
    BASE_URL="http://developer.download.nvidia.com/compute/cuda/repos"
    CUDA_REPO_GZ=$(curl -s ${BASE_URL}/rhel${VERSION}/${PROCESSOR}/repodata/repomd.xml | sed '2 s/xmlns=".*"//g' | xmllint --xpath 'string(/repomd/data[@type="primary"]/location/@href)' -)
    DRIVER_VERSION=$(curl -s ${BASE_URL}/rhel${VERSION}/${PROCESSOR}/${CUDA_REPO_GZ} | gunzip | sed -n "s/^.*\"${PACKAGE_REGEX}\.rpm\".*$/\1/p" | sort -V | tail -n1)
fi
echo "{ 'nvidia_driver_version' : '${DRIVER_VERSION}' }"