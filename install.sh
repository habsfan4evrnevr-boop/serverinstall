#!/bin/bash
set -e

echo "=============================="
echo " ALL-IN-ONE SERVER INSTALLER "
echo "=============================="

# -----------------------------
# VARIABLES
# -----------------------------
VM_NAME="Windows11"
VM_DIR="/var/vms/$VM_NAME"
ISO_DIR="/var/isos"
ISO_FILE="$ISO_DIR/win11.iso"

# -----------------------------
# UPDATE SYSTEM
# -----------------------------
echo "[+] Updating system..."
dnf update -y

# -----------------------------
# INSTALL BASE PACKAGES
# -----------------------------
echo "[+] Installing base packages..."
dnf install -y epel-release wget curl nano git firewalld net-tools

systemctl enable firewalld
systemctl start firewalld

# -----------------------------
# INSTALL JELLYFIN
# -----------------------------
echo "[+] Installing Jellyfin..."
dnf install -y https://repo.jellyfin.org/releases/server/centos/jellyfin-release.rpm
dnf install -y jellyfin
systemctl enable jellyfin
systemctl start jellyfin
firewall-cmd --add-port=8096/tcp --permanent

# -----------------------------
# INSTALL XAMPP
# -----------------------------
echo "[+] Installing XAMPP..."
wget -O /tmp/xampp.run https://www.apachefriends.org/xampp-files/latest/xampp-linux-x64-installer.run
chmod +x /tmp/xampp.run
/tmp/xampp.run --mode unattended
/opt/lampp/lampp start

firewall-cmd --add-port=80/tcp --permanent
firewall-cmd --add-port=443/tcp --permanent

# -----------------------------
# INSTALL ICECAST
# -----------------------------
echo "[+] Installing Icecast..."
dnf install -y icecast
systemctl enable icecast
systemctl start icecast
firewall-cmd --add-port=8000/tcp --permanent

# -----------------------------
# INSTALL VIRTUALBOX
# -----------------------------
echo "[+] Installing VirtualBox..."
dnf install -y @development-tools kernel-devel kernel-headers dkms
dnf config-manager --add-repo https://download.virtualbox.org/virtualbox/rpm/el/virtualbox.repo
dnf install -y VirtualBox-7.0
/sbin/vboxconfig || true

# -----------------------------
# DOWNLOAD WINDOWS 11 ISO
# -----------------------------
echo "[+] Downloading Windows 11 ISO..."
mkdir -p $ISO_DIR
cd $ISO_DIR

wget -O win11.iso https://software-download.microsoft.com/db/Win11_23H2_English_x64.iso || echo "ISO download may fail, add manually"

# -----------------------------
# CREATE VM
# -----------------------------
echo "[+] Creating Virtual Machine..."
mkdir -p $VM_DIR

VBoxManage createvm --name "$VM_NAME" --ostype Windows11_64 --register

VBoxManage modifyvm "$VM_NAME" \
  --memory 8192 \
  --cpus 4 \
  --vram 128 \
  --nic1 nat \
  --firmware efi

VBoxManage createmedium disk \
  --filename "$VM_DIR/$VM_NAME.vdi" \
  --size 102400

VBoxManage storagectl "$VM_NAME" --name "SATA Controller" --add sata --controller IntelAhci
VBoxManage storageattach "$VM_NAME" --storagectl "SATA Controller" --port 0 --device 0 --type hdd --medium "$VM_DIR/$VM_NAME.vdi"

VBoxManage storagectl "$VM_NAME" --name "IDE Controller" --add ide
VBoxManage storageattach "$VM_NAME" --storagectl "IDE Controller" --port 0 --device 0 --type dvddrive --medium "$ISO_FILE"

# -----------------------------
# START VM
# -----------------------------
echo "[+] Starting Windows VM..."
VBoxManage startvm "$VM_NAME" --type headless

# -----------------------------
# SETUP DATABASE (XAMPP MYSQL)
# -----------------------------
echo "[+] Setting up database..."
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
VALUES ('admin', MD5('admin123'), 'admin');
EOF

# -----------------------------
# CREATE DASHBOARD
# -----------------------------
echo "[+] Creating web dashboard..."

mkdir -p /opt/lampp/htdocs/dashboard

cat <<'EOF' > /opt/lampp/htdocs/dashboard/login.php
<?php
session_start();
$conn = new mysqli("localhost","root","","dashboard");

if($_SERVER['REQUEST_METHOD'] == 'POST'){
  $user = $_POST['username'];
  $pass = md5($_POST['password']);

  $res = $conn->query("SELECT * FROM users WHERE username='$user' AND password='$pass'");

  if($res->num_rows > 0){
    $_SESSION['user'] = $user;
    header("Location: index.php");
  } else {
    echo "Login failed";
  }
}
?>
<form method="POST">
<input name="username" placeholder="Username"><br>
<input name="password" type="password" placeholder="Password"><br>
<button type="submit">Login</button>
</form>
EOF

cat <<'EOF' > /opt/lampp/htdocs/dashboard/index.php
<?php
session_start();
if(!isset($_SESSION['user'])) header("Location: login.php");
?>

<h1>Server Dashboard</h1>

<h2>Services</h2>
<ul>
<li><a href="http://localhost:8096">Jellyfin</a></li>
<li><a href="http://localhost">Web Server</a></li>
<li><a href="http://localhost:8000">Icecast</a></li>
</ul>

<h2>System Info</h2>
<pre><?php echo shell_exec("uptime"); ?></pre>

<h2>VMs</h2>
<pre><?php echo shell_exec("VBoxManage list runningvms"); ?></pre>
EOF

# -----------------------------
# PERMISSIONS
# -----------------------------
echo "apache ALL=(ALL) NOPASSWD: /opt/lampp/lampp" >> /etc/sudoers

# -----------------------------
# FINALIZE FIREWALL
# -----------------------------
firewall-cmd --reload

IP=$(hostname -I | awk '{print $1}')

echo "=================================="
echo " INSTALL COMPLETE"
echo "=================================="
echo "Dashboard: http://$IP/dashboard"
echo "Jellyfin:  http://$IP:8096"
echo "Icecast:   http://$IP:8000"
echo "=================================="
