#!/bin/bash
set -e

echo "======================================"
echo " ALL-IN-ONE SERVER INSTALLER - ROCKY 9 "
echo "======================================"

# -----------------------------
# VARIABLES
# -----------------------------
VM_NAME="Win11VM"
VM_DIR="/var/vms/$VM_NAME"
ISO_DIR="/var/isos"
ISO_FILE="$ISO_DIR/Win11.iso"

# -----------------------------
# UPDATE SYSTEM
# -----------------------------
dnf -y update

# -----------------------------
# BASE PACKAGES
# -----------------------------
dnf install -y epel-release wget curl git nano firewalld unzip net-tools bzip2
systemctl enable --now firewalld

# -----------------------------
# JELLYFIN
# -----------------------------
cat <<EOF > /etc/yum.repos.d/jellyfin.repo
[jellyfin]
name=Jellyfin
baseurl=https://repo.jellyfin.org/releases/server/centos/stable/
enabled=1
gpgcheck=0
EOF

dnf install -y jellyfin
systemctl enable --now jellyfin
firewall-cmd --add-port=8096/tcp --permanent

# -----------------------------
# XAMPP
# -----------------------------
cd /tmp
wget -O xampp.run https://www.apachefriends.org/xampp-files/latest/xampp-linux-x64-installer.run
chmod +x xampp.run
./xampp.run --mode unattended
/opt/lampp/lampp start
firewall-cmd --add-port=80/tcp --permanent
firewall-cmd --add-port=443/tcp --permanent

# -----------------------------
# ICECAST
# -----------------------------
dnf install -y icecast
systemctl enable --now icecast
firewall-cmd --add-port=8000/tcp --permanent

# -----------------------------
# VIRTUALBOX
# -----------------------------
dnf install -y @development-tools kernel-devel kernel-headers dkms
dnf config-manager --add-repo https://download.virtualbox.org/virtualbox/rpm/el/virtualbox.repo
dnf install -y VirtualBox-7.0
/sbin/vboxconfig || true

# -----------------------------
# WINDOWS 11 ISO AUTO-DOWNLOAD
# -----------------------------
mkdir -p $ISO_DIR
if [ ! -f "$ISO_FILE" ]; then
  echo "[✓] Downloading Windows 11 ISO..."
  wget -O "$ISO_FILE" "https://software-download.microsoft.com/db/Win11_22H2_English_x64.iso?t=YOUR_TEMP_LINK_HERE"
  echo "[✓] Download complete: $ISO_FILE"
fi

# -----------------------------
# CREATE VM
# -----------------------------
mkdir -p $VM_DIR
VBoxManage createvm --name "$VM_NAME" --ostype Windows11_64 --register
VBoxManage modifyvm "$VM_NAME" --memory 8192 --cpus 4 --nic1 nat --firmware efi
VBoxManage createmedium disk --filename "$VM_DIR/$VM_NAME.vdi" --size 102400
VBoxManage storagectl "$VM_NAME" --name "SATA" --add sata
VBoxManage storageattach "$VM_NAME" --storagectl "SATA" --port 0 --device 0 --type hdd --medium "$VM_DIR/$VM_NAME.vdi"
VBoxManage storagectl "$VM_NAME" --name "IDE" --add ide
VBoxManage storageattach "$VM_NAME" --storagectl "IDE" --port 0 --device 0 --type dvddrive --medium "$ISO_FILE"
VBoxManage startvm "$VM_NAME" --type headless

# -----------------------------
# DATABASE
# -----------------------------
/opt/lampp/lampp startmysql
/opt/lampp/bin/mysql -u root <<EOF
CREATE DATABASE IF NOT EXISTS dashboard;
USE dashboard;
CREATE TABLE IF NOT EXISTS users (
  id INT AUTO_INCREMENT PRIMARY KEY,
  username VARCHAR(50),
  password VARCHAR(255),
  role ENUM('admin','manager','viewer')
);
INSERT INTO users (username,password,role)
VALUES ('admin', MD5('admin123'),'admin');
EOF

# -----------------------------
# DASHBOARD DEPLOYMENT
# -----------------------------
mkdir -p /opt/lampp/htdocs/dashboard
cp -r dashboard/* /opt/lampp/htdocs/dashboard/
echo "apache ALL=(ALL) NOPASSWD: /opt/lampp/lampp" >> /etc/sudoers

# -----------------------------
# FIREWALL RELOAD
# -----------------------------
firewall-cmd --reload

IP=$(hostname -I | awk '{print $1}')
echo "=================================="
echo " INSTALL COMPLETE "
echo " Dashboard: http://$IP/dashboard"
echo " Jellyfin: http://$IP:8096"
echo " Icecast:  http://$IP:8000"
echo "=================================="
