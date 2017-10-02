#!/bin/bash

# The Feliz2 installation scripts for Arch Linux
# Developed by Elizabeth Mills
# With grateful acknowlegements to Helmuthdu, Carl Duff and Dylan Schacht
# Revision date: 1st October 2017

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
# arch_chroot           37
# Parted                41       InstallDM            206
# TPecho                45       InstallLuxuries      216
# MountPartitions       52       UserAdd              324
# InstallKernel        126       SetRootPassword      368
# AddCodecs            158       SetUserPassword      412
# NewMirrorList        187       Restart              442
# -------------------------      -------------------------

# read -p "DEBUG f-run $LINENO"   # Basic debugging - copy and paste wherever a break is needed

arch_chroot() {  # From Lution AIS
  arch-chroot /mnt /bin/bash -c "${1}" 2>> feliz.log
}

Parted() {
  parted --script /dev/${UseDisk} "$1" 2>> feliz.log
}

TPecho() { # For displaying status while running on auto
  echo
  tput bold
  PrintOne "$1" "$2" "$3"
  tput sgr0
  Echo
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
    mkfs.vfat -F32 ${EFIPartition} 2>> feliz.log        # Format EFI boot partition
    mkdir -p /mnt/boot                                  # Make mountpoint
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
    umount ${id} /mnt${AddPartMount[$Counter]} >> feliz.log
    mkdir -p /mnt${AddPartMount[$Counter]} 2>> feliz.log  # eg: mkdir -p /mnt/home
    # Check if replacing existing ext3/4 partition with btrfs (as with /root)
    CurrentType=$(file -sL ${AddPartType[$Counter]} | grep 'ext\|btrfs' | cut -c26-30) 2>> feliz.log
    if [ "${AddPartType[$Counter]}" = "btrfs" ] && [ ${CurrentType} != "btrfs" ]; then
      btrfs-convert ${id} 2>> feliz.log
    elif [ "${AddPartType[$Counter]}" = "btrfs" ]; then
      mkfs.btrfs -f ${id} 2>> feliz.log   # eg: mkfs.btrfs -f /dev/sda2
    elif [ "${AddPartType[$Counter]}" = "xfs" ]; then
      mkfs.xfs -f ${id} 2>> feliz.log                   # eg: mkfs.xfs -f /dev/sda2
    elif [ "${AddPartType[$Counter]}" != "" ]; then     # If no type, do not format
      Partition=${id: -4}                               # Last 4 characters of ${id}
      Label="${LabellingArray[${Partition}]}"
      if [ -n "${Label}" ]; then
        Label="-L ${Label}"                             # Prepare label
      fi
      mkfs.${AddPartType[$Counter]} ${Label} ${id} &>> feliz.log  # eg: mkfs.ext4 -L Arch-Home /dev/sda3
    fi
    mount ${id} /mnt${AddPartMount[$Counter]} &>> feliz.log       # eg: mount /dev/sda3 /mnt/home
    Counter=$((Counter+1))
  done
}

InstallKernel() {   # Selected kernel and some other core systems

  LANG=C            # Set the locale for all processes run from the current shell 

  # And this, to solve keys issue if an older Feliz or Arch iso is running after keyring changes
  # Passes test if the date of the running iso is more recent than the date of the latest Arch trust update

  # Use blkid to get details of the Feliz or Arch iso that is running, in the form yyyymm
  RunningDate=$(blkid | grep "feliz\|arch" | cut -d'=' -f3 | cut -d'-' -f2 | cut -b-6)

  TrustDate=201709  # Reset this to date of latest Arch Linux trust update
                    # Next trustdb check 2017-10-20
  
  if [ $RunningDate -ge $TrustDate ]; then              # If the running iso is more recent than
    echo "pacman-key trust check passed" >> feliz.log   # the last trust update, no action is taken
  else                                                  # But if the iso is older than the last trust update
    TPecho "Updating keys"                              # Then the keys must be updated
   # pacman-db-upgrade
   # pacman-key --init
   # pacman-key --populate archlinux
   # pacman-key --refresh-keys
    pacman -Sy --noconfirm archlinux-keyring            # This is an experimental alternative to the above
  fi
  Translate "kernel and core systems"
  TPecho "$_Installing " "$Result"
  case $Kernel in
  1) # This is the full linux group list at 1st August 2017 with linux-lts in place of linux
    # Use the script ArchBaseGroup.sh in FelizWorkshop to regenerate the list periodically
    pacstrap /mnt autoconf automake bash binutils bison bzip2 coreutils cryptsetup device-mapper dhcpcd diffutils e2fsprogs fakeroot file filesystem findutils flex gawk gcc gcc-libs gettext glibc grep groff gzip inetutils iproute2 iputils jfsutils less libtool licenses linux-lts logrotate lvm2 m4 make man-db man-pages mdadm nano netctl pacman patch pciutils pcmciautils perl pkg-config procps-ng psmisc reiserfsprogs sed shadow s-nail sudo sysfsutils systemd-sysvcompat tar texinfo usbutils util-linux vi which xfsprogs 2>> feliz.log
  ;;
  *) pacstrap /mnt base base-devel 2>> feliz.log
  esac
  Translate "cli tools"
  TPecho "$_Installing " "$Result"
  pacstrap /mnt btrfs-progs gamin gksu gvfs ntp wget openssh os-prober screenfetch unrar unzip vim xarchiver xorg-xedit xterm 2>> feliz.log
  arch_chroot "systemctl enable sshd.service" >> feliz.log
}

