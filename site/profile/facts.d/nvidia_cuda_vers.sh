#!/bin/sh
CUDA_VERSION=$(rpm -q cuda-repo-rhel7 | sed -n "s/cuda-repo-rhel7-\(.*\)\.x86_64/\1/p")
if [ -z $CUDA_VERSION ]; then
    CUDA_VERSION=$(curl -s http://developer.download.nvidia.com/compute/cuda/repos/rhel7/x86_64/ |
sed -n "s/^.*'cuda-repo-rhel7-\(.*\)\.x86_64\.rpm'.*$/\1/p" |
tail -n1)
fi
echo "{ 'nvidia_cuda_version' : ${CUDA_VERSION} }"