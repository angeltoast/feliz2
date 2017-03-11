#!/bin/bash

# The Feliz2 installation scripts for Arch Linux
# Developed by Elizabeth Mills
# Revision date: 26th February 2017

# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or (at
# your option) any later version.

# This program is distributed in the hope that it will be useful, but
#      WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
#            General Public License for more details.

# A copy of the GNU General Public License is available from the Feliz2
#        page at http://sourceforge.net/projects/feliz2/files
#        or https://github.com/angeltoast/feliz2, or write to:
#                 The Free Software Foundation, Inc.
#                  51 Franklin Street, Fifth Floor
#                    Boston, MA 02110-1301 USA

# In this module: functions used during installation
# -------------------------      -------------------------
# Functions           Line       Functions           Line
# -------------------------      -------------------------
# arch_chroot           36       ReflectorMirrorList  205
# Parted                41       LocalMirrorList      215
# TPecho                63       InstallDM            230
#                                InstallLuxuries      240
# MountPartitions       99       UserAdd              325
# InstallKernel        162       SetRootPassword      340
# AddCodecs            180       SetUserPassword      378
# McInitCPIO           195       Restart
# -------------------------      -------------------------

arch_chroot() {  # From Lution AIS
  arch-chroot /mnt /bin/bash -c "${1}" 2>> feliz.log
}

Parted() {
  parted --script /dev/${UseDisk} "$1" 2>> feliz.log
}

TPecho() { # For displaying status while running on auto
  echo
  tput bold
  PrintOne "$1"
  tput sgr0
}

MountPartitions() {
  TPecho "Preparing and mounting partitions" ""
  # First unmount any mounted partitions
  umount ${RootPartition} /mnt 2>> feliz.log            # eg: umount /dev/sda1
  # 1) Root partition
  case $RootType in
  "") echo "Not formatting root partition" >> feliz.log # If /root filetype not set - do nothing
  ;;
  *) # Otherwise, check if replacing existing ext3/4 /root partition with btrfs
    CurrentType=$(file -sL ${RootPartition} | grep 'ext\|btrfs' | cut -c26-30) 2>> feliz.log
    # Check if /root type or existing partition are btrfs ...
    if [ ${CurrentType} ] && [ $RootType = "btrfs" ] && [ ${CurrentType} != "btrfs" ]; then
      btrfs-convert ${RootPartition} 2>> feliz.log      # Convert existing partition to btrfs
    elif [ $RootType = "btrfs" ]; then                  # Otherwise, for btrfs /root
      mkfs.btrfs -f ${RootPartition} 2>> feliz.log      # eg: mkfs.btrfs -f /dev/sda2
    elif [ $RootType = "xfs" ]; then                    # Otherwise, for xfs /root
      mkfs.xfs -f ${RootPartition} 2>> feliz.log        # eg: mkfs.xfs -f /dev/sda2
    else                                                # /root is not btrfs
      Partition=${RootPartition: -4}                    # Last 4 characters (eg: sda1)
      Label="${LabellingArray[${Partition}]}"           # Check to see if it has a label
      if [ -n "${Label}" ]; then                        # If it has a label ...
        Label="-L ${Label}"                             # ... prepare to use it
      fi
      mkfs.${RootType} ${Label} ${RootPartition} &>> feliz.log
    fi                                                  # eg: mkfs.ext4 -L Arch-Root /dev/sda1
  esac
  mount ${RootPartition} /mnt 2>> feliz.log             # eg: mount /dev/sda1 /mnt
  # 2) EFI (if required)
  if [ ${UEFI} -eq 1 ] && [ ${DualBoot} = "N" ]; then   # Check if /boot partition required
    mkfs.fat -F32 ${EFIPartition} 2> feliz.log          # Format EFI boot partition
    mkdir /mnt/boot                                     # Make mountpoint
    mount ${EFIPartition} /mnt/boot                     # Mount it
  fi
  # 3) Swap
  if [ ${SwapPartition} ]; then
    swapoff -a 2>> feliz.log                            # Make sure any existing swap cleared
    if [ $MakeSwap = "Y" ]; then
      Partition=${SwapPartition: -4}                    # Last 4 characters (eg: sda2)
      Label="${LabellingArray[${Partition}]}"           # Check for label
      if [ -n "${Label}" ]; then
        Label="-L ${Label}"                             # Prepare label
      fi
      mkswap ${Label} ${SwapPartition} 2>> feliz.log    # eg: mkswap -L Arch-Swap /dev/sda2
    fi
    swapon ${SwapPartition} 2>> feliz.log               # eg: swapon /dev/sda2
  fi

  # 4) Any additional partitions (from the related arrays AddPartList, AddPartMount & AddPartType)
  local Counter=0
  for id in ${AddPartList}                              # $id will be in the form /dev/sda2
  do
    umount ${id} /mnt${AddPartMount[$Counter]} >/dev/null 2>> feliz.log
    mkdir -p /mnt${AddPartMount[$Counter]} 2>> feliz.log  # eg: mkdir -p /mnt/home
    # Check if replacing existing ext3/4 partition with btrfs (as with /root)
    CurrentType=$(file -sL ${AddPartType[$Counter]} | grep 'ext\|btrfs' | cut -c26-30) 2>> feliz.log
    if [ "${AddPartType[$Counter]}" = "btrfs" ] && [ ${CurrentType} != "btrfs" ]; then
      btrfs-convert ${id} 2>> feliz.log
    elif [ "${AddPartType[$Counter]}" = "btrfs" ]; then
      mkfs.btrfs -f ${id} 2>> feliz.log   # eg: mkfs.btrfs -f /dev/sda2
    elif [ "${AddPartType[$Counter]}" = "xfs" ]; then
      mkfs.xfs -f ${id} 2>> feliz.log                   # eg: mkfs.xfs -f /dev/sda2
    elif [ "${AddPartType[$Counter]}" != "" ]; then       # If no type, do not format
      Partition=${id: -4}                               # Last 4 characters of ${id}
      Label="${LabellingArray[${Partition}]}"
      if [ -n "${Label}" ]; then
        Label="-L ${Label}"                             # Prepare label
      fi
      mkfs.${AddPartType[$Counter]} ${Label} ${id} &>> feliz.log # eg: mkfs.ext4 -L Arch-Home /dev/sda3
    fi
    mount ${id} /mnt${AddPartMount[$Counter]} &>> feliz.log # eg: mount /dev/sda3 /mnt/home
    Counter=$((Counter+1))
  done
}

