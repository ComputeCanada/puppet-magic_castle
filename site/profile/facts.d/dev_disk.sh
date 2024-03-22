#!/bin/bash
echo \"/dev/disk:\"
for i in $(find /dev/disk -type l); do
  echo "  "\"$i\": \"$(readlink -f $i)\"
done