AddCodecs() {
  TPecho "$_Installing " "codecs"
  pacstrap /mnt a52dec autofs faac faad2 flac lame libdca libdv libmad libmpeg2 libtheora libvorbis libxv wavpack x264 gstreamer gst-plugins-base gst-plugins-good pavucontrol pulseaudio pulseaudio-alsa libdvdcss dvd+rw-tools dvdauthor dvgrab 2>> feliz.log
  Translate "Wireless Tools"
  TPecho "$_Installing " "$Result"
  pacstrap /mnt b43-fwcutter ipw2100-fw ipw2200-fw zd1211-firmware 2>> feliz.log
  pacstrap /mnt iw wireless_tools wpa_supplicant 2>> feliz.log
  # Note that networkmanager and network-manager-applet are installed separately by feliz.sh
  Translate "Graphics tools"
  TPecho "$_Installing " "$Result"
  pacstrap /mnt xorg xorg-xinit xorg-twm 2>> feliz.log
  Translate "opensource video drivers"
  TPecho "$_Installing " "$Result"
  pacstrap /mnt xf86-video-vesa xf86-video-nouveau xf86-input-synaptics 2>> feliz.log
  Translate "fonts"
  TPecho "$_Installing " "$Result"
  pacstrap /mnt ttf-liberation 2>> feliz.log

  # TPecho "Installing  CUPS printer services"
  # pacstrap /mnt -S system-config-printer cups
  # arch_chroot "systemctl enable org.cups.cupsd.service"

}

NewMirrorList() { # Use rankmirrors (script in /usr/bin/ from Arch) to generate fast mirror list
  # In f-set.sh/ChooseMirrors the user has selected one or more countries with Arch Linux mirrors
  # These have been stored in the array CountryLong[@] declared in f-vars.sh
  # Now the mirrors associated with each of those countries must be extracted from the array
  TPecho "Generating mirrorlist"
  cp /etc/pacman.d/mirrorlist /etc/pacman.d/mirrorlist.safe 2>> feliz.log

  if [ ${#CountryLong[@]} -eq 0 ]; then   # If no mirrors were cosen by user,
    # generate and save a shortened mirrorlist of only the mirrors defined in the CountryCode variable.
    URL="https://www.archlinux.org/mirrorlist/?country=${CountryCode}&use_mirror_status=on"
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
  else
    # Prepare file of mirrors to be used
    for Country in "${CountryLong[@]}"
    do
      # Get line number of $Country in $CountryLong in allmirrors.list
      #                      exact match only | restrict to first find | display only number
      CountryLine=$(grep -n "${Country}" allmirrors.list | head -n 1 | cut -d':' -f1)
      # Read each line until empty line encountered
      while true
      do
        CountryLine=$((CountryLine+1))                                                    # Next line
        MirrorURL="$(head -n ${CountryLine} allmirrors.list | tail -n 1 | cut -d'#' -f2)" # Read next item in source file
        echo "$MirrorURL" >> usemirrors.list                                              # Save it to usemirrors.list file
        if [ -z "$MirrorURL" ]; then
          break
        else
          echo "$_Loading " "$Country $MirrorURL"
        fi
      done
    done
    TPecho "Ranking mirrors - please wait ..."
    Date=$(date)
    echo -e "# Ranked mirrors /etc/pacman.d/mirrorlist \n# $Date \n# Generated by Feliz and rankmirrors\n#" > /etc/pacman.d/mirrorlist
    rankmirrors -n 5 usemirrors.list | grep '^Server' >> /etc/pacman.d/mirrorlist
    rm usemirrors.list allmirrors.list    # Delete working files
  fi
  rm countries.list                       # Delete working files
}

InstallDM() { # Disable any existing display manager
  arch_chroot "systemctl disable display-manager.service" >> feliz.log
  # Then install selected display manager
  TPecho "$_Installing " "${DisplayManager}"
  case ${DisplayManager} in
  "lightdm") pacstrap /mnt lightdm lightdm-gtk-greeter 2>> feliz.log
    arch_chroot "systemctl -f enable lightdm.service" >> feliz.log
  ;;
  *)
    pacstrap /mnt "${DisplayManager}" 2>> feliz.log
    arch_chroot "systemctl -f enable ${DisplayManager}.service" >> feliz.log
  esac
}

