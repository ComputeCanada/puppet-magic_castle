#!/bin/bash
TOKEN=$(/var/www/userportal-env/bin/python /var/www/userportal/manage.py drf_create_token root | awk '{print $3}')
echo "[api]
token = ${TOKEN}
host = http://localhost:8001
script_length = 100000
[slurm]
spool = /var/spool/slurm" > /etc/slurm/slurm_jobscripts.ini
chmod 600 /etc/slurm/slurm_jobscripts.ini
chown slurm:slurm /etc/slurm/slurm_jobscripts.ini
