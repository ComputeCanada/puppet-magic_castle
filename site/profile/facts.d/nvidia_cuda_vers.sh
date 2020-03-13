#!/bin/sh
PROCESSOR=$(uname -p)
VERSION="$(source /etc/os-release; echo $VERSION_ID)"
PACKAGE="cuda-repo-rhel${VERSION}"
PACKAGE_REGEX="${PACKAGE}-\(.*\)\.${PROCESSOR}"
CUDA_VERSION=$(rpm -q ${PACKAGE} | sed -n "s/${PACKAGE_REGEX}/\1/p")
if [ -z $DRIVER_VERSION ]; then
    BASE_URL="http://developer.download.nvidia.com/compute/cuda/repos"
    CUDA_REPO_GZ=$(curl -s ${BASE_URL}/rhel${VERSION}/${PROCESSOR}/repodata/repomd.xml | sed '2 s/xmlns=".*"//g' | xmllint --xpath 'string(/repomd/data[@type="primary"]/location/@href)' -)
    CUDA_VERSION=$(curl -s ${BASE_URL}/rhel${VERSION}/${PROCESSOR}/${CUDA_REPO_GZ} | gunzip | sed -n "s/^.*\"${PACKAGE_REGEX}\.rpm\".*$/\1/p" | sort -V | tail -n1)
fi

echo "{ 'nvidia_cuda_version' : '${CUDA_VERSION}' }"