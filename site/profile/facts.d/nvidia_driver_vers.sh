#!/bin/sh
if [ -e /proc/driver/nvidia ]; then
    DRIVER_VERSION=$(grep -m 1 -Po 'NVRM version:.* \K(\d+\.\d+\.\d+)' /proc/driver/nvidia/version)
fi
echo "{ 'nvidia_driver_version' : '${DRIVER_VERSION}' }"