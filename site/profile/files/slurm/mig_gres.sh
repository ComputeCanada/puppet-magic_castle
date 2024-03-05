#!/bin/bash
nvidia-smi mig -lgi | grep -oP "([0-9]+)\s*MIG ([\w.]+)\s*[0-9]*\s*([0-9]*)" | awk '{print $1,$3,$5}' | while read i MIG_PROFILE GPU_ID; do 
    echo "Name=gpu" Type=${MIG_PROFILE} MultipleFiles=/dev/nvidia${i},/dev/nvidia-caps/nvidia-cap$(cat /proc/driver/nvidia/capabilities/gpu${i}/mig/gi${GPU_ID}/access | grep -oP 'DeviceFileMinor: \K([0-9]+)')
done