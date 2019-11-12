#!/bin/sh
cpu_ext=$(grep -m1 flags /proc/cpuinfo | tr " " "\n" | tac | grep -m 1 -P '^(avx512f|avx2|avx|pni)$')
case "$cpu_ext" in
    avx512f)
        cpu_ext="avx512"
        ;;
    pni)
        cpu_ext="sse3"
        ;;
esac
echo "{ 'cpu_ext' : '${cpu_ext}' }"