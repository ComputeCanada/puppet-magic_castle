#!/bin/bash
# AMD vendor id is 0x1002
# List all devides with that vendor id then count the number of lines
echo "{ 'amd_gpu_count' : $(lspci -d 0x1002: | wc -l) }"