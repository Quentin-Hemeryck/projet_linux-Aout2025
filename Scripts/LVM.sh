#!/bin/bash

# Vérification des privilèges root
if [[ $EUID -ne 0 ]]; then
    echo "Ce script doit être exécuté avec les privilèges root." >&2
    exit 1
fi

echo "[INFO] Configuration LVM et RAID"

# Installation des dépendances
sudo dnf install -y lvm2 mdadm

# Vérifier si la configuration existe déjà
if vgs vg_raid1 &>/dev/null; then
    echo "[INFO] Configuration LVM déjà existante - Script terminé"
    exit 0
fi

# Afficher les devices RAID existants
echo "[INFO] RAID existants :"
cat /proc/mdstat

# Lister les disques disponibles
echo "[INFO] Disques disponibles :"
lsblk -d -o NAME,SIZE,TYPE | grep disk

# Détection automatique des disques non utilisés (excluant le disque système)
# Détecter les disques NVMe et SCSI/SATA disponibles
NVME_DISKS=$(lsblk -d -n -o NAME | grep -E '^nvme[0-9]+n[0-9]+$' | grep -v nvme0n1 | head -2)
SATA_DISKS=$(lsblk -d -n -o NAME | grep -E '^sd[b-z]$' | head -2)

# Utiliser les disques NVMe en priorité, sinon les disques SATA
if [ -n "$NVME_DISKS" ]; then
    AVAILABLE_DISKS=$NVME_DISKS
else
    AVAILABLE_DISKS=$SATA_DISKS
fi

disk_count=$(echo $AVAILABLE_DISKS | wc -w)

if [ $disk_count -lt 2 ]; then
    echo "[ERROR] Pas assez de disques disponibles pour créer un RAID 1"
    echo "[INFO] Disques NVMe détectés: $NVME_DISKS"
    echo "[INFO] Disques SATA détectés: $SATA_DISKS"
    echo "[INFO] Disques sélectionnés: $AVAILABLE_DISKS"
    echo "[INFO] Nombre de disques: $disk_count"
    exit 1
fi

# Utiliser les 2 premiers disques disponibles
DISK_ARRAY=($AVAILABLE_DISKS)
DISK1=${DISK_ARRAY[0]}
DISK2=${DISK_ARRAY[1]}

echo "[INFO] Utilisation des disques: $DISK1 et $DISK2"

# Déterminer automatiquement le prochain device RAID disponible
RAID_NAME="md0"
if [ -e "/dev/md0" ]; then
    RAID_NAME="md1"
    if [ -e "/dev/md1" ]; then
        RAID_NAME="md2"
    fi
fi

RAID_DEVICE="/dev/$RAID_NAME"
RAID_DISKS="/dev/$DISK1 /dev/$DISK2"

echo "[INFO] Création du RAID $RAID_NAME avec les disques $DISK1 et $DISK2"

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
echo "UUID=$UUID_NFS /srv/nfs/share ext4 defaults,usrquota,grpquota 0 0" >> /etc/fstab

sudo lvcreate -L 500M -n web vg_raid1
sudo mkfs.ext4 /dev/vg_raid1/web
sudo mkdir -p /var/www
sudo mount -o defaults /dev/vg_raid1/web /var/www

UUID_WEB=$(blkid -s UUID -o value /dev/vg_raid1/web)
echo "UUID=$UUID_WEB /var/www ext4 defaults,usrquota,grpquota 0 0" >> /etc/fstab

sudo lvcreate -L 1G -n backup vg_raid1
sudo mkfs.ext4 /dev/vg_raid1/backup
sudo mkdir -p /backup
sudo mount -o defaults /dev/vg_raid1/backup /backup

UUID_BACKUP=$(blkid -s UUID -o value /dev/vg_raid1/backup)
echo "UUID=$UUID_BACKUP /backup ext4 defaults 0 0" >> /etc/fstab

# Sauvegarder la configuration RAID
sudo mdadm --detail --scan >> /etc/mdadm/mdadm.conf

sudo systemctl daemon-reload

# Initialiser les quotas
echo "[INFO] Initialisation des quotas..."
sudo quotacheck -cum /var/www
sudo quotacheck -cum /srv/nfs/share
sudo quotaon /var/www
sudo quotaon /srv/nfs/share

echo "[INFO] Configuration terminée avec succès."