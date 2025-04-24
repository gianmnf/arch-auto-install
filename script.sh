#!/bin/bash
set -e

# Prompt for username and passwords
echo "Enter the username for the new user:"
read -r username

echo "Enter a password for the user '$username':"
read -r user_pass

echo "Enter a password for the root user:"
read -r root_pass

echo ">> Setting keyboard layout..."
loadkeys br-abnt2

echo ">> Partitioning xvda..."
parted /dev/xvda --script mklabel gpt
parted /dev/xvda --script mkpart primary ext4 1MiB 100%
mkfs.ext4 /dev/xvda1
mount /dev/xvda1 /mnt

echo ">> Installing base system..."
pacstrap /mnt base linux linux-firmware sudo vim nano git curl ufw openssh

echo ">> Generating fstab..."
genfstab -U /mnt >> /mnt/etc/fstab

echo ">> Entering chroot and configuring system..."
arch-chroot /mnt /bin/bash <<EOF
ln -sf /usr/share/zoneinfo/America/Sao_Paulo /etc/localtime
hwclock --systohc

echo "pt_BR.UTF-8 UTF-8" >> /etc/locale.gen
locale-gen
echo "LANG=pt_BR.UTF-8" > /etc/locale.conf
echo "KEYMAP=br-abnt2" > /etc/vconsole.conf

echo "archmachine" > /etc/hostname
echo "127.0.0.1 localhost" >> /etc/hosts
echo "::1       localhost" >> /etc/hosts
echo "127.0.1.1 archmachine.localdomain archmachine" >> /etc/hosts

# Using dynamic values for the user and root password
useradd -m -G wheel -s /bin/bash $username
echo "$username:$user_pass" | chpasswd
echo "root:$root_pass" | chpasswd
echo "%wheel ALL=(ALL) ALL" >> /etc/sudoers

echo ">> Enabling UFW..."
systemctl enable ufw
ufw allow OpenSSH
ufw allow 8100/tcp
ufw --force enable

echo ">> Installing code-server..."
curl -fsSL https://code-server.dev/install.sh | sh

echo ">> Creating code-server systemd service on port 8100..."
mkdir -p /home/$username/.config/code-server
chown $username:$username /home/$username/.config/code-server

cat <<SERVICE > /etc/systemd/system/code-server@$username.service
[Unit]
Description=code-server for user $username
After=network.target

[Service]
Type=simple
User=$username
WorkingDirectory=/home/$username
ExecStart=/usr/bin/code-server --bind-addr 0.0.0.0:8100
Restart=always

[Install]
WantedBy=multi-user.target
SERVICE

systemctl enable code-server@$username

# Install nvm if not installed
if [ ! -d "$HOME/.nvm" ]; then
  git clone https://github.com/nvm-sh/nvm.git ~/.nvm
  cd ~/.nvm && git checkout `git describe --abbrev=0 --tags`
fi

# Source nvm
export NVM_DIR="$HOME/.nvm"
if [ -s "$NVM_DIR/nvm.sh" ]; then
  . "$NVM_DIR/nvm.sh"
fi

# Install specific Node versions
nvm install 14
nvm install 20
nvm install --lts

corepack enable
corepack prepare yarn@stable --activate
USERSETUP

EOF

echo ">> Finalizing and rebooting..."
umount -R /mnt
reboot
