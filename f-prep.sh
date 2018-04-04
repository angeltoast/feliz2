#!/bin/bash

# The Feliz installation scripts for Arch Linux
# Developed by Elizabeth Mills
# With grateful acknowlegements to Helmuthdu, Carl Duff and Dylan Schacht
# Revision date: 4th April 2018

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
# The Free Software Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.

# In this module - functions for guided creation of a GPT or EFI partition table
#                  and partitions, and functions for autopartitioning
# ------------------------    ----------------------
# Functions           Line    Functions         Line 
# ------------------------    ----------------------
# auto_warning          36    guided_message     162
# autopart              46    guided_partitions  172
# prepare_device        72    guided_recalc      216
# prepare_partitions    92    guided_root        243
# select_filesystem    142    guided_home        286
# display_results      435    guided_swap        336
# ------------------------    ----------------------

function auto_warning
{
  message_first_line "This will erase any data on"
  Message="$Message $RootDevice"
  message_subsequent "Are you sure you wish to continue?"
  dialog --backtitle "$Backtitle" --title " Auto-partition " \
    --yes-label "$Yes" --no-label "$No" --yesno "\n$Message" 9 50
  retval=$?
}

function autopart   # Consolidated fully automatic partitioning for BIOS or EFI environment
{                   # Called by f-part.sh/check_parts (after auto_warning)
  prepare_device                                    # Create partition table and device variables
  RootType="ext4"                                   # Default for auto
  HomeType="ext4"                                   # Default for auto
  # Decide partition sizes based on device size
  if [ $DiskSize -ge 40 ]; then                     # ------ /root /home /swap partitions ------
    HomeSize=$((DiskSize-15-4))                     # /root 15 GiB, /swap 4GiB, /home from 18GiB
    prepare_partitions "${StartPoint}" "15GiB" "${HomeSize}GiB" "100%"
  elif [ $DiskSize -ge 30 ]; then                   # ------ /root /home /swap partitions ------
    HomeSize=$((DiskSize-15-3))                     # /root 15 GiB, /swap 3GiB, /home 12 to 22GiB
    prepare_partitions "${StartPoint}" "15GiB" "${HomeSize}GiB" "100%"
  elif [ $DiskSize -ge 18 ]; then                   # ------ /root & /swap partitions only ------
    RootSize=$((DiskSize-2))                        # /root 16 to 28GiB, /swap 2GiB
    prepare_partitions "${StartPoint}" "${RootSize}GiB" "0" "100%"
  elif [ $DiskSize -gt 10 ]; then                   # ------ /root & /swap partitions only ------
    RootSize=$((DiskSize-1))                        # /root 9 to 17GiB, /swap 1GiB
    prepare_partitions "${StartPoint}" "${RootSize}GiB" "0" "100%"
  else                                              # ------ Swap file and /root partition only -----
    prepare_partitions "${StartPoint}" "100%" "0" "0"
    SwapFile="2G"                                   # Swap file
    SwapPartition=""                                # Clear swap partition variable
  fi
  AutoPart="AUTO"                                   # Set auto-partition flag
}

function prepare_device # Called by autopart, guided_MBR and guided_EFI
{
  GrubDevice="/dev/${UseDisk}"
  Home="N"                                          # No /home partition at this point
  DiskSize=$(lsblk -l "$RootDevice" | grep "${UseDisk} " | awk '{print $4}' | sed "s/G\|M\|K//g") # Get disk size
  FreeSpace="$((DiskSize*1024))"                    # For guided partitioning
  tput setf 0                                       # Change foreground colour to black to hide error message
  clear

  # Create a new partition table
  if [ ${UEFI} -eq 1 ]; then                        # Installing in UEFI environment
    parted_script "mklabel gpt"                       # Create new filesystem
    parted_script "mkpart primary fat32 1MiB 513MiB"  # EFI boot partition
    StartPoint="513MiB"                             # For next partition
  else                                              # Installing in BIOS environment
    parted_script "mklabel msdos"                   # Create new filesystem
    StartPoint="1MiB"                               # For next partition
  fi

}

