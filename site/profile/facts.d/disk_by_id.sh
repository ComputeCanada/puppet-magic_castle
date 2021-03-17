#!/bin/bash

echo "{ 'disk_links' : {"
for i in $(find /dev/disk -type l); do
  echo \"$i\":\"$(readlink -f $i)\";
done  | paste -sd,
echo '}}'