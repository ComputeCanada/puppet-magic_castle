#!/bin/sh
echo "{ 'nvidia_grid_vgpu' : $(test -f /etc/nvidia/gridd.conf && echo true || echo false) }"