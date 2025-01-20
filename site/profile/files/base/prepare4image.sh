#!/bin/bash -e
systemctl stop puppet
systemctl stop slurmd &> /dev/null || true
systemctl stop consul &> /dev/null || true
systemctl stop consul-template &> /dev/null || true
systemctl disable puppet
systemctl disable slurmd &> /dev/null || true
systemctl disable consul &> /dev/null || true
systemctl disable consul-template &> /dev/null || true

/sbin/ipa-client-install -U --uninstall
rm -f /var/log/ipaclient-uninstall.log
rm -f /var/log/ipaclient-install.log
rm -rf /etc/sssd/sssd.conf.deleted

rm -rf /etc/puppetlabs
rm -rf /opt/puppetlabs/puppet/cache/{clientbucket,client_data,client_yaml,state}
rm /opt/consul/node-id /opt/consul/checkpoint-signature /opt/consul/serf/local.snapshot

# Turn off swap
swapoff -a
grep -q "swap" /etc/fstab && rm -f $(grep "swap" /etc/fstab | cut -f 1)
# Unmount filesystems
umount -a --types cephfs,nfs4
# for xfs, we unmount only what's in /mnt, not things like / or /boot
grep xfs /etc/fstab | cut -f 2 | grep /mnt | xargs --no-run-if-empty umount
grep -P '(ext4|xfs|vfat|^#|^$)' /etc/fstab | grep -v /mnt > /etc/fstab.new
mv -f /etc/fstab.new /etc/fstab
systemctl daemon-reload

systemctl stop rsyslog
: > /var/log/messages
: > /var/log/munge/munged.log
: > /var/log/secure
: > /var/log/cron
: > /var/log/audit/audit.log

if [ -f /etc/cloud/cloud-init.disabled ]; then
  # This is for GCP where we install cloud-init on first boot
  rm /etc/cloud/cloud-init.disabled
  yum install -y cloud-init
  systemctl disable cloud-init
fi
cloud-init clean --logs
rm -rf /var/lib/cloud

# Remove all internal domain host entries
grep -v $(hostname -d) /etc/hosts > /etc/hosts.clean
mv /etc/hosts.clean /etc/hosts

rm -f /etc/hostname
rm -f /etc/udev/rules.d/70-persistent-net.rules
: > /etc/sysconfig/network
: > /etc/machine-id

rm /etc/NetworkManager/conf.d/zzz-puppet.conf
: > /etc/resolv.conf

cat > /etc/sysconfig/network-scripts/ifcfg-eth0 << EOF
DEVICE=eth0
TYPE=Ethernet
ONBOOT=yes
BOOTPROTO=dhcp
EOF
halt -p
