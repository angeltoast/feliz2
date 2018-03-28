#!/bin/bash

# The Feliz2 installation scripts for Arch Linux
# Developed by Elizabeth Mills  liz@feliz.one
# With grateful acknowlegements to Helmuthdu, Carl Duff and Dylan Schacht
# Revision date: 9th January 2018

# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.

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

# Main module

# Include source files
source f-vars.sh      # Global functions, variables and arrays are declared in this module
source f-set.sh       # Functions to set user locale and preferences
source f-part.sh      # Functions concerned with allocating partitions
source f-run.sh       # Functions called during installation

function main {       # Prepare environment, call the four processes in sequence
  
  if [ -f dialogrc ] && [ ! -f .dialogrc ]; then  # Ensure that display of dialogs is controlled
    cp dialogrc .dialogrc
  fi
  
  StartTime=$(date +%s)                           # Installation time is dispalyed at end
  echo "${StartTime}" >> feliz.log
  
  Backtitle=$(head -n 1 README)                   # Will be different for testing or stable

  # Check if on UEFI or BIOS system
  tput setf 0                                     # Change foreground colour to black to hide system messages
  dmesg | grep -q "efi: EFI"                      # Test for EFI (-q tells grep to be quiet)
  if [ $? -eq 0 ]; then                           # check exit code; 0 = EFI, else BIOS
    UEFI=1                                        # Set variable UEFI ON and mount the device
    mount -t efivarfs efivarfs /sys/firmware/efi/efivars 2> feliz.log
  else
    UEFI=0                                        # Set variable UEFI OFF
  fi
  tput sgr0                                       # Reset foreground colour

  timedatectl set-ntp true
    
  while true; do
    the_start                                     # All user interraction takes place in this function
    case $? in                                    # the_start allows progressive 'backing out'
    1) continue ;;                                # Restart on low-level backout
    2) exit ;;                                    # Quit on high-level backout
    esac
      
    if [ "$AutoPart" = "NONE"  ] || [ -z "$AutoPart"  ]; then continue; fi  # Restart if no partitioning options    
    translate "Preparations complete"             # Inform user
    install_message "$Result"
    translate "Entering automatic installation phase"
    install_message "$Result"
  
    preparation                                   # Prepare the environment for the installation phase
    if [ $? -ne 0 ]; then continue; fi            # Restart if error
    
    the_middle                                    # The installation phase
    if [ $? -ne 0 ]; then continue; fi            # Restart if error
  
    the_end                                       # Set passwords and finish Feliz
    if [ $? -ne 0 ]; then exit; fi                # Exit if user selected <Cancel>
  done
}

