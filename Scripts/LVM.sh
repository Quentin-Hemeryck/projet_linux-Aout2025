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

# Détection automatique des disques non utilisés (excluant le disque système et ceux déjà en RAID)
USED_DISKS=$(cat /proc/mdstat | grep -o 'nvme[0-9]*n[0-9]*\|sd[a-z]*' | sort -u)
NVME_DISKS=$(lsblk -d -n -o NAME | grep -E '^nvme[0-9]+n[0-9]+$' | grep -v nvme0n1)
SATA_DISKS=$(lsblk -d -n -o NAME | grep -E '^sd[b-z]$')

# Filtrer les disques déjà utilisés dans RAID
AVAILABLE_DISKS=""
for disk in $NVME_DISKS $SATA_DISKS; do
    if ! echo "$USED_DISKS" | grep -q "$disk"; then
        AVAILABLE_DISKS="$AVAILABLE_DISKS $disk"
    fi
done

disk_count=$(echo $AVAILABLE_DISKS | wc -w)

if [ $disk_count -lt 2 ]; then
    echo "[WARNING] Pas assez de disques disponibles pour créer un nouveau RAID 1"
    echo "[INFO] Vérification des RAID existants..."
    
    # Utiliser le RAID existant s'il y en a un
    EXISTING_RAID=$(ls /dev/md* 2>/dev/null | head -1)
    if [ -n "$EXISTING_RAID" ]; then
        echo "[INFO] Utilisation du RAID existant: $EXISTING_RAID"
        RAID_DEVICE="$EXISTING_RAID"
        SKIP_RAID_CREATION=true
    else
        echo "[ERROR] Aucun RAID disponible"
        exit 1
    fi
else
    DISK_ARRAY=($AVAILABLE_DISKS)
    DISK1=${DISK_ARRAY[0]}
    DISK2=${DISK_ARRAY[1]}
    SKIP_RAID_CREATION=false
fi

if [ "$SKIP_RAID_CREATION" = false ]; then
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

    # Création du RAID si non existant
    if [ ! -e "$RAID_DEVICE" ]; then
        echo "[INFO] Création du RAID $RAID_NAME..."
        sudo mdadm --create --verbose $RAID_DEVICE --level=1 --raid-devices=2 $RAID_DISKS
        
        # Créer le répertoire mdadm s'il n'existe pas
        sudo mkdir -p /etc/mdadm
        sudo mdadm --detail --scan >> /etc/mdadm/mdadm.conf
    else
        echo "[INFO] RAID $RAID_DEVICE déjà présent, utilisation existante."
    fi
fi

# Configuration LVM
echo "[INFO] Configuration LVM..."
if ! pvs | grep -q "$RAID_DEVICE"; then
    sudo pvcreate $RAID_DEVICE
fi
if ! vgs | grep -q "vg_raid1"; then
    sudo vgcreate vg_raid1 $RAID_DEVICE
fi

# Création des volumes logiques + montage
echo "[INFO] Création des volumes logiques..."

if ! lvs | grep -q "nfs_share"; then
    sudo lvcreate -L 500M -n nfs_share vg_raid1
    sudo mkfs.ext4 /dev/vg_raid1/nfs_share
fi
sudo mkdir -p /srv/nfs/share
UUID_NFS=$(blkid -s UUID -o value /dev/vg_raid1/nfs_share)
grep -q "$UUID_NFS" /etc/fstab || echo "UUID=$UUID_NFS /srv/nfs/share ext4 defaults,usrquota,grpquota 0 0" >> /etc/fstab
sudo mount /srv/nfs/share 2>/dev/null || sudo mount -o remount,usrquota,grpquota /srv/nfs/share

if ! lvs | grep -q "web"; then
    sudo lvcreate -L 500M -n web vg_raid1
    sudo mkfs.ext4 /dev/vg_raid1/web
fi
sudo mkdir -p /var/www
UUID_WEB=$(blkid -s UUID -o value /dev/vg_raid1/web)
grep -q "$UUID_WEB" /etc/fstab || echo "UUID=$UUID_WEB /var/www ext4 defaults,usrquota,grpquota 0 0" >> /etc/fstab
sudo mount /var/www 2>/dev/null || sudo mount -o remount,usrquota,grpquota /var/www

# Assurer la présence du DocumentRoot par défaut
sudo mkdir -p /var/www/html
sudo chown apache:apache /var/www/html
sudo chmod 755 /var/www/html

# (Optionnel) Créer une page de test
echo "<h1>Apache fonctionne !</h1>" | sudo tee /var/www/html/index.html > /dev/null

if ! lvs | grep -q "backup"; then
    sudo lvcreate -L 1G -n backup vg_raid1
    sudo mkfs.ext4 /dev/vg_raid1/backup
fi
sudo mkdir -p /backup
UUID_BACKUP=$(blkid -s UUID -o value /dev/vg_raid1/backup)
grep -q "$UUID_BACKUP" /etc/fstab || echo "UUID=$UUID_BACKUP /backup ext4 defaults 0 0" >> /etc/fstab
sudo mount /backup 2>/dev/null || true

sudo systemctl daemon-reload

# Remontage avec quotas avant initialisation
echo "[INFO] Remontage avec quotas..."
sudo mount -o remount,usrquota,grpquota /var/www
sudo mount -o remount,usrquota,grpquota /srv/nfs/share

# Initialiser les quotas
echo "[INFO] Initialisation des quotas..."
# Désactiver les quotas temporairement s'ils sont actifs
sudo quotaoff /var/www 2>/dev/null || true
sudo quotaoff /srv/nfs/share 2>/dev/null || true

# Forcer la vérification des quotas (création des fichiers quota)
sudo quotacheck -cufm /var/www
sudo quotacheck -cufm /srv/nfs/share

# Créer les fichiers de quotas de groupe s'ils n'existent pas
sudo quotacheck -cugm /var/www 2>/dev/null || true
sudo quotacheck -cugm /srv/nfs/share 2>/dev/null || true

# Réactiver les quotas
sudo quotaon /var/www 2>/dev/null || echo "[WARNING] Quota utilisateur activé pour /var/www, groupe ignoré si inexistant"
sudo quotaon /srv/nfs/share 2>/dev/null || echo "[WARNING] Quota utilisateur activé pour /srv/nfs/share, groupe ignoré si inexistant"

echo "[INFO] Configuration terminée avec succès."