InstallKernel() {   # Selected kernel and some other core systems

  LANG=C              # Temporary addition to overcome bug in Arch

  # And this, to solve keys issue if an older Feliz iso is running after keyring changes
  # If feliz.log exists and the first line created by felizinit is numeric (new felizinit)
  # and that number is greater than or equal to the date of the latest Arch trust update
  TrustDate=20170104  # Reset this to date of latest Arch Linux trust update
  if [ -f feliz.log ] && [ $(head -n 1 feliz.log | grep '[0-9]') ] && [ $(head -n 1 feliz.log) -ge $TrustDate ]; then
    echo "pacman-key trust check passed" >> feliz.log
  else             # Default
    TPecho "Updating keys"
    pacman-db-upgrade
    pacman-key --init 
    pacman-key --populate archlinux
    pacman-key --refresh-keys
  fi
  TPecho "Installing kernel and core systems"
  case $Kernel in
  1) # This is the full linux group list at 28th January 2017 with linux-lts in place of linux
    # Use the script ArchBaseGroup.sh in 3-FelizWorkshop to regenerate the list periodically
    pacstrap /mnt autoconf automake bash binutils bison bzip2 coreutils cryptsetup device-mapper dhcpcd diffutils e2fsprogs fakeroot file filesystem findutils flex gawk gcc gcc-libs gettext glibc grep groff gzip inetutils iproute2 iputils jfsutils less libtool licenses linux-lts logrotate lvm2 m4 make man-db man-pages mdadm nano netctl pacman patch pciutils pcmciautils perl pkg-config procps-ng psmisc reiserfsprogs sed shadow s-nail sudo sysfsutils systemd-sysvcompat tar texinfo usbutils util-linux vi which xfsprogs
  ;;
  *) pacstrap /mnt base base-devel 2>> feliz.log
  esac

  TPecho "Installing cli tools"
  pacstrap /mnt btrfs-progs gamin gksu gvfs ntp wget openssh os-prober screenfetch unrar unzip vim xarchiver xorg-xedit xterm 2>> feliz.log
  arch_chroot "systemctl enable sshd.service" >/dev/null

}

