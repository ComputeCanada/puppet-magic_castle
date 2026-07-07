#!/bin/sh
is_unprivileged_container=$(test "nobody" == $(stat -c "%U" /proc/) && echo true || echo false)
echo "---"
echo "is_unprivileged_container: ${is_unprivileged_container}"
