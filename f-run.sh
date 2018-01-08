#!/bin/bash

# The Feliz2 installation scripts for Arch Linux
# Developed by Elizabeth Mills
# With grateful acknowlegements to Helmuthdu, Carl Duff and Dylan Schacht
# Revision date: 8th January 2018

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
# -------------------------    ---------------------------
# Functions           Line     Functions              Line
# -------------------------    ---------------------------
# arch_chroot            40    mirror_list             419
# parted_script          44    install_display_manager 473
# install_message        48    install_extras          487
# action_MBR             56    install_yaourt          581
# action_EFI            134    user_add                603
# autopart              233    check_existing          666
# mount_partitions      273    set_root_password       673
# install_kernel        346    set_user_password       728
# add_codecs            384    finish                  774
#                              partition_maker         793
# -------------------------    ---------------------------

function arch_chroot { # From Lution AIS - calls arch-chroot with options
  arch-chroot /mnt /bin/bash -c "${1}" 2>> feliz.log
}

function parted_script { # Calls GNU parted tool with options
  parted --script /dev/${UseDisk} "$1" 2>> feliz.log
}

function install_message { # For displaying status while running on auto
  echo
  tput bold
  print_first_line "$1" "$2" "$3"
  tput sgr0
  echo
}

function action_MBR { # Called without arguments by feliz.sh before other partitioning actions
                      # Uses the variables set by user to create partition table & all partitions
                      
  create_partition_table
  
  local Unit
  local EndPoint
  declare -i Chars
  declare -i Var
  declare -i EndPart
  declare -i NextStart
  # Root partition
  # --------------
    # Calculate end-point    
    Unit=${RootSize: -1}                # Save last character of root (eg: G)
    Chars=${#RootSize}                  # Count characters in root variable
    Var=${RootSize:0:Chars-1}           # Remove unit character to get an int
    if [ "$Unit" = "G" ]; then
      Var=$((Var*1024))                 # Convert to MiB
      EndPart=$((1+Var))                # Start at 1MiB
      EndPoint="${EndPart}MiB"          # Append unit
    elif [ "$Unit" = "M" ]; then
      EndPart=$((1+Var))                # Start at 1MiB
      EndPoint="${EndPart}MiB"          # Append unit
    elif [ "$Unit" = "%" ]; then
      EndPoint="${Var}%"
    fi
    parted_script "mkpart primary ${RootType} 1MiB ${EndPoint}"
    parted_script "set 1 boot on"
    RootPartition="${GrubDevice}1"      # "/dev/sda1"
    local NextStart=${EndPart}          # Save for next partition. Numerical only (has no unit)
  # Swap partition
  # --------------
    if [ -n "$SwapSize" ]; then
      # Calculate end-point
      Unit=${SwapSize: -1}              # Save last character of swap (eg: G)
      Chars=${#SwapSize}                # Count characters in swap variable
      Var=${SwapSize:0:Chars-1}         # Integer part of swap variable
      if [ "$Unit" = "G" ]; then
        Var=$((Var*1024))               # Convert to MiB
        EndPart=$((NextStart+Var))      # Add to previous end
        EndPoint="${EndPart}MiB"        # Append unit
      elif [ "$Unit" = "M" ]; then
        EndPart=$((NextStart+Var))      # Add to previous end
        EndPoint="${EndPart}MiB"        # Append unit
      elif [ "$Unit" = "%" ]; then
        EndPoint="${Var}%"
      fi
      # Make the partition
      parted_script "mkpart primary linux-swap ${NextStart}MiB ${EndPoint}"
      SwapPartition="${GrubDevice}2"    # "/dev/sda2"
      MakeSwap="Y"
      NextStart=${EndPart}              # Save for next partition. Numerical only (has no unit)
    fi
  # Home partition
  # --------------
    if [ $HomeSize ]; then
      # Calculate end-point
      Unit=${HomeSize: -1}              # Save last character of home (eg: G)
      Chars=${#HomeSize}                # Count characters in home variable
      Var=${HomeSize:0:Chars-1}         # Remove unit character from home variable
      if [ "$Unit" = "G" ]; then
        Var=$((Var*1024))               # Convert to MiB
        EndPart=$((NextStart+Var))      # Add to previous end
        EndPoint="${EndPart}MiB"        # Append unit
      elif [ "$Unit" = "M" ]; then
        EndPart=$((NextStart+Var))      # Add to previous end
        EndPoint="${EndPart}MiB"        # Append unit
      elif [ "$Unit" = "%" ]; then
        EndPoint="${Var}%"
      fi
      # Make the partition
      parted_script "mkpart primary ${HomeType} ${NextStart}MiB ${EndPoint}"
      HomePartition="${GrubDevice}3"    # "/dev/sda3"
      Home="Y"
      AddPartList[0]="${GrubDevice}3"   # /dev/sda3     | add to
      AddPartMount[0]="/home"           # Mountpoint    | array of
      AddPartType[0]="${HomeType}"      # Filesystem    | additional partitions
    fi
  return 0
}

function action_EFI { # Called without arguments by feliz.sh before other partitioning actions
                      # Uses the variables set by user to create partition table & all partitions
                      
  create_partition_table
  
  local Unit
  local EndPoint
  declare -i Chars
  declare -i Var
  declare -i EndPart
  declare -i NextStart
  # Format the drive for EFI
    tput setf 0                         # Change foreground colour to black temporarily to hide error message
    sgdisk --zap-all /dev/sda           # Remove all partitions
    wipefs -a /dev/sda                  # Remove filesystem
    tput sgr0                           # Reset colour
    parted_script "mklabel gpt"         # Create EFI partition table
  # Boot partition
  # --------------
    # Calculate end-point
    Unit=${BootSize: -1}                # Save last character of boot (eg: M)
    Chars=${#BootSize}                  # Count characters in boot variable
    Var=${BootSize:0:Chars-1}           # Remove unit character from boot variable
    if [ "$Unit" = "G" ]; then
      Var=$((Var*1024))                 # Convert to MiB
    fi
    EndPoint=$((Var+1))                 # Add start and finish. Result is MiBs, numerical only (has no unit)
    parted_script "mkpart primary fat32 1MiB ${EndPoint}MiB"
    parted_script "set 1 boot on"
    EFIPartition="${GrubDevice}1"       # "/dev/sda1"
    NextStart=${EndPoint}               # Save for next partition. Numerical only (has no unit)
  # Root partition
  # --------------
    # Calculate end-point
    Unit=${RootSize: -1}                # Save last character of root (eg: G)
    Chars=${#RootSize}                  # Count characters in root variable
    Var=${RootSize:0:Chars-1}           # Remove unit character from root variable
    if [ "$Unit" = "G" ]; then
      Var=$((Var*1024))                 # Convert to MiB
      EndPart=$((NextStart+Var))        # Add to previous end
      EndPoint="${EndPart}MiB"          # Add unit
    elif [ "$Unit" = "M" ]; then
      EndPart=$((NextStart+Var))        # Add to previous end
      EndPoint="${EndPart}MiB"          # Add unit
    elif [ "$Unit" = "%" ]; then
      EndPoint="${Var}%"
    fi
    # Make the partition
    parted_script "mkpart primary ${RootType} ${NextStart}MiB ${EndPoint}"
    RootPartition="${GrubDevice}2"      # "/dev/sda2"
    NextStart=${EndPart}                # Save for next partition. Numerical only (has no unit)
  # Swap partition
  # --------------
    if [ $SwapSize ]; then
      # Calculate end-point
      Unit=${SwapSize: -1}              # Save last character of swap (eg: G)
      Chars=${#SwapSize}                # Count characters in swap variable
      Var=${SwapSize:0:Chars-1}         # Remove unit character from swap variable
      if [ "$Unit" = "G" ]; then
        Var=$((Var*1024))               # Convert to MiB
        EndPart=$((NextStart+Var))      # Add to previous end
        EndPoint="${EndPart}MiB"        # Add unit
      elif [ "$Unit" = "M" ]; then
        EndPart=$((NextStart+Var))      # Add to previous end
        EndPoint="${EndPart}MiB"        # Add unit
      elif [ "$Unit" = "%" ]; then
        EndPoint="${Var}%"
      fi
      # Make the partition
      parted_script "mkpart primary linux-swap ${NextStart}MiB ${EndPoint}"
      SwapPartition="${GrubDevice}3"    # "/dev/sda3"
      MakeSwap="Y"
      NextStart=${EndPart}              # Save for next partition. Numerical only (has no unit)
    fi
  # Home partition
  # --------------
    if [ $HomeSize ]; then
      # Calculate end-point
      Unit=${HomeSize: -1}              # Save last character of home (eg: G)
      Chars=${#HomeSize}                # Count characters in home variable
      Var=${HomeSize:0:Chars-1}         # Remove unit character from home variable
      if [ "$Unit" = "G" ]; then
        Var=$((Var*1024))               # Convert to MiB
        EndPart=$((NextStart+Var))      # Add to previous end
        EndPoint="${EndPart}MiB"        # Add unit
      elif [ "$Unit" = "M" ]; then
        EndPart=$((NextStart+Var))      # Add to previous end
        EndPoint="${EndPart}MiB"        # Add unit
      elif [ "$Unit" = "%" ]; then
        EndPoint="${Var}%"
      fi
      # Make the partition
      parted_script "mkpart primary ${HomeType} ${NextStart}MiB ${EndPoint}"
      HomePartition="${GrubDevice}4"    # "/dev/sda4"
      Home="Y"
      AddPartList[0]="${GrubDevice}4"   # /dev/sda4     | add to
      AddPartMount[0]="/home"           # Mountpoint    | array of
      AddPartType[0]="ext4"             # Filesystem    | additional partitions
    fi
  return 0
}

function create_partition_table {
  # Create a new partition table
  if [ ${UEFI} -eq 1 ]; then                        # Installing in UEFI environment
    sgdisk --zap-all ${GrubDevice} &>> feliz.log    # Remove all existing filesystems
    wipefs -a ${GrubDevice} &>> feliz.log           # from the drive
    parted_script "mklabel gpt"                            # Create new filesystem
    parted_script "mkpart primary fat32 1MiB 513MiB"       # EFI boot partition
    StartPoint="513MiB"                             # For next partition
  else                                              # Installing in BIOS environment
    dd if=/dev/zero of=${GrubDevice} bs=512 count=1 # Remove any existing partition table
    parted_script "mklabel msdos"                   # Create new filesystem
    StartPoint="1MiB"                               # Set start point for next partition
  fi
}

function autopart { # Called by feliz.sh/preparation during installation phase
                    # if AutoPartition flag is AUTO.
                    # Consolidated automatic partitioning for BIOS or EFI environment
  GrubDevice="/dev/${UseDisk}"
  Home="N"                                          # No /home partition at this point
  DiskSize=$(lsblk -l | grep "${UseDisk}\ " | awk '{print $4}' | sed "s/G\|M\|K//g") # Get disk size

  create_partition_table
                                                    # Decide partition sizes
  if [ $DiskSize -ge 40 ]; then                     # ------ /root /home /swap partitions ------
    HomeSize=$((DiskSize-15-4))                     # /root 15 GiB, /swap 4GiB, /home from 18GiB
    partition_maker "${StartPoint}" "15GiB" "${HomeSize}GiB" "100%"
  elif [ $DiskSize -ge 30 ]; then                   # ------ /root /home /swap partitions ------
    HomeSize=$((DiskSize-15-3))                     # /root 15 GiB, /swap 3GiB, /home 12 to 22GiB
    partition_maker "${StartPoint}" "15GiB" "${HomeSize}GiB" "100%"
  elif [ $DiskSize -ge 18 ]; then                   # ------ /root & /swap partitions only ------
    RootSize=$((DiskSize-2))                        # /root 16 to 28GiB, /swap 2GiB
    partition_maker "${StartPoint}" "${RootSize}GiB" "" "100%"
  elif [ $DiskSize -gt 10 ]; then                   # ------ /root & /swap partitions only ------
    RootSize=$((DiskSize-1))                        # /root 9 to 17GiB, /swap 1GiB
    partition_maker "${StartPoint}" "${RootSize}GiB" "" "100%"
  else                                              # ------ Swap file and /root partition only -----
    partition_maker "${StartPoint}" "100%" "" ""
    SwapFile="2G"                                   # Swap file
    SwapPartition=""                                # Clear swap partition variable
  fi
  partprobe 2>> feliz.log                           # Inform kernel of changes to partitions
  return 0
}

function mount_partitions { # Called without arguments by feliz.sh after action_UEFI or action_EFI
    install_message "Preparing and mounting partitions"
    # First unmount any mounted partitions !!! Why? Feliz is running in a new Arch session. Nothing is mounted.
  #  umount ${RootPartition} /mnt 2>> feliz.log                        # eg: umount /dev/sda1
  # 1) Root partition
    if [ $RootType = "" ]; then
      echo "Not formatting root partition" >> feliz.log               # If /root filetype not set - do nothing
    else                                                              # Check if replacing existing ext3/4 with btrfs
      CurrentType=$(file -sL ${RootPartition} | grep 'ext\|btrfs' | cut -c26-30) 2>> feliz.log
      # Check if /root type or existing partition are btrfs ...
      if [ -n "$CurrentType" ] && [ "$RootType" = "btrfs" ] && [ "$CurrentType" != "btrfs" ]; then
        btrfs-convert ${RootPartition} 2>> feliz.log                  # Convert existing partition to btrfs
      elif [ "$RootType" = "btrfs" ]; then                            # Otherwise, for btrfs /root
        mkfs.btrfs -f ${RootPartition} 2>> feliz.log                  # eg: mkfs.btrfs -f /dev/sda2
      elif [ "$RootType" = "xfs" ]; then                              # Otherwise, for xfs /root
        mkfs.xfs -f ${RootPartition} 2>> feliz.log                    # eg: mkfs.xfs -f /dev/sda2
      else                                                            # /root is not btrfs
        Partition=${RootPartition: -4}                                # Last 4 characters (eg: sda1)
        Label="${Labelled[${Partition}]}"                             # Check to see if it has a label
        if [ -n "$Label" ]; then                                      # If it has a label ...
          Label="-L $Label"                                           # ... prepare to use it
        fi
        mkfs.${RootType} ${Label} ${RootPartition} &>> feliz.log
      fi                                                              # eg: mkfs.ext4 -L Arch-Root /dev/sda1
    fi
    mount ${RootPartition} /mnt 2>> feliz.log                         # eg: mount /dev/sda1 /mnt
  # 2) EFI (if required)
    if [ "$UEFI" -eq 1 ] && [ "$DualBoot" = "N" ]; then               # Check if /boot partition required
      mkfs.vfat -F32 ${EFIPartition} 2>> feliz.log                    # Format EFI boot partition
      mkdir -p /mnt/boot                                              # Make mountpoint
      parted_script "set 1 boot on"                                   # Make bootable
      mount ${EFIPartition} /mnt/boot                                 # Mount it
    fi
  # 3) Swap
    if [ $SwapPartition ]; then
      swapoff -a 2>> feliz.log                                        # Make sure any existing swap cleared
      if [ "$MakeSwap" = "Y" ]; then
        Partition=${SwapPartition: -4}                                # Last 4 characters (eg: sda2)
        Label="${Labelled[${Partition}]}"                             # Check for label
        if [ -n "$Label" ]; then
          Label="-L ${Label}"                                         # Prepare label
        fi
        mkswap ${Label} ${SwapPartition} 2>> feliz.log                # eg: mkswap -L Arch-Swap /dev/sda2
      fi
      swapon ${SwapPartition} 2>> feliz.log                           # eg: swapon /dev/sda2
    fi
  # 4) Any additional partitions (from the related arrays AddPartList, AddPartMount & AddPartType)
    local Counter=0
    for id in ${AddPartList}; do                                      # $id will be in the form /dev/sda2
      umount ${id} /mnt${AddPartMount[$Counter]} >> feliz.log
      mkdir -p /mnt${AddPartMount[$Counter]} 2>> feliz.log            # eg: mkdir -p /mnt/home
      # Check if replacing existing ext3/4 partition with btrfs (as with /root)
      CurrentType=$(file -sL ${AddPartType[$Counter]} | grep 'ext\|btrfs' | cut -c26-30) 2>> feliz.log
      if [ "${AddPartType[$Counter]}" = "btrfs" ] && [ ${CurrentType} != "btrfs" ]; then
        btrfs-convert ${id} 2>> feliz.log
      elif [ "${AddPartType[$Counter]}" = "btrfs" ]; then
        mkfs.btrfs -f ${id} 2>> feliz.log                             # eg: mkfs.btrfs -f /dev/sda2
      elif [ "${AddPartType[$Counter]}" = "xfs" ]; then
        mkfs.xfs -f ${id} 2>> feliz.log                               # eg: mkfs.xfs -f /dev/sda2
      elif [ "${AddPartType[$Counter]}" != "" ]; then                 # Only format if type has been set
        Partition=${id: -4}                                           # Last 4 characters of ${id}
        Label="${Labelled[${Partition}]}"
        if [ -n "${Label}" ]; then
          Label="-L ${Label}"                                         # Prepare label
        fi
        mkfs.${AddPartType[$Counter]} ${Label} ${id} &>> feliz.log    # eg: mkfs.ext4 -L Arch-Home /dev/sda3
      fi
      mount ${id} /mnt${AddPartMount[$Counter]} &>> feliz.log         # eg: mount /dev/sda3 /mnt/home
      Counter=$((Counter+1))
    done
  return 0
}

function install_kernel { # Called without arguments by feliz.sh
                          # Installs selected kernel and some other core systems
  LANG=C                  # Set the locale for all processes run from the current shell 

  # Solve keys issue if an older Feliz or Arch iso is running after keyring changes
  # Passes test if the date of the running iso is more recent than the date of the latest Arch
  # trust update. Next trust update due 2018:06:25
  # Use blkid to get details of the Feliz or Arch iso that is running, in the form yyyymm
  RunningDate=$(blkid | grep "feliz\|arch" | cut -d'=' -f3 | cut -d'-' -f2 | cut -b-6)
  TrustDate=201710                                                # Reset this to date of latest Arch Linux trust update
                                                                  # Next trustdb check 2018-10-20
  if [ "$RunningDate" -ge "$TrustDate" ]; then                    # If the running iso is more recent than
    echo "pacman-key trust check passed" >> feliz.log             # the last trust update, no action is taken
  else                                                            # But if the iso is older than the last trust
    install_message "Updating keys"                               # update then the keys are updated
    pacman-db-upgrade
    pacman-key --init
    pacman-key --populate archlinux
    pacman-key --refresh-keys
    pacman -Sy --noconfirm archlinux-keyring
  fi
  translate "Installing"
  Message="$Result"
  translate "kernel and core systems"
  install_message "$Message $Result"
  case $Kernel in
  1) # This is the full linux group list at 1st August 2017 with linux-lts in place of linux
      # Use the script ArchBaseGroup.sh in FelizWorkshop to regenerate the list periodically
    pacstrap /mnt autoconf automake bash binutils bison bzip2 coreutils cryptsetup device-mapper dhcpcd diffutils e2fsprogs fakeroot file filesystem findutils flex gawk gcc gcc-libs gettext glibc grep groff gzip inetutils iproute2 iputils jfsutils less libtool licenses linux-lts logrotate lvm2 m4 make man-db man-pages mdadm nano netctl pacman patch pciutils pcmciautils perl pkg-config procps-ng psmisc reiserfsprogs sed shadow s-nail sudo sysfsutils systemd-sysvcompat tar texinfo usbutils util-linux vi which xfsprogs 2>> feliz.log ;;
  *) pacstrap /mnt base base-devel 2>> feliz.log
  esac
  translate "cli tools"
  install_message "$Message $Result"
  pacstrap /mnt btrfs-progs gamin gksu gvfs ntp wget openssh os-prober screenfetch unrar unzip vim xarchiver xorg-xedit xterm 2>> feliz.log
  arch_chroot "systemctl enable sshd.service" >> feliz.log
  return 0
}

function add_codecs { # Called without arguments by feliz.sh
  translate "Installing"
  install_message "$Result codecs"
  pacstrap /mnt a52dec autofs faac faad2 flac lame libdca libdv libmad libmpeg2 libtheora
  pacstrap /mnt libvorbis libxv wavpack x264 gstreamer gst-plugins-base gst-plugins-good
  pacstrap /mnt pavucontrol pulseaudio pulseaudio-alsa libdvdcss dvd+rw-tools dvdauthor dvgrab 2>> feliz.log
  translate "Wireless Tools"
  Message="$Result"
  translate "Installing"
  install_message "$Result $Message"
  pacstrap /mnt b43-fwcutter ipw2100-fw ipw2200-fw zd1211-firmware 2>> feliz.log
  pacstrap /mnt iw wireless_tools wpa_supplicant 2>> feliz.log
  # Note that networkmanager and network-manager-applet are installed separately by feliz.sh
  translate "Graphics tools"
  Message="$Result"
  translate "Installing"
  install_message "$Result $Message"
  pacstrap /mnt xorg xorg-xinit xorg-twm 2>> feliz.log
  translate "opensource video drivers"
  Message="$Result"
  translate "Installing"
  install_message "$Result $Message"
  pacstrap /mnt xf86-video-vesa xf86-video-nouveau xf86-input-synaptics 2>> feliz.log
  translate "fonts"
  Message="$Result"
  translate "Installing"
  install_message "$Result $Message"
  pacstrap /mnt ttf-liberation 2>> feliz.log

  # install_message "Installing  CUPS printer services"
  # pacstrap /mnt -S system-config-printer cups
  # arch_chroot "systemctl enable org.cups.cupsd.service"
  return 0
}

function mirror_list {  # Use rankmirrors (script in /usr/bin/ from Arch) to generate fast mirror list
                        # User has selected one or more countries with Arch Linux mirrors
                        # These have been stored in the array CountryLong
                        # Now the mirrors associated with each of those countries must be extracted from the array
  install_message "Generating mirrorlist"
  cp /etc/pacman.d/mirrorlist /etc/pacman.d/mirrorlist.safe 2>> feliz.log

  if [ -f mirrors.list ] && [ $(wc mirrors.list) -gt 1 ]; then  # If user has entered a manual list of one or more mirrors
    install_message "Ranking mirrors - please wait ..."
    Date=$(date)
    echo -e "# Ranked mirrors /etc/pacman.d/mirrorlist \n# $Date \n# Generated by ${user_name} and rankmirrors\n#" > /etc/pacman.d/mirrorlist
    rankmirrors -n 5 mirrors.list | grep '^Server' >> /etc/pacman.d/mirrorlist
  elif [ ${#CountryLong[@]} -eq 0 ]; then  # If no mirrors were cosen by user ...
    install_message "Ranking mirrors - please wait ..."
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
  else # Get addresses of mirrors in the country selected by the user
    if [ -f usemirrors.list ]; then rm usemirrors.list; fi
    for Country in "${CountryLong[@]}"; do    # Prepare file of mirrors to be used
        # Get the line number of $Country in $CountryLong in allmirrors.list
        #                      exact match only | restrict to first find | display only number
      CountryLine=$(grep -n "${Country}" allmirrors.list | head -n 1 | cut -d':' -f1)
      # Read each line from that line onwards until an empty line is encountered (end of country)
      while true; do
        CountryLine=$((CountryLine+1))                                                    # Next line
        MirrorURL="$(head -n ${CountryLine} allmirrors.list | tail -n 1 | cut -d'#' -f2)" # Read next item in source file
        echo "$MirrorURL" >> usemirrors.list                                              # Save it to usemirrors.list file
        if [ -z "$MirrorURL" ]; then
          break
        else
          translate "Loading"
          echo "$Result $Country $MirrorURL"
        fi
      done
    done
    translate "Ranking mirrors - please wait"
    install_message "$Result ..."
    Date=$(date)
    echo -e "# Ranked mirrors /etc/pacman.d/mirrorlist \n# $Date \n# Generated by Feliz and rankmirrors\n#" > /etc/pacman.d/mirrorlist
    rankmirrors -n 5 usemirrors.list | grep '^Server' >> /etc/pacman.d/mirrorlist
  fi
  return 0
}

function install_display_manager { # Disable any existing display manager
  arch_chroot "systemctl disable display-manager.service" >> feliz.log
  # Then install selected display manager
  translate "Installing"
  install_message "$Result " "${DisplayManager}"
  case ${DisplayManager} in
  "lightdm") pacstrap /mnt lightdm lightdm-gtk-greeter 2>> feliz.log
    arch_chroot "systemctl -f enable lightdm.service" >> feliz.log ;;
  *) pacstrap /mnt "${DisplayManager}" 2>> feliz.log
    arch_chroot "systemctl -f enable ${DisplayManager}.service" >> feliz.log
  esac
  return 0
}

function install_extras { # Install desktops and other extras for FelizOB (note that $LuxuriesList 
                          # and $DisplayManager are empty, so their routines will not be called)
  if [ $DesktopEnvironment = "FelizOB" ]; then
    translate "Installing"
    install_message "$Result FelizOB"
    arch_chroot "systemctl disable display-manager.service" 2>> feliz.log
    pacstrap /mnt lxdm 2>> feliz.log
    arch_chroot "systemctl -f enable lxdm.service" >> feliz.log
    pacstrap /mnt openbox 2>> feliz.log                                               # First ensure that Openbox gets installed
    pacstrap /mnt obmenu obconf 2>> feliz.log                                         # Then Openbox tools
    pacstrap /mnt lxde-icon-theme leafpad lxappearance lxinput lxpanel 2>> feliz.log  # Then LXDE tools
    pacstrap /mnt lxrandr lxsession lxtask lxterminal pcmanfm 2>> feliz.log           # more LXDE tools
    pacstrap /mnt compton conky gpicview midori xscreensaver 2>> feliz.log            # Add some extras
    cp lxdm.conf /mnt/etc/lxdm/                                                       # Copy the LXDM config file
    install_yaourt                                                                    # And install Yaourt
  fi
  # Display manager - runs only once
  if [ -n "${DisplayManager}" ]; then             # Not triggered by FelizOB or Gnome
    install_display_manager                       # Clear any pre-existing DM and install this one
  fi
  # First parse through LuxuriesList checking for DEs and Window Managers (not used by FelizOB)
  if [ -n "${LuxuriesList}" ]; then
    for i in ${LuxuriesList}; do
      translate "Installing"
      case $i in
      "Awesome") install_message "$Result Awesome"
          pacstrap /mnt awesome 2>> feliz.log ;;
      "Budgie") install_message "$Result Budgie"
          pacstrap /mnt budgie-desktop 2>> feliz.log ;;
      "Cinnamon") install_message "$Result Cinnamon"
          pacstrap /mnt cinnamon 2>> feliz.log ;;
      "Deepin") install_message "$Result Deepin"
          pacstrap /mnt deepin 2>> feliz.log
          pacstrap /mnt deepin-extra 2>> feliz.log ;;
      "Enlightenment") install_message "$Result Enlightenment"
          pacstrap /mnt enlightenment connman terminology 2>> feliz.log ;;
      "Fluxbox") install_message "$Result Fluxbox"
          pacstrap /mnt fluxbox 2>> feliz.log ;;
      "Gnome") install_message "$Result Gnome"
          pacstrap /mnt gnome 2>> feliz.log
          pacstrap /mnt gnome-extra 2>> feliz.log
          arch_chroot "systemctl -f enable gdm.service" >> feliz.log ;;
      "i3") install_message "$Result i3 window manager"
          pacstrap /mnt i3 2>> feliz.log ;;                           # i3 group includes i3-wm
      "Icewm") install_message "$Result Icewm"
          pacstrap /mnt icewm 2>> feliz.log ;;
      "JWM") install_message "$Result JWM"
          pacstrap /mnt jwm 2>> feliz.log ;;
      "KDE") install_message "$Result KDE Plasma"
          pacstrap /mnt plasma-meta 2>> feliz.log
          pacstrap /mnt kde-applications 2>> feliz.log ;;
      "LXDE") install_message "$Result LXDE"
          pacstrap /mnt lxde leafpad 2>> feliz.log
          if [ -d /mnt/etc/lxdm ]; then
            echo "session=/usr/bin/startlxde" >> /mnt/etc/lxdm/lxdm.conf 2>> feliz.log
          fi ;;
      "LXQt") install_message "$Result LXQt"
          pacstrap /mnt lxqt 2>> feliz.log
          pacstrap /mnt oxygen-icons connman lxappearance xscreensaver 2>> feliz.log ;;
      "Mate") install_message "$Result Mate"
        pacstrap /mnt mate mate-extra 2>> feliz.log
        pacstrap /mnt mate-applet-dock mate-applet-streamer mate-menu 2>> feliz.log ;;
      "Openbox") install_message "$Result Openbox"
        pacstrap /mnt openbox 2>> feliz.log ;;
      "Windowmaker") install_message "$Result Windowmaker"
        pacstrap /mnt windowmaker 2>> feliz.log
        pacstrap /mnt windowmaker-extra 2>> feliz.log ;;
      "Xfce") install_message "$Result Xfce"
        pacstrap /mnt xfce4 2>> feliz.log
        pacstrap /mnt xfce4-goodies 2>> feliz.log ;;
      "Xmonad") install_message "$Result Xmonad"
        pacstrap /mnt xmonad 2>> feliz.log
        pacstrap /mnt xmonad-contrib 2>> feliz.log ;;
      *) continue                                                     # Ignore all others on this pass
      esac
    done
    install_yaourt
    # Second parse through LuxuriesList for any extras (not triggered by FelizOB)
    for i in ${LuxuriesList}; do
        translate "Installing"
      case $i in
      "Awesome"|"Budgie"|"Cinnamon"|"Deepin"|"Enlightenment"|"Fluxbox"|"Gnome"|"i3"|"Icewm"|"JWM"|"KDE"|"LXDE"|"LXQt"|"Mate"|"Openbox"|"Windowmaker"|"Xfce"|"Xmonad") continue ;; # Ignore DEs & WMs on this pass
      "cairo-dock") install_message "$Result Cairo Dock"
        pacstrap /mnt cairo-dock cairo-dock-plug-ins 2>> feliz.log ;;
      "conky") install_message "$Result Conky"
        pacstrap /mnt conky 2>> feliz.log ;;
      *) install_message "$Result $i"
        pacstrap /mnt "$i" 2>> feliz.log
      esac
    done
  fi
  return 0
}

