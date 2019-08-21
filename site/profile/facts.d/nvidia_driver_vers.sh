#!/bin/sh
if lspci | grep -q -i nvidia; then
    DRIVER_VERSION=$(rpm -q nvidia-driver-libs | sed -n "s/nvidia-driver-libs-\([0-9.]\{1,\}\)[-0-9]*.el7\.x86_64/\1/p")
    if [ -z $DRIVER_VERSION ]; then
        DRIVER_VERSION=$(curl -s http://developer.download.nvidia.com/compute/cuda/repos/rhel7/x86_64/ |
sed -n "s/^.*'nvidia-driver-latest-libs-\([0-9.]\{1,\}\)[-0-9]*.el7\.x86_64\.rpm'.*$/\1/p")
    fi
    echo "{ 'nvidia_driver_version' : ${DRIVER_VERSION} }"
fi