function the_start {  # All user interraction takes place in this function
                      # Sets variables relating to locality and desktop
  declare -i step=1
  while [ "$step" -gt 0 ]; do
    case "$step" in
    1) set_language                               # In f-vars.sh - Use appropriate language file
      if [ $? -ne 0 ]; then
        return 2                                  # On <Cancel> return backout code to main
      else
        step=2                                    # Step 1 completed, advance to step 2
      fi ;;
    2) # Devices (if only one device detected, no user interaction)
      select_device                               # Detect all available devices & allow user to select
      if [ $? -ne 0 ]; then return 2; fi          # On <Cancel> return backout code to main
      get_device_size                             # First make sure that there is space for installation
      case $? in
       0) step=3 ;;                               # Device selected, advance to step 3
       *) continue                                # No device, rerun this step
      esac ;;
    3) # Check that there are partitions on the device, if not, exit
      check_parts
      case $? in
       0) step=4 ;;                               # Partitions exist, advance to step 4
       *) shutdown -h now                         # Shutdown
      esac ;;
    4) # localisation_settings                    Locale, keyboard & hostname
      setlocale                                   # CountryLocale eg: en_GB.UTF-8
      if [ $? -ne 0 ]; then step=1; continue; fi
      get_keymap                                  # Select keyboard layout eg: uk
      if [ $? -ne 0 ]; then continue; fi
      set_hostname
      case $? in
       0) step=5 ;;                               # Step 3 completed, advance to step 5
       1) continue ;;                             # Backout, rerun this step
       *) step=2 ;;                               # Backout, rerun previous step
      esac ;;
    5) choose_mirrors
      case $? in
       0) step=6 ;;                               # Step completed, advance to desktop settings
       1) continue ;;                             # Backout, rerun this step
       *) step=3 ;;                               # Backout, rerun previous step
      esac ;;
    6) # desktop settings
      DesktopEnvironment=""
      type_of_installation                        # Basic or Full - use chooses Build, FeliOB or Basic
      if [ $? -ne 0 ]; then
        step=1
        continue                                  # No option selected, restart
      fi
      if [ "$Scope" != "Basic" ]; then            # If any extra apps have been added
        if [ -n "$DesktopEnvironment" ] && [ "$DesktopEnvironment" != "FelizOB" ] && [ "$DesktopEnvironment" != "Gnome" ] && [ "$DesktopEnvironment" != "Deepin" ]; then # Deepin, Gnome and FelizOB install their own DM
          choose_display_manager                  # User selects from list of display managers
        fi                                        # Installation can continue without a display manager
        set_username                              # Enter name of primary user; default = "archie"
        wireless_option                           # New option to bypass wireless tools if not needed
        confirm_virtualbox                        # Offer Virtualbox option
       fi
      step=7 ;;                                   # Step completed, advance to partitioning
    7) use_parts                                  # Check partition table & offer partitioning options
      if [ $? -ne 0 ]; then step=1; fi            # User cancelled partitioning options, backout
      if [ "$AutoPart" = "MANUAL" ]; then         # Not Auto partitioned or guided
        allocate_partitions                       # Assign /root /swap & others
      fi
      step=8 ;;                                   # Step completed, advance to next step
    8) select_kernel                              # Select kernel and device for Grub
      if [ $? -ne 0 ]; then step=1; fi            # No kernel selected, backout
      step=9 ;;                                   # Step completed, advance to next step
    9) if [ ${UEFI} -eq 1 ]; then                 # If installing in EFI
        GrubDevice="EFI"                          # Set variable
      else							                          # If BIOS 
        select_grub_device                        # User chooses grub partition
        if [ $? -ne 0 ]; then step=6; fi          # No grub location selected, restart partitioning
      fi
      step=10 ;;                                  # Step completed, advance to next step
    10) final_check                               # Allow user to change any variables
      return $? ;;                                # Exit from final_check may be 0 or 1
    *) step=1                                     # In case other level, restart
    esac
  done
}

function preparation { # Prepare the environment for the installation phase
  if [ "$UEFI" -eq 1 ] && [ "$AutoPart" = "GUIDED" ]; then    # If installing on EFI with Guided partitioning
    action_EFI
  elif [ "$UEFI" -eq 0 ] && [ "$AutoPart" = "GUIDED" ]; then  # If installing on BIOS with Guided partitioning
    action_MBR
  fi

  if [ "$AutoPart" = "AUTO" ]; then                           # If Auto partitioning_options
    autopart 
  elif [ "$AutoPart" = "NONE" ]; then                         # If partitioning_options not set
    Message="No partitions"
    not_found 6 20
    return 1
  fi                                                          # Note that MANUAL allocation was done in f-part1

  mount_partitions                                            # In f-run.sh
  mirror_list                                                 # In f-run.sh
  install_kernel                                              # In f-run.sh
}