function install_yaourt {
  translate "Installing"
  install_message "$Result Yaourt"
  arch=$(uname -m)
  if [ ${arch} = "x86_64" ]; then                                     # Identify 64 bit architecture
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
  return 0
}

function user_add { # Adds user and copies FelizOB configurations
  CheckUsers=`cat /mnt/etc/passwd | grep ${user_name}`
  # If not already exist, create user
  if [ -z "${CheckUsers}" ]; then
    translate "Adding user and setting up groups"
    install_message "$Result"
    arch_chroot "useradd ${user_name} -m -g users -G wheel,storage,power,network,video,audio,lp -s /bin/bash"
    # Set up basic configuration files and permissions for user
    arch_chroot "cp /etc/skel/.bashrc /home/${user_name}"
    arch_chroot "chown -R ${user_name}:users /home/${user_name}"
    sed -i '/%wheel ALL=(ALL) ALL/s/^#//' /mnt/etc/sudoers 2>> feliz.log
  fi
  # Create main user folders
  translate "Desktop Documents Downloads Music Pictures Public Templates Videos"
  for i in ${Result}; do
    arch_chroot "mkdir /home/${user_name}/${i}"
    arch_chroot "chown -R ${user_name}: /home/${user_name}/${i}"
  done
  # FelizOB
  if [ $DesktopEnvironment = "FelizOB" ]; then
    # Set up directories
    arch_chroot "mkdir -p /home/${user_name}/.config/openbox/"
    arch_chroot "mkdir -p /home/${user_name}/.config/pcmanfm/default/"
    arch_chroot "mkdir -p /home/${user_name}/.config/lxpanel/default/panels/"
    arch_chroot "mkdir /home/${user_name}/Pictures/"
    arch_chroot "mkdir /home/${user_name}/.config/libfm/"
    # Copy FelizOB files
    cp -r themes /mnt/home/${user_name}/.themes 2>> feliz.log          # Copy egtk theme
    check_existing "/mnt/home/${user_name}/" ".conkyrc"
    cp conkyrc /mnt/home/${user_name}/.conkyrc 2>> feliz.log           # Conky config file
    check_existing "/mnt/home/${user_name}/" ".compton.conf"
    cp compton.conf /mnt/home/${user_name}/.compton.conf 2>> feliz.log # Compton config file
    check_existing "/mnt/home/${user_name}/" ".face"
    cp face.png /mnt/home/${user_name}/.face 2>> feliz.log             # Image for greeter
    check_existing "/mnt/home/${user_name}/.config/openbox/" "autostart"
    cp autostart /mnt/home/${user_name}/.config/openbox/ 2>> feliz.log # Autostart config file
    check_existing "/mnt/home/${user_name}/.config/openbox/" "menu.xml"
    cp menu.xml /mnt/home/${user_name}/.config/openbox/ 2>> feliz.log  # Openbox menu config file
    check_existing "/mnt/home/${user_name}/.config/openbox/" "rc.xml"
    cp rc.xml /mnt/home/${user_name}/.config/openbox/ 2>> feliz.log    # Openbox config file
    check_existing "/mnt/home/${user_name}/.config/lxpanel/default/panels/" "panel"
    cp panel /mnt/home/${user_name}/.config/lxpanel/default/panels/ 2>> feliz.log  # Panel config file
    cp feliz.png /mnt/usr/share/icons/ 2>> feliz.log                   # Icon for panel menu
    cp wallpaper.jpg /mnt/home/${user_name}/Pictures/ 2>> feliz.log    # Wallpaper for user
    check_existing "/mnt/home/${user_name}/.config/libfm/" "libfm.conf"
    cp libfm.conf /mnt/home/${user_name}/.config/libfm/ 2>> feliz.log  # Configs for pcmanfm
    check_existing "/mnt/home/${user_name}/.config/lxpanel/default/" "config"
    cp config /mnt/home/${user_name}/.config/lxpanel/default/ 2>> feliz.log # Desktop configs for pcmanfm
    check_existing "/mnt/home/${user_name}/.config/pcmanfm/default/" "desktop-items-0.conf"
    cp desktop-items /mnt/home/${user_name}/.config/pcmanfm/default/desktop-items-0.conf 2>> feliz.log # Desktop configurations for pcmanfm
    cp wallpaper.jpg /mnt/usr/share/ 2>> feliz.log
    # Set owner
    arch_chroot "chown -R ${user_name}:users /home/${user_name}/"
  fi
  # Set keyboard at login for user
  arch_chroot "localectl set-x11-keymap $Countrykbd"
  case $Countrykbd in
  "uk") echo "setxkbmap -layout gb" >> /mnt/home/${user_name}/.bashrc 2>> feliz.log ;;
  *) echo "setxkbmap -layout $Countrykbd" >> /mnt/home/${user_name}/.bashrc 2>> feliz.log
  esac
  return 0
}

