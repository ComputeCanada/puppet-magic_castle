#!/bin/bash
echo "{ 'nvidia_gpu_count' : $(lspci | grep -c -i nvidia) }"