function prepare_partitions # Called from autopart for either EFI or BIOS system
{
  # Uses gnu parted to create partitions 
  # Receives up to 4 arguments
  #   $1 is the starting point of the root partition  - 1MiB if MBR, 513MiB if GPT
  #   $2 is size of root partition                    - 8GiB upwards to 100%
  #   $3 is size of home partition or null            - may be xGiB x% or "0"
  #   $4 if passed is size of swap partition          - may be xMiB xGiB x% or "0"
  # Note:
  # An appropriate partition table has already been created in prepare_device
  # If system is EFI, prepare_device has also created the /boot partition at
  #   /dev/${UseDisk} and set it as bootable, and the startpoint
  #    (passed here as $1) has been set to follow /boot
                    
  local StartPoint=$1                               # Local variable 

  # Set the device to be used to 'set x boot on'    # $MountDevice is numerical - eg: 1 in sda1
  MountDevice=1                                     # Start with first partition = [sda]1
                                                    # Make /boot at startpoint
  parted_script "mkpart primary ext4 ${StartPoint} ${2}"   # eg: parted /dev/sda mkpart primary ext4 1MiB 12GiB
  parted_script "set ${MountDevice} boot on"               # eg: parted /dev/sda set 1 boot on
  if [ $UEFI -eq 1 ]; then                          # Reset if installing in EFI environment
    MountDevice=2                                   # Next partition after /boot = [sda]2
  fi
  RootPartition="${GrubDevice}${MountDevice}"       # eg: /dev/sda1
  mkfs."{RootType}" "${RootPartition}" &>> feliz.log   # eg: mkfs.ext4 /dev/sda1
  StartPoint=$2                                     # Increment startpoint for /home or /swap
  MountDevice=$((MountDevice+1))                    # Advance partition numbering for next step

  if [ -n "$3" ] && [ "$3" != "0" ]; then # eg: parted /dev/sda mkpart primary ext4 12GiB 19GiB
    parted_script "mkpart primary ext4 ${StartPoint} ${3}"
    HomePartition="${GrubDevice}${MountDevice}"
    AddPartList[0]="${HomePartition}"               # eg: /dev/sda2  | add to
    AddPartMount[0]="/home"                         # Mountpoint     | array of
    AddPartType[0]="$HomeType"                      # Filesystem     | additional partitions
    Home="Y"
    mkfs."$HomeType" "${HomePartition}" &>> feliz.log  # eg: mkfs.ext4 /dev/sda3
    StartPoint=$3                                   # Reset startpoint for /swap
    MountDevice=$((MountDevice+1))                  # Advance partition numbering
  fi

  if [ -n "$4" ] && [ "$4" != "0" ]; then # eg: parted /dev/sda mkpart primary linux-swap 31GiB 100%
    parted_script "mkpart primary linux-swap ${StartPoint} ${4}"
    SwapPartition="${GrubDevice}${MountDevice}"
    mkswap "$SwapPartition"
    MakeSwap="Y"
  fi
  display_results
}

function select_filesystem # User chooses filesystem from list in global variable ${TypeList}
{
  local Counter=0
  message_first_line "Please select the file system for"
  Message="$Message ${Partition}"
  message_subsequent "It is not recommended to mix the btrfs file-system with others"

  menu_dialog_variable="ext4 ext3 btrfs xfs"
  menu_dialog 16 55 "$_Exit"

  if [ $retval -ne 0 ]; then
    PartitionType=""
    return 1
  else
    PartitionType="$Result"
  fi
}

function guided_message
{
  message_first_line "Here you can set the size and format of the partitions"
  message_subsequent "you wish to create. When ready, Feliz will wipe the disk"
  message_subsequent "and create a new partition table with your settings"
  message_subsequent "$limitations"
  message_subsequent "\nDo you wish to continue?"

  dialog --backtitle "$Backtitle" --title " $title " \
      --yes-label "$Yes" --no-label "$No" --yesno "\n$Message" 12 60
  retval=$?
}

function guided_partitions
{
  limitations="This facility will create /root, /swap and /home"
  guided_message
  if [ $retval -ne 0 ]; then return 1; fi   # If 'No' then return to caller

  prepare_device                            # Create partition table and prepare device size variables
  if [ $? -ne 0 ]; then return 1; fi        # If error then return to caller

  guided_root                               # Prepare $RootSize variable (eg: 9GiB) & $RootType)
  if [ $? -ne 0 ]; then return 1; fi        # If error then return to caller

  guided_recalc "$RootSize"                 # Recalculate remaining space after adding /root
  if [ $? -ne 0 ]; then return 1; fi        # If error then return to caller

  if [ ${FreeSpace} -gt 2 ]; then
    guided_home                             # Prepare $HomeSize & $HomeType
    if [ $? -ne 0 ]; then return 1; fi      # If error then return to caller
    guided_recalc "$HomeSize"               # Recalculate remaining space after adding /home
    if [ $? -ne 0 ]; then return 1; fi      # If error then return to caller
  fi
  
  if [ ${FreeSpace} -gt 1 ]; then
    guided_swap                             # Prepare $SwapSize
    if [ $? -ne 0 ]; then return 1; fi      # If error then return to caller
  else
    message_first_line "There is no space for a /swap partition, but you can"
    message_subsequent "assign a swap-file. It is advised to allow some swap\n"
    message_subsequent "Do you wish to allocate a swapfile?"
    SwapSize="0"
    dialog --backtitle "$Backtitle" --title " $title " \
      --yes-label "$Yes" --no-label "$No" --yesno "\n$Message" 10 60 2>output.file
    
    if [ $? -eq 0 ]; then
      set_swap_file # Note: Global variable SwapFile is set by set_swap_file
                    # and a swap file is created during installation by MountPartitions
    else
      SwapSize="0"
    fi
  fi

  prepare_partitions "${StartPoint}" "${RootSize}" "${HomeSize}" "${SwapSize}" # variables include MiB GiB or %
  AutoPart="GUIDED"                     # Set auto-partition flag
}