function check_existing {     # Test if $1 (path) + $2 (file) already exists
  if [ -f "$1$2" ]; then      # If path+file already exists
      mv "$1$2" "$1saved$2"   # Rename it
  fi
  return 0
}

function set_root_password {
  translate "Success!"
  title="$Result"
  translate "minutes"
  mins="$Result"
  translate "seconds"
  secs="$Result"
  message_first_line "Finished installing in"
  Message="$Message ${DIFFMIN} $mins ${DIFFSEC} ${secs}\n"
  message_subsequent "Finally we need to set passwords"
  Message="${Message}\n"
  message_subsequent "Note that you will not be able to"
  message_subsequent "see passwords as you enter them"
  Message="${Message}\n"
  Repeat="Y"
  while [ $Repeat = "Y" ]; do
    message_subsequent "Enter a password for"
    Message="${Message} root\n"
    dialog --backtitle "$Backtitle" --title " $title " --insecure --nocancel \
      --ok-label "$Ok" --passwordbox "$Message" 16 60 2>output.file
    Pass1=$(cat output.file)
    rm output.file
    translate "Re-enter the password for"
    Message="${Message} root\n"
    dialog --backtitle "$Backtitle" --insecure --title " Root " --ok-label "$Ok" --nocancel --passwordbox "$Result root\n" 10 50 2>output.file
    Pass2=$(cat output.file)
    rm output.file
    if [ -z ${Pass1} ] || [ -z ${Pass2} ]; then
      title="Error"
      message_first_line "Passwords cannot be blank"
      message_subsequent "Please try again"
      Message="${Message}\n"
      message_subsequent "Note that you will not be able to"
      message_subsequent "see passwords as you enter them"
      Message="${Message}\n"
      continue
    fi
    if [ $Pass1 = $Pass2 ]; then
     echo -e "${Pass1}\n${Pass2}" > /tmp/.passwd
     arch_chroot "passwd root" < /tmp/.passwd >> feliz.log
     rm /tmp/.passwd 2>> feliz.log
     Repeat="N"
    else
      title="Error"
      message_first_line "Passwords don't match"
      message_subsequent "Please try again"
      Message="${Message}\n"
      message_subsequent "Note that you will not be able to"
      message_subsequent "see passwords as you enter them"
      Message="${Message}\n"
    fi
  done
  return 0
}