InstallLuxuries() { # Install desktops and other extras

  # FelizOB (note that $LuxuriesList and $DisplayManager are empty, so their routines will not be called)
  if [ $DesktopEnvironment = "FelizOB" ]; then
    TPecho "$_Installing " "FelizOB"
    arch_chroot "systemctl disable display-manager.service" 2>> feliz.log
    pacstrap /mnt lxdm 2>> feliz.log
    arch_chroot "systemctl -f enable lxdm.service" >> feliz.log
    pacstrap /mnt openbox 2>> feliz.log                                               # First ensure that Openbox gets installed
    pacstrap /mnt obmenu obconf 2>> feliz.log                                         # Then Openbox tools
    pacstrap /mnt lxde-icon-theme leafpad lxappearance lxinput lxpanel 2>> feliz.log  # Then LXDE tools
    pacstrap /mnt lxrandr lxsession lxtask lxterminal pcmanfm 2>> feliz.log           # more LXDE tools
    pacstrap /mnt compton conky gpicview midori xscreensaver 2>> feliz.log            # Add some extras
    cp lxdm.conf /mnt/etc/lxdm/                                                       # Copy the LXDM config file
    InstallYaourt                                                                     # And install Yaourt
  fi

  # Display manager - runs only once
  if [ -n "${DisplayManager}" ]; then   # Not triggered by FelizOB
    InstallDM                  # Clear any pre-existing DM and install this one
  fi

  # First parse through LuxuriesList checking for DEs and Window Managers (not used by FelizOB)
  if [ -n "${LuxuriesList}" ]; then
    for i in ${LuxuriesList}
    do
      case $i in
      "Awesome") TPecho "$_Installing " "Awesome"
          pacstrap /mnt awesome 2>> feliz.log
        ;;
      "Budgie") TPecho "$_Installing " "Budgie"
          pacstrap /mnt budgie-desktop gnome 2>> feliz.log
        ;;
      "Cinnamon") TPecho "$_Installing Cinnamon"
          pacstrap /mnt cinnamon 2>> feliz.log
        ;;
      "Enlightenment") TPecho "$_Installing " "Enlightenment"
          pacstrap /mnt enlightenment connman terminology 2>> feliz.log
        ;;
      "Fluxbox") TPecho "$_Installing " "Fluxbox"
          pacstrap /mnt fluxbox 2>> feliz.log
        ;;
      "Gnome") TPecho "$_Installing " "Gnome"
          pacstrap /mnt gnome 2>> feliz.log
          pacstrap /mnt gnome-extra 2>> feliz.log
        ;;
      "i3") TPecho "$_Installing " "i3 window manager"
          pacstrap /mnt i3 2>> feliz.log      # i3 group includes i3-wm
         ;;
      "Icewm") TPecho "$_Installing " "Icewm"
          pacstrap /mnt icewm 2>> feliz.log
         ;;
      "JWM") TPecho "$_Installing " "JWM"
          pacstrap /mnt jwm 2>> feliz.log
         ;;
      "KDE") TPecho "$_Installing " "KDE Plasma"
          pacstrap /mnt plasma-meta 2>> feliz.log
          pacstrap /mnt kde-applications 2>> feliz.log
        ;;
      "LXDE") TPecho "$_Installing " "LXDE"
          pacstrap /mnt lxde leafpad 2>> feliz.log
          if [ -d /mnt/etc/lxdm ]; then
            echo "session=/usr/bin/startlxde" >> /mnt/etc/lxdm/lxdm.conf 2>> feliz.log
          fi
        ;;
      "LXQt") TPecho "$_Installing " "LXQt"
          pacstrap /mnt lxqt 2>> feliz.log
          pacstrap /mnt oxygen-icons connman lxappearance xscreensaver 2>> feliz.log
        ;;
      "Mate") TPecho "$_Installing " "Mate"
        pacstrap /mnt mate mate-extra 2>> feliz.log
        pacstrap /mnt mate-applet-dock mate-applet-streamer mate-menu 2>> feliz.log
        ;;
      "Openbox") TPecho "$_Installing " "Openbox"
        pacstrap /mnt openbox 2>> feliz.log
        ;;
      "Windowmaker") TPecho "$_Installing " "Windowmaker"
        pacstrap /mnt windowmaker 2>> feliz.log
        pacstrap /mnt windowmaker-extra 2>> feliz.log
        ;;
      "Xfce") TPecho "$_Installing " "Xfce"
        pacstrap /mnt xfce4 2>> feliz.log
        pacstrap /mnt xfce4-goodies 2>> feliz.log
        ;;
      "Xmonad") TPecho "$_Installing " "Xmonad"
        pacstrap /mnt xmonad 2>> feliz.log
        pacstrap /mnt xmonad-contrib 2>> feliz.log
        ;;
      *) continue # Ignore all others on this pass
      esac
    done

    InstallYaourt

    # Second parse through LuxuriesList for any extras (not triggered by FelizOB)
    for i in ${LuxuriesList}
    do
      case $i in
      "Awesome" | "Budgie" | "Cinnamon" | "Enlightenment" | "Fluxbox" | "Gnome" | "i3" | "Icewm" | "JWM" | "KDE" | "LXDE" | "LXQt" | "Mate" | "Openbox" | "Windowmaker" | "Xfce" | "Xmonad") continue # Ignore DEs & WMs on this pass
        ;;
      "cairo-dock") TPecho "$_Installing " "Cairo Dock"
        pacstrap /mnt cairo-dock cairo-dock-plug-ins 2>> feliz.log
        ;;
      "conky") TPecho "$_Installing " "Conky"
        pacstrap /mnt conky 2>> feliz.log
        ;;
      *) TPecho "$_Installing " "$i"
        pacstrap /mnt "$i" 2>> feliz.log
      esac
    done
  fi
}

