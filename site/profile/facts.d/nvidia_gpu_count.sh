#!/bin/bash
# NVIDIA vendor id is 0x10de
# List all devides with that vendor id then count the number of lines
echo "{ 'nvidia_gpu_count' : $(lspci -d 0x10de: | wc -l) }"