function set_user_password {
  message_first_line "Enter a password for"
  Message="${Message} ${user_name}\n"
  Repeat="Y"
  while [ $Repeat = "Y" ]; do
    message_subsequent "Note that you will not be able to"
    message_subsequent "see passwords as you enter them"
    Message="${Message}\n"
    dialog --backtitle "$Backtitle" --title " $user_name " --insecure \
      --ok-label "$Ok" --nocancel --passwordbox "$Message" 15 50 2>output.file
    Pass1=$(cat output.file)
    rm output.file
    message_first_line "Re-enter the password for"
    Message="${Message} $user_name\n"
    dialog --backtitle "$Backtitle" --title " $user_name " --insecure \
      --ok-label "$Ok" --nocancel --passwordbox "$Message" 10 50 2>output.file
    Pass2=$(cat output.file)
    rm output.file
    if [ -z ${Pass1} ] || [ -z ${Pass2} ]; then
      title="Error"
      message_first_line "Passwords cannot be blank"
      message_subsequent "Please try again"
      Message="${Message}\n"
      message_subsequent "Note that you will not be able to"
      message_subsequent "see passwords as you enter them"
      Message="${Message}\n"
      continue
    fi
    if [ $Pass1 = $Pass2 ]; then
     echo -e "${Pass1}\n${Pass2}" > /tmp/.passwd
     arch_chroot "passwd ${user_name}" < /tmp/.passwd >> feliz.log
     rm /tmp/.passwd 2>> feliz.log
     Repeat="N"
    else
      title="Error"
      message_first_line "Passwords don't match"
      message_subsequent "Please try again"
      Message="${Message}\n"
      message_subsequent "Note that you will not be able to"
      message_subsequent "see passwords as you enter them"
      Message="${Message}\n"
    fi
  done
  return 0
}

