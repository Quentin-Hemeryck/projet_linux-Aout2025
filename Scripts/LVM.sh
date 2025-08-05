#!/bin/bash

# Vérification des privilèges root
if [[ $EUID -ne 0 ]]; then
    echo "Ce script doit être exécuté avec les privilèges root." >&2
    exit 1
fi

echo "[INFO] Configuration LVM et RAID"

# Installation des dépendances
sudo dnf install -y lvm2 mdadm

# Afficher les devices RAID existants
echo "[INFO] RAID existants :"
cat /proc/mdstat

# Lister les disques disponibles
echo "[INFO] Disques disponibles :"
lsblk -d -o NAME,SIZE,TYPE | grep disk

# Demander à l'utilisateur le nom du device RAID à créer
read -p "Nom du device RAID à créer (ex: md0, md1) : " RAID_NAME
RAID_DEVICE="/dev/$RAID_NAME"

# Demander à l'utilisateur les disques à utiliser
read -p "Entrez 2 disques pour le RAID 1 (ex: sdb sdc) : " DISKS
disk_count=$(echo $DISKS | wc -w)

if [ $disk_count -ne 2 ]; then
    echo "[ERROR] Le RAID 1 nécessite exactement 2 disques"
    exit 1
fi

RAID_DISKS=""
for disk in $DISKS; do
    RAID_DISKS="$RAID_DISKS /dev/$disk"
done

# Créer le RAID 1
echo "[INFO] Création du RAID 1..."
sudo mdadm --create --verbose $RAID_DEVICE --level=1 --raid-devices=2 $RAID_DISKS

# Configuration LVM
echo "[INFO] Configuration LVM..."
sudo pvcreate $RAID_DEVICE
sudo vgcreate vg_raid1 $RAID_DEVICE

# Création des volumes logiques
echo "[INFO] Création des volumes logiques..."
sudo lvcreate -L 500M -n nfs_share vg_raid1
sudo mkfs.ext4 /dev/vg_raid1/nfs_share
sudo mkdir -p /srv/nfs/share
sudo mount -o defaults /dev/vg_raid1/nfs_share /srv/nfs/share

UUID_NFS=$(blkid -s UUID -o value /dev/vg_raid1/nfs_share)
echo "UUID=$UUID_NFS /srv/nfs/share ext4 defaults 0 0" >> /etc/fstab

sudo lvcreate -L 500M -n web vg_raid1
sudo mkfs.ext4 /dev/vg_raid1/web
sudo mkdir -p /var/www
sudo mount -o defaults /dev/vg_raid1/web /var/www

UUID_WEB=$(blkid -s UUID -o value /dev/vg_raid1/web)
echo "UUID=$UUID_WEB /var/www ext4 defaults 0 0" >> /etc/fstab

sudo lvcreate -L 1G -n backup vg_raid1
sudo mkfs.ext4 /dev/vg_raid1/backup
sudo mkdir -p /backup
sudo mount -o defaults /dev/vg_raid1/backup /backup

UUID_BACKUP=$(blkid -s UUID -o value /dev/vg_raid1/backup)
echo "UUID=$UUID_BACKUP /backup ext4 defaults 0 0" >> /etc/fstab

# Sauvegarder la configuration RAID
sudo mdadm --detail --scan >> /etc/mdadm/mdadm.conf

sudo systemctl daemon-reload

echo "[INFO] Configuration terminée avec succès."