function the_middle { # The installation phase
    translate "Preparing local services"
    install_message "$Result"
    echo "$HostName" > /mnt/etc/hostname 2>> feliz.log
    sed -i "/127.0.0.1/s/$/ ${HostName}/" /mnt/etc/hosts 2>> feliz.log
    sed -i "/::1/s/$/ ${HostName}/" /mnt/etc/hosts 2>> feliz.log
  # Set up locale, etc. The local copy of locale.gen may have been manually edited in f-set.sh, so ...
    GrepTest=$(grep "^${CountryLocale}" /etc/locale.gen)                # Check main locale not already set
    if [ -z "$GrepTest" ]; then                                           # If not, add it at bottom
      echo "${CountryLocale} UTF-8" >> /etc/locale.gen 2>> feliz.log    # eg: en_GB.UTF-8 UTF-8
    fi
    GrepTest=$(grep "^en_US.UTF-8" /etc/locale.gen)                     # If secondary locale not already set, and
    if [ "$GrepTest" ] && [ "$GrepTest" = "" ] && [ "${CountryLocale:0:2}" != "en" ]; then # if main is not English
      echo "en_US.UTF-8 UTF-8" >> /etc/locale.gen 2>> feliz.log         # add en_US for completeness
    fi
    cp -f /etc/locale.gen /mnt/etc/                                     # Copy to installed system
    arch_chroot "locale-gen"
    echo "LANG=${CountryLocale}" > /mnt/etc/locale.conf 2>> feliz.log   # eg: LANG=en_US.UTF-8
    export "LANG=${CountryLocale}" 2>> feliz.log                        # eg: LANG=en_US.UTF-8
    arch_chroot "ln -sf /usr/share/zoneinfo/${ZONE}/${SUBZONE} /etc/localtime"
    arch_chroot "hwclock --systohc --utc"
  # Networking
    arch_chroot "systemctl enable dhcpcd.service"
    pacstrap /mnt networkmanager network-manager-applet rp-pppoe 2>> feliz.log
    arch_chroot "systemctl enable NetworkManager.service && systemctl enable NetworkManager-dispatcher.service"
  # Generate fstab and set up swapfile (10 Feb 2018: note that this is also being tested at f-run.sh line 325)
    genfstab -p -U /mnt > /mnt/etc/fstab 2>> feliz.log
    if [ ${SwapFile} ]; then
      fallocate -l ${SwapFile} /mnt/swapfile 2>> feliz.log
      chmod 600 /mnt/swapfile 2>> feliz.log
      mkswap /mnt/swapfile 2>> feliz.log
      swapon /mnt/swapfile 2>> feliz.log
      echo "/swapfile none  swap  defaults  0 0" >> /mnt/etc/fstab 2>> feliz.log
    fi
  # Grub
    translate "Installing"
    install_message "$Result " "Grub"
    if [ "${GrubDevice}" = "EFI" ]; then                        # Installing grub in UEFI environment
      pacstrap /mnt grub efibootmgr
      arch_chroot "grub-install --efi-directory=/boot --target=x86_64-efi --bootloader-id=boot ${GrubDevice}"
      if [ "$IsInVbox" = "VirtualBox" ]; then                 # Prepare for Virtualbox
        mv /mnt/boot/EFI/boot/grubx64.efi /mnt/boot/EFI/boot/bootx64.efi 2>> feliz.log
      fi
      arch_chroot "os-prober"
      arch_chroot "grub-mkconfig -o /boot/grub/grub.cfg"
    elif [ -n "${GrubDevice}" ]; then                           # Installing grub in BIOS environment
      pacstrap /mnt grub 2>> feliz.log
      arch_chroot "grub-install --target=i386-pc --recheck ${GrubDevice}"
      arch_chroot "os-prober"
      arch_chroot "grub-mkconfig -o /boot/grub/grub.cfg"
    else                                                      # No grub device selected
      echo "Not installing Grub" >> feliz.log
    fi
  # Set keyboard to selected language at next startup
    echo KEYMAP="$Countrykbd" > /mnt/etc/vconsole.conf 2>> feliz.log
    echo -e "Section \"InputClass\"\nIdentifier \"system-keyboard\"\nMatchIsKeyboard \"on\"\nOption \"XkbLayout\" \"${Countrykbd}\"\nEndSection" > /mnt/etc/X11/xorg.conf.d/00-keyboard.conf 2>> feliz.log
  # Extra processes for desktop installation
    if [ $Scope != "Basic" ]; then
      add_codecs                                               # Various bits
      if [ "$IsInVbox" = "VirtualBox" ]; then                  # If in Virtualbox
        translate="Installing"
        install_message "$Result " "Virtualbox Guest Modules"
        translate="Y"
        case $Kernel in
        1) pacstrap /mnt dkms linux-lts-headers 2>> feliz.log  # LTS kernel
          pacstrap /mnt virtualbox-guest-dkms 2>> feliz.log ;;
        *) pacstrap /mnt dkms linux-headers 2>> feliz.log      # Latest kernel
          pacstrap /mnt virtualbox-guest-modules-arch 2>> feliz.log
        esac
        pacstrap /mnt virtualbox-guest-utils 2>> feliz.log
        arch_chroot "systemctl enable vboxservice"
      fi
      install_extras                                           # Install DEs, WMs and DMs
      user_add
    fi
}

function the_end { # Set passwords and finish Feliz
  EndTime=$(date +%s)                                         # The end of life as we know it
  Difference=$(( EndTime-StartTime ))
  DIFFMIN=$(( Difference / 60 ))
  DIFFSEC=$(( Difference % 60 ))
  set_root_password
  if [ $Scope != "Basic" ]; then set_user_password; fi
  cp feliz.log /mnt/etc                                        # Copy installation log for reference
  finish                                                       # Shutdown or reboot
}

main
