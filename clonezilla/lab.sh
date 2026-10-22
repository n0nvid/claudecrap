#!/bin/bash
# Unattended save/restore of the Windows partition, run by Clonezilla live (ocs_live_run).
# The mode comes from lab/mode on this partition, written by SaveBaseline.ps1 / RestoreLab.ps1.
# Partitions are found by GPT partition GUID, so device names don't matter.

WIN_PARTUUID=df4f92b2-a105-4306-a373-08038104ef04   # C:
IMG_PARTUUID=3dda29dd-a922-4b22-80a1-c82550ef49ab   # image partition (ext4, invisible to Windows)
IMG=lab-clean
MEDIUM=/run/live/medium
REPO=/home/partimag

fail() {
  echo
  echo "*** FAILED: $* ***"
  echo "Nothing else was changed. Rebooting into Windows in 10 minutes, or press Enter now."
  read -t 600 _
  sudo reboot
  exit 1
}

# After a save, switch back to restore so an accidental boot here can never save an infected image.
set_mode_restore() {
  sudo mount -o remount,rw $MEDIUM && echo restore | sudo tee $MEDIUM/lab/mode >/dev/null
  sync
}

mode=$(tr -dc 'a-z' < $MEDIUM/lab/mode 2>/dev/null)
[ -n "$mode" ] || mode=restore
win=$(readlink -f /dev/disk/by-partuuid/$WIN_PARTUUID)
img=$(readlink -f /dev/disk/by-partuuid/$IMG_PARTUUID)
[ -b "$win" ] || fail "Windows partition $WIN_PARTUUID not found"
[ -b "$img" ] || fail "Image partition $IMG_PARTUUID not found"
echo "=== Lab $mode: Windows=$win  images=$img ==="

if [ "$(sudo blkid -o value -s TYPE $img)" != ext4 ]; then
  [ "$mode" = save ] || fail "The image partition is empty - run SaveBaseline first"
  sudo mkfs.ext4 -F -L LabImages $img || fail "mkfs.ext4 $img"
fi
sudo mkdir -p $REPO
sudo mount $img $REPO || fail "mount $img"

case $mode in
  save)
    # Save to a new name first; the previous good image is only replaced once this one succeeds.
    sudo rm -rf $REPO/$IMG.new
    sudo ocs-sr -b -q2 -z9p -sfsck -senc -gs -p true saveparts $IMG.new ${win#/dev/} || fail "save"
    sudo rm -rf $REPO/$IMG.prev
    [ -d $REPO/$IMG ] && sudo mv $REPO/$IMG $REPO/$IMG.prev
    sudo mv $REPO/$IMG.new $REPO/$IMG
    set_mode_restore
    ;;
  restore)
    [ -d $REPO/$IMG ] || fail "No saved image - run SaveBaseline first"
    # -k: keep the existing partition table. Without it, restoreparts recreates the whole
    # disk's partition table from the image (and refuses here because CZLAB/Images are mounted).
    sudo ocs-sr -b -k -cs -p true restoreparts $IMG ${win#/dev/} || fail "restore - see the Clonezilla messages above"
    ;;
  *)
    fail "unknown mode '$mode'"
    ;;
esac

sync
sudo umount $REPO
echo "=== Lab $mode finished. Rebooting into Windows. ==="
sleep 5
sudo reboot