function guided_recalc                  # Calculate remaining disk space
{
  local Passed=$1
  Chars=${#Passed}                      # Count characters in variable
  
  if [ ${Passed: -1} = "%" ]; then      # Allow for percentage
    Passed=${Passed:0:Chars-1}          # Passed variable stripped of unit
    Value=$((FreeSpace*100/Passed))     # Convert percentage to value
    Calculator=$Value
  elif [ ${Passed: -1} = "G" ]; then
    Passed=${Passed:0:Chars-1}          # Passed variable stripped of unit
    Calculator=$((Passed*1024))
  elif [ ${Passed: -3} = "GiB" ]; then  
    Passed=${Passed:0:Chars-3}          # Passed variable stripped of unit
    Calculator=$((Passed*1024))
  elif [ ${Passed: -1} = "M" ]; then
    Calculator=${Passed:0:Chars-1}      # (M or MiB) Passed variable stripped of unit
  elif [ ${Passed: -3} = "MiB" ]; then
    Calculator=${Passed:0:Chars-3}      # (M or MiB) Passed variable stripped of unit
  else
    read -p "Error in free-space calculator at line $LINENO"
  fi

  # Recalculate available space
  FreeSpace=$((FreeSpace-Calculator))
}

function guided_root # MBR & EFI Set variables: RootSize, RootType
{
  FreeGigs=$((FreeSpace/1024))

  while true
  do
    # Clear display, show /boot and available space
    if [ $UEFI -eq 1 ]; then
      message_first_line "$BootPartition : ${BootSize}"
      message_subsequent "You now have"
    else
      message_first_line "You have"
    fi
    Message="$Message ${FreeGigs}GiB"
    Message="$Message available on the chosen device"
    message_subsequent "A partition is needed for /root"
    message_subsequent "You can use all the remaining space on the device, if you wish"
    message_subsequent "although you may want to leave room for a /swap partition"
    message_subsequent "and perhaps also a /home partition"
    message_subsequent "The /root partition should not be less than 8GiB"
    message_subsequent "ideally more, up to 20GiB"
    message_subsequent "\nPlease enter the desired size"
     Message="$Message \n [ eg: 12G or 100% ] ... "

    dialog --backtitle "$Backtitle" --title " Root " --ok-label "$Ok" --inputbox "$Message" 18 70 2>output.file
    retval=$?

    if [ $retval -ne 0 ]; then return 1; fi
    Result="$(cat output.file)"
    RESPONSE="${Result^^}"
    # Check that entry includes 'G or M or %'
    CheckInput=${RESPONSE: -1}

    if [ "$CheckInput" != "%" ] && [ "$CheckInput" != "G" ] && [ "$CheckInput" != "M" ]; then
      dialog --backtitle "$Backtitle" --ok-label "$Ok" --msgbox "\nYou must include M or G or %\n" 6 50
      RootSize=""
      continue
    else
      if [ "$CheckInput" = "%" ]; then
        RootSize="${RESPONSE}"
      else
        RootSize="${RESPONSE}iB"
      fi
      Partition="/root"
      select_filesystem
      RootType=${PartitionType}
      break
    fi
  done
}

function guided_home # MBR & EFI Set variables: HomeSize, HomeType
{
  FreeGigs=$((FreeSpace/1024))
  while true
  do
    # Show /root, /swap and available space
    translate "/root partition"
    message_first_line "$Result : ${RootType} : ${RootSize}"
    message_subsequent "You now have"
    Message="$Message ${FreeGigs}GiB"
    Message="$Message available on the chosen device"
    
    message_subsequent "There is space for a"
    translate "/home partition"
    Message="$Message $Result"
    message_subsequent "You can use all the remaining space on the device, if you wish"
    message_subsequent "You may want to leave room for a /swap partition"
    message_subsequent "\nPlease enter the desired size"
    translate "Size"
    message_subsequent "${Result} [ eg: 10G or 0 or 100% ] ... "
    
    dialog --backtitle "$Backtitle" --title " Home " --ok-label "$Ok" --inputbox "$Message" 16 70 2>output.file
    retval=$?
    Result="$(cat output.file)"
    RESPONSE="${Result^^}"

    case ${RESPONSE} in
      "" | 0) HomeSize="0"
          break ;;
      *) # Check that entry includes 'G or M'
          CheckInput=${RESPONSE: -1}
        if [ "$CheckInput" != "%" ] && [ "$CheckInput" != "G" ] && [ "$CheckInput" != "M" ]; then
          dialog --backtitle "$Backtitle" --ok-label "$Ok" --msgbox "\nYou must include M or G or %\n" 8 75
          HomeSize=""
          continue
        else
          if [ "$CheckInput" = "%" ]; then
            HomeSize="${RESPONSE}"
          else
            HomeSize="${RESPONSE}iB"
          fi
          select_filesystem
          HomeType=${PartitionType}
          break
        fi
    esac
  done
}