AddCodecs() {
  TPecho "Adding codecs"
  pacstrap /mnt a52dec autofs faac faad2 flac lame libdca libdv libmad libmpeg2 libtheora libvorbis libxv wavpack x264 gstreamer0.10-plugins pavucontrol pulseaudio pulseaudio-alsa libdvdcss dvd+rw-tools dvdauthor dvgrab

  TPecho "Installing Wireless Tools"
  pacstrap /mnt b43-fwcutter ipw2100-fw ipw2200-fw zd1211-firmware
  pacstrap /mnt iw wireless_tools wpa_supplicant

  TPecho "Installing Graphics tools"
  pacstrap /mnt xorg-server xorg-server-utils xorg-xinit xorg-twm

  TPecho "Installing opensource video drivers"
  pacstrap /mnt xf86-video-vesa xf86-video-nouveau xf86-input-synaptics

  TPecho "Installing fonts"
  pacstrap /mnt ttf-liberation

  # TPecho "Installing  CUPS printer services"
  # pacstrap /mnt -S system-config-printer cups
  # arch_chroot "systemctl enable org.cups.cupsd.service"
  
}

McInitCPIO() {
  TPecho "Running mkinitcpio"
  case $Kernel in
  1) arch_chroot "mkinitcpio -p linux-lts" 2>> feliz.log
  ;;
  *) arch_chroot "mkinitcpio -p linux" 2>> feliz.log
  esac
}

ReflectorMirrorList() { # Use reflector (added to archiso) to generate fast mirror list
  TPecho "Generating mirrorlist"
  reflector --verbose -l 5 --sort rate --save /etc/pacman.d/mirrorlist 2>> feliz.log
  if [ $? -gt 0 ]; then
    LocalMirrorList
  else
    chmod +r /etc/pacman.d/mirrorlist 2>> feliz.log
  fi
}

LocalMirrorList() { # In case Reflector fails, generate and save a shortened
  # mirrorlist of only the mirrors defined in the CountryCode variable.
  URL="https://www.archlinux.org/mirrorlist/?country=${CountryCode}&protocol=http"
  MirrorTemp=$(mktemp --suffix=-mirrorlist) 2>> feliz.log
  # Use curl to get list of mirrors from the Arch mirrorlist ${URL} to ${MirrorTemp}
  curl -so ${MirrorTemp} ${URL} 2>> feliz.log
  # Use sed to filter entries
  sed -i 's/^#Server/Server/g' ${MirrorTemp} 2>> feliz.log
  # Make a safe copy of existing mirrorlist
  mv -f /etc/pacman.d/mirrorlist /etc/pacman.d/mirrorlist.orig 2>> feliz.log
  # Replace existing mirrorlist with new local mirrorlist
  mv -f ${MirrorTemp} /etc/pacman.d/mirrorlist 2>> feliz.log
  chmod +r /etc/pacman.d/mirrorlist 2>> feliz.log
}

InstallDM()
{ # Display manager
  # Disable any existing display manager
  arch_chroot "systemctl disable display-manager.service" >/dev/null
  # Then install selected display manager
  TPecho "Installing"
  TPecho "${DisplayManager} ${Greeter}"
  pacstrap /mnt ${DisplayManager} ${Greeter} 2>> feliz.log
  arch_chroot "systemctl -f enable ${DisplayManager}.service" >/dev/null
}

InstallLuxuries()
{ # Install desktops and other extras
  # Display manager - runs only once
  InstallDM                  # Clear any pre-existing DM and install this one
  # First parse through LuxuriesList - checking for DEs
  if [ -n "${LuxuriesList}" ]; then
    for i in ${LuxuriesList}
    do
      case $i in
      "Budgie") TPecho "Installing"
          TPecho "Budgie"
          pacstrap /mnt budgie-desktop 2>> feliz.log
        ;;
      "Cinnamon") TPecho "Installing"
          TPecho "Cinnamon"
          pacstrap /mnt cinnamon 2>> feliz.log
        ;;
      "Deepin") TPecho "Installing"
          TPecho "Deepin"
          pacstrap /mnt deepin 2>> feliz.log
          pacstrap /mnt deepin-extras 2>> feliz.log
          # Change the greeter line in lightdm.conf
          if [ -d /mnt/etc/lightdm ]; then
            sed -i s/#greeter-session=example-gtk-gnome/greeter-session=lightdm-deepin-greeter/g /mnt/etc/lightdm/lightdm.conf 2>> feliz.log
          fi
        ;;
      "Enlightenment") TPecho "Installing"
          TPecho "Enlightenment"
          pacstrap /mnt enlightenment connman terminology 2>> feliz.log
        ;;
      "Fluxbox") TPecho "Installing"
          TPecho "Fluxbox"
          pacstrap /mnt fluxbox 2>> feliz.log
        ;;
      "Gnome") TPecho "Installing"
          TPecho "Gnome"
          pacstrap /mnt gnome 2>> feliz.log
          pacstrap /mnt gnome-extra 2>> feliz.log
        ;;
      "KDE") TPecho "Installing"
          TPecho "KDE Plasma"
          pacstrap /mnt plasma-meta 2>> feliz.log
          pacstrap /mnt kde-applications 2>> feliz.log
        ;;
      "LXDE") TPecho "Installing"
          TPecho "LXDE"
          pacstrap /mnt lxde leafpad 2>> feliz.log
          if [ -d /mnt/etc/lxdm ]; then
            echo "session=/usr/bin/startlxde" >> /mnt/etc/lxdm/lxdm.conf 2>> feliz.log
          fi
        ;;
      "LXQt") TPecho "Installing"
          TPecho "LXQt"
          pacstrap /mnt lxqt 2>> feliz.log
          pacstrap /mnt oxygen-icons connman lxappearance xscreensaver
        ;;
      "Mate") TPecho "Installing"
        TPecho "Mate"
        pacstrap /mnt mate 2>> feliz.log
        pacstrap /mnt mate-extra 2>> feliz.log
        ;;
      "MateGTK3") TPecho "Installing"
        TPecho "Mate GTK3"
        pacstrap /mnt mate-gtk3 2>> feliz.log
        pacstrap /mnt mate-extra-gtk3 2>> feliz.log
        ;;
      "Openbox") TPecho "Installing"
        TPecho "Openbox"
        pacstrap /mnt openbox 2>> feliz.log
        ;;
      "Xfce") TPecho "Installing"
        TPecho "Xfce"
        pacstrap /mnt xfce4 2>> feliz.log
        pacstrap /mnt xfce4-goodies 2>> feliz.log
        ;;
      *) continue # Ignore all others on this pass
      esac
    done

    # Install Yaourt
    TPecho "Installing"
    TPecho "Yaourt"
    arch=$(uname -m)
    if [ ${arch} = "x86_64" ]; then                     # New: Identify 64 bit architecture
      # For installed system
      echo -e "\n[multilib]\nInclude = /etc/pacman.d/mirrorlist" >> /mnt/etc/pacman.conf 2>> feliz.log
      # For installer
      echo -e "\n[multilib]\nInclude = /etc/pacman.d/mirrorlist" >> /etc/pacman.conf 2>> feliz.log
    fi
    # For installed system
    echo -e "\n[archlinuxfr]\nSigLevel = Never\nServer = http://repo.archlinux.fr/$arch" >> /mnt/etc/pacman.conf 2>> feliz.log
    # For installer
    echo -e "\n[archlinuxfr]\nSigLevel = Never\nServer = http://repo.archlinux.fr/$arch" >> /etc/pacman.conf 2>> feliz.log

    # Update, then install yaourt to /mnt
    pacman-key --init 2>> feliz.log
    pacman-key --populate archlinux 2>> feliz.log
    pacman -Sy 2>> feliz.log
    pacstrap /mnt yaourt 2>> feliz.log
    # Second parse through LuxuriesList - any extras
    for i in ${LuxuriesList}
    do
      case $i in
      "Budgie" | "Cinnamon" | "Deepin" | "Enlightenment" | "Fluxbox" | "Gnome" | "KDE" | "LXDE" | "LXQt" | "Mate" | "MateGTK3" | "Openbox" | "Xfce") continue # Ignore DEs & WMs on this pass
        ;;
      "cairo-dock") TPecho "Installing"
        TPecho "Cairo Dock"
        pacstrap /mnt cairo-dock cairo-dock-plug-ins 2>> feliz.log
        ;;
      "conky")     TPecho "Installing"
        TPecho "Conky"
        pacstrap /mnt conky 2>> feliz.log
        ;;
      *) TPecho "Installing"
        TPecho "$i"
        pacstrap /mnt "$i" 2>> feliz.log
      esac
    done
  fi
}

UserAdd() {
  CheckUsers=`cat /mnt/etc/passwd | grep ${UserName}`
  # If not already exist, create user
  if [ -z "${CheckUsers}" ]; then
    TPecho "Adding user and setting up groups"
    arch_chroot "useradd ${UserName} -m -g users -G wheel,storage,power,network,video,audio,lp -s /bin/bash"
    # Set up basic configuration files and permissions for user
    arch_chroot "cp /etc/skel/.bashrc /home/${UserName}"
    arch_chroot "chown -R ${UserName}:users /home/${UserName}"
    sed -i '/%wheel ALL=(ALL) ALL/s/^#//' /mnt/etc/sudoers 2>> feliz.log
  fi
  # Create main user folders
  for i in $(head -n 77 ${LanguageFile} | tail -n 1)
  do
    arch_chroot "mkdir /home/${UserName}/${i}"
    arch_chroot "chown -R ${UserName}: /home/${UserName}/${i}"
  done
  # Set keyboard at login for user
  arch_chroot "localectl set-x11-keymap $Countrykbd"
  case $Countrykbd in
  "uk") echo "setxkbmap -layout gb" >> /mnt/home/${UserName}/.bashrc
  ;;
  *) echo "setxkbmap -layout $Countrykbd" >> /mnt/home/${UserName}/.bashrc
  esac
}

SetRootPassword() {
  print_heading
  Echo
  PrintOne "Success!"
  Echo
  Translate "minutes"
  mins="$Result"
  Translate "seconds"
  secs="$Result"
  Translate "Finished installing in"
  PrintOne "$Result" "${DIFFMIN} $mins ${DIFFSEC} $secs"
  Echo
  PrintOne "Finally we need to set passwords"
  Echo
  PrintOne "Note that you will not be able to"
  PrintOne "see passwords as you enter them"
  Echo
  Repeat="Y"
  while [ $Repeat = "Y" ]
  do
    Translate "Enter a password for"
    read -s -p "               $Result root: " Pass1
    Echo
    Translate "Re-enter the password for"
    read -s -p "               $Result root: " Pass2
    Echo
    if [ -z ${Pass1} ] || [ -z ${Pass2} ]; then
      print_heading
      Translate "Passwords cannot be blank"
      read_timed "$Result ..." 1
      continue
    fi
    if [ $Pass1 = $Pass2 ]; then
     echo -e "${Pass1}\n${Pass2}" > /tmp/.passwd
     arch_chroot "passwd root" < /tmp/.passwd >/dev/null
     rm /tmp/.passwd 2>> feliz.log
     Repeat="N"
    else
      print_heading
      PrintOne "Passwords don't match"
    fi
  done
}

SetUserPassword() {
  Echo
  Repeat="Y"
  while [ $Repeat = "Y" ]
  do
    Translate "Enter a password for"
    read -s -p "               $Result $UserName: " Pass1
    Echo
    Translate "Re-enter the password for"
    read -s -p "               $Result $UserName: " Pass2
    Echo
    if [ -z ${Pass1} ] || [ -z ${Pass2} ]; then
      print_heading
      Translate "Passwords cannot be blank"
      read_timed "$Result ..." 1
      continue
    fi
    if [ $Pass1 = $Pass2 ]; then
      echo -e "${Pass1}\n${Pass2}" > /tmp/.passwd
      arch_chroot "passwd ${UserName}" < /tmp/.passwd >/dev/null
      rm /tmp/.passwd 2>> feliz.log
      Repeat="N"
    else
      print_heading
      PrintOne "Passwords don't match"
      continue
    fi
  done
}

Restart() {
  Translate "Shutdown Reboot"
  listgen1 "$Result" "Ctrl+c $_Exit" "$_Ok"
  case $Response in
  1) shutdown -h now
  ;;
  2) reboot
  ;;
  *) exit 1
  esac
}

