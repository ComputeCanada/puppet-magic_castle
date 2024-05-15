#!/bin/bash

/usr/bin/nvidia-smi --query-gpu=index,mig.mode.current --format=csv,noheader | sed 's/,//' | while read GPU_INDEX MIG_ENABLED; do
    if [ "${MIG_ENABLED}" == "Enabled" ]; then
        /usr/bin/nvidia-smi mig -lgi -i ${GPU_INDEX} | grep MIG | awk '{gsub("[|]", ""); print $3,$5}' | while read MIG_PROFILE MIG_ID; do
            GPU_CAP_ID=$(grep -oP 'DeviceFileMinor: \K([0-9]+)' /proc/driver/nvidia/capabilities/gpu${GPU_INDEX}/mig/gi${MIG_ID}/access)
            echo "Name=gpu Type=${MIG_PROFILE} MultipleFiles=/dev/nvidia${GPU_INDEX},/dev/nvidia-caps/nvidia-cap${GPU_CAP_ID}"
        done
    else
        GPU_TYPE=$(/usr/bin/nvidia-smi -i ${GPU_INDEX} --query-gpu=gpu_name --format=csv,noheader | awk '{print $2}')
        echo "Name=gpu Type=${GPU_TYPE} File=/dev/nvidia${GPU_INDEX}"
    fi
done