InstallYaourt() {
  TPecho "$_Installing " "Yaourt"
  arch=$(uname -m)
  if [ ${arch} = "x86_64" ]; then                     # Identify 64 bit architecture
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
  # FelizOB
  if [ $DesktopEnvironment = "FelizOB" ]; then
    # Set up directories
    arch_chroot "mkdir -p /home/${UserName}/.config/openbox/"
    arch_chroot "mkdir -p /home/${UserName}/.config/pcmanfm/default/"
    arch_chroot "mkdir -p /home/${UserName}/.config/lxpanel/default/panels/"
    arch_chroot "mkdir /home/${UserName}/Pictures/"
    arch_chroot "mkdir /home/${UserName}/.config/libfm/"
    # Copy FelizOB files

    cp -r themes /mnt/home/${UserName}/.themes 2>> feliz.log            # Copy egtk theme
    
    CheckExisting "/mnt/home/${UserName}/" ".conkyrc"
    cp conkyrc /mnt/home/${UserName}/.conkyrc 2>> feliz.log             # Conky configuration file

    CheckExisting "/mnt/home/${UserName}/" ".compton.conf"
    cp compton.conf /mnt/home/${UserName}/.compton.conf 2>> feliz.log   # Compton configuration file

    CheckExisting "/mnt/home/${UserName}/" ".face"
    cp face.png /mnt/home/${UserName}/.face 2>> feliz.log               # Image for greeter

    CheckExisting "/mnt/home/${UserName}/.config/openbox/" "autostart"
    cp autostart /mnt/home/${UserName}/.config/openbox/ 2>> feliz.log   # Autostart configuration file

    CheckExisting "/mnt/home/${UserName}/.config/openbox/" "menu.xml"
    cp menu.xml /mnt/home/${UserName}/.config/openbox/ 2>> feliz.log    # Openbox right-click menu configuration file

    CheckExisting "/mnt/home/${UserName}/.config/openbox/" "rc.xml"
    cp rc.xml /mnt/home/${UserName}/.config/openbox/ 2>> feliz.log      # Openbox configuration file

    CheckExisting "/mnt/home/${UserName}/.config/lxpanel/default/panels/" "panel"
    cp panel /mnt/home/${UserName}/.config/lxpanel/default/panels/ 2>> feliz.log  # Panel configuration file

    cp feliz.png /mnt/usr/share/icons/ 2>> feliz.log                    # Icon for panel menu
    cp wallpaper.jpg /mnt/home/${UserName}/Pictures/ 2>> feliz.log      # Wallpaper for user

    CheckExisting "/mnt/home/${UserName}/.config/libfm/" "libfm.conf"
    cp libfm.conf /mnt/home/${UserName}/.config/libfm/ 2>> feliz.log    # Configurations for pcmanfm

    CheckExisting "/mnt/home/${UserName}/.config/lxpanel/default/" "config"
    cp config /mnt/home/${UserName}/.config/lxpanel/default/ 2>> feliz.log # Desktop configurations for pcmanfm

    CheckExisting "/mnt/home/${UserName}/.config/pcmanfm/default/" "desktop-items-0.conf"
    cp desktop-items /mnt/home/${UserName}/.config/pcmanfm/default/desktop-items-0.conf 2>> feliz.log # Desktop configurations for pcmanfm

    cp wallpaper.jpg /mnt/usr/share/ 2>> feliz.log                      # Wallpaper for desktop (set in desktop-items-0.conf)
    # Set owner
    arch_chroot "chown -R ${UserName}:users /home/${UserName}/"
  fi
  # Set keyboard at login for user
  arch_chroot "localectl set-x11-keymap $Countrykbd"
  case $Countrykbd in
  "uk") echo "setxkbmap -layout gb" >> /mnt/home/${UserName}/.bashrc 2>> feliz.log
  ;;
  *) echo "setxkbmap -layout $Countrykbd" >> /mnt/home/${UserName}/.bashrc 2>> feliz.log
  esac
}

