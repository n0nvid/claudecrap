#!/bin/bash
# Mounts the host E:\remnux (VMware shared folder "evidence") at /mnt/evidence at every boot.
exec > /tmp/share.log 2>&1
echo malware | sudo -S -p '' true
sudo mkdir -p /mnt/evidence
grep -q '^.host:/evidence ' /etc/fstab || echo '.host:/evidence /mnt/evidence fuse.vmhgfs-fuse allow_other,uid=1000,gid=1000,nofail,defaults 0 0' | sudo tee -a /etc/fstab
sudo systemctl daemon-reload
sudo mount /mnt/evidence
echo "== mount"; mount | grep /mnt/evidence
echo "written from REMnux $(date -Is)" > /mnt/evidence/hello-from-remnux.txt && echo "== write OK"
ls -la /mnt/evidence