function finish {
  translate "Shutdown Reboot"
  Item1="$(echo $Result | cut -d' ' -f1)"
  Item2="$(echo $Result | cut -d' ' -f2)"
  dialog --backtitle "$Backtitle" --title " Finish "  --ok-label "$Ok" \
    --cancel-label "$Cancel" --menu "$Backtitle" 12 30 2 \
      1 "$Item1" \
      2 "$Item2" 2>output.file
  retval=$?
  Result="$(cat output.file)"
  rm output.file
  case $Result in
  1) shutdown -h now ;;
  2) reboot ;;
  *) exit
  esac
  return 0
}

function partition_maker {  # Called from autopart for autopartitioning both EFI and BIOS systems
                            # Uses GNU Parted to create partitions as defined
                            # Receives up to 4 arguments
                            #   $1 is the starting point of the first partition
                            #   $2 is size of root partition
                            #   $3 if passed is size of home partition
                            #   $4 if passed is size of swap partition
                            # Appropriate partition table has already been created in autopart
                            # If EFI the /boot partition has also been created at /dev/sda1 and
                            # set as bootable, and the startpoint has been set to follow /boot
  local StartPoint=$1 
                                                    # Set the device to be used to 'set x boot on'    
  MountDevice=1                                     # $MountDevice is numerical - eg: 1 in sda1
                                                    # Start with first partition = [sda]1
  parted_script "mkpart primary ext4 ${StartPoint} ${2}"  # Make /boot at startpoint
                                                          # eg: parted /dev/sda mkpart primary ext4 1MiB 12GiB
  parted_script "set ${MountDevice} boot on"        # eg: parted /dev/sda set 1 boot on
  if [ ${UEFI} -eq 1 ]; then                        # Reset if installing in EFI environment
    MountDevice=2                                   # Next partition after /boot = [sda]2
  fi
  RootPartition="${GrubDevice}${MountDevice}"       # eg: /dev/sda1
  RootType="ext4"
  StartPoint=$2                                     # Increment startpoint for /home or /swap
  MountDevice=$((MountDevice+1))                    # Advance partition numbering for next step

  if [ $3 ]; then
    parted_script "mkpart primary ext4 ${StartPoint} ${3}" # eg: parted /dev/sda mkpart primary ext4 12GiB 19GiB
    AddPartList[0]="${GrubDevice}${MountDevice}"    # eg: /dev/sda3  | add to
    AddPartMount[0]="/home"                         # Mountpoint     | array of
    AddPartType[0]="ext4"                           # Filesystem     | additional partitions
    Home="Y"
    StartPoint=$3                                   # Reset startpoint for /swap
    MountDevice=$((MountDevice+1))                  # Advance partition numbering
  fi

  if [ $4 ]; then
    parted_script "mkpart primary linux-swap ${StartPoint} ${4}" # eg: parted /dev/sda mkpart primary linux-swap 31GiB 100%
    SwapPartition="${GrubDevice}${MountDevice}"
    MakeSwap="Y"
  fi
  return 0
}
