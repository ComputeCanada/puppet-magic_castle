#!/bin/sh
echo "{ 'nvidia_grid_vgpu' : $(curl -s http://169.254.169.254/2009-04-04/meta-data/instance-type | grep -q ^vgpu && echo true || echo false) }"