#!/bin/sh

# NVIDIA Vendor ID is : 0x10de
# Grep the GPU memory size from the product description and convert to bytes
GPU_MEM_SIZE=$(/usr/sbin/lspci -d 10de: | grep -oP '\[*\K[0-9]*[T|G](?=B)' | numfmt --from=iec)
# Grep the actual GPU memory size from lspci verbose and convert to bytes
AVAIL_MEM_SIZE=$(/usr/sbin/lspci -d 10de: -v | grep -oP 'Memory.*\(64-bit, prefetchable\).*\[size=\K([0-9]*[T|G])(?=])' | numfmt --from=iec)

# If the memory available from the product description is greater than the available memory
# we conclude it must be a virtual GPU
if [[ ! -z "${GPU_MEM_SIZE}" ]] && [[ ! -z "${AVAIL_MEM_SIZE}" ]]; then
    IS_VGPU=$(test "${GPU_MEM_SIZE}" -gt "${AVAIL_MEM_SIZE}" && echo true || echo false)
else
    IS_VGPU='false'
fi

echo "{ 'nvidia_grid_vgpu' : $IS_VGPU }"