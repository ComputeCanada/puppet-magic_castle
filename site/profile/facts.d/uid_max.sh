#!/bin/sh

echo "{ 'uid_max': $(grep -Po '^UID_MAX\s+\K(\d+)$' /etc/login.defs) }"