CheckExisting() {             # Test if $1 (path) + $2 (file) already exists
  if [ -f "$1$2" ]; then      # If path+file already exists
      mv "$1$2" "$1saved$2"   # Rename it
  fi
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
      PrintOne "Passwords cannot be blank"
      Echo
      PrintOne "Please try again"
      Echo
      PrintOne "Note that you will not be able to"
      PrintOne "see passwords as you enter them"
      Echo
      continue
    fi
    if [ $Pass1 = $Pass2 ]; then
     echo -e "${Pass1}\n${Pass2}" > /tmp/.passwd
     arch_chroot "passwd root" < /tmp/.passwd >> feliz.log
     rm /tmp/.passwd 2>> feliz.log
     Repeat="N"
    else
      print_heading
      PrintOne "Passwords don't match"
      Echo
      PrintOne "Please try again"
      Echo
      PrintOne "Note that you will not be able to"
      PrintOne "see passwords as you enter them"
      Echo
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
      PrintOne "Passwords cannot be blank"
      Echo
      PrintOne "Please try again"
      Echo
      PrintOne "Note that you will not be able to"
      PrintOne "see passwords as you enter them"
      Echo
      continue
    fi
    if [ $Pass1 = $Pass2 ]; then
      echo -e "${Pass1}\n${Pass2}" > /tmp/.passwd
      arch_chroot "passwd ${UserName}" < /tmp/.passwd >> feliz.log
      rm /tmp/.passwd 2>> feliz.log
      Repeat="N"
    else
      print_heading
      PrintOne "Passwords don't match"
      Echo
      PrintOne "Please try again"
      Echo
      PrintOne "Note that you will not be able to"
      PrintOne "see passwords as you enter them"
      Echo
    fi
  done
}

Restart() {
  Translate "Shutdown Reboot"
  listgen1 "$Result" "" "$_Ok"
  umount /mnt -R
  case $Response in
  1) shutdown -h now
  ;;
  2) reboot
  ;;
  *) exit 1
  esac
}