function guided_swap # MBR & EFI Set variable: SwapSize
{
  # Show /boot and /root
  FreeGigs=$((FreeSpace/1024))
  while true
  do
    if [ ${FreeSpace} -gt 0 ]; then
      # show /root and available space
      translate "/root partition"
      message_first_line "$Result : ${RootType} : ${RootSize}"
      translate "/home partition"
      message_first_line "$Result : ${HomeType} : ${HomeSize}"
      message_subsequent "You now have"
      Message="$Message ${FreeGigs}GiB"
      Message="$Message available on the chosen device"
  
      if [ ${FreeSpace} -gt 10 ]; then
        message_subsequent "There is space for a"
        translate "/swap partition"
        Message="$Message $Result"
        message_subsequent "Swap can be anything from 512MiB upwards but"
        message_subsequent "it is not necessary to exceed 4GiB"
        message_subsequent "You can use all the remaining space on the device, if you wish"
      elif [ ${FreeSpace} -gt 5 ]; then
        message_subsequent "There is space for a"
        Message="$Message $_SwapPartition"
        message_subsequent "Swap can be anything from 512MiB upwards but"
        message_subsequent "it is not necessary to exceed 4GiB"
        message_subsequent "You can use all the remaining space on the device, if you wish"
      else
        message_subsequent "There is just space for a"
        Message="$Message $_SwapPartition"
        message_subsequent "Swap can be anything from 512MiB upwards but"
        message_subsequent "it is not necessary to exceed 4GiB"
        message_subsequent "You can use all the remaining space on the device, if you wish"
      fi
      message_subsequent "\nPlease enter the desired size"
      translate "Size"
      message_subsequent "$Result [ eg: 2G or 0 or 100% ] ... "
  
      dialog --backtitle "$Backtitle" --title " Swap " --ok-label "$Ok" --inputbox "$Message" 16 70 2>output.file
      retval=$?
      Result="$(cat output.file)"
      RESPONSE="${Result^^}"
      case ${RESPONSE} in
        '' | 0) Echo
            message_first_line "Do you wish to allocate a swapfile?"
          dialog --backtitle "$Backtitle" --title " $title " \
              --yes-label "$Yes" --no-label "$No" --yesno "\n$Message" 7 60
          if [ $? -eq 0 ]; then
            set_swap_file
          else
            SwapSize="0"
          fi
          break
        ;;
        *) # Check that entry includes 'G or M or %'
          CheckInput=${RESPONSE: -1}
          if [ "$CheckInput" != "%" ] && [ "$CheckInput" != "G" ] && [ "$CheckInput" != "M" ]; then
            dialog --backtitle "$Backtitle" --ok-label "$Ok" --msgbox "\nYou must include M or G or %\n" 6 50
            SwapSize=""
            continue
          else
            if [ "$CheckInput" = "%" ]; then
              SwapSize="${RESPONSE}"
            else
              SwapSize="${RESPONSE}iB"
            fi
            break
          fi
      esac
    else
      message_first_line "There is no space for a /swap partition, but you can"
      message_subsequent "assign a swap-file. It is advised to allow some swap\n"
      message_subsequent "Do you wish to allocate a swapfile?"
      SwapSize="0"
      dialog --backtitle "$Backtitle" --title " $title " \
        --yes-label "$Yes" --no-label "$No" --yesno "\n$Message" 10 60 2>output.file
      
      if [ $? -eq 0 ]; then
        set_swap_file # Note: Global variable SwapFile is set by set_swap_file
                    # and SwapFile is created during installation by MountPartitions
      else
        SwapSize="0"
      fi
      break
    fi
  done
}

function display_results
{
  lsblk -l "${RootDevice}" > output.file
  p=" "
  while read -r Item; do             # Read items from the output.file file
    p="$p \n $Item"                  # Add to $p with newline after each $Item
  done < output.file

  dialog --backtitle "$Backtitle" --ok-label "$Ok" --msgbox "\n Partitioning of ${GrubDevice} \n $p" 15 70
}
