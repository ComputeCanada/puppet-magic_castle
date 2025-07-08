#!/bin/bash
echo "---"
echo \"/dev/disk\":
if [ -e /dev/disk ]; then
  for i in $(find /dev/disk -type l); do
    echo "  "\"$i\": \"$(readlink -f $i)\"
  done
fi
