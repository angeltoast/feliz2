#!/bin/bash

# The Feliz installation scripts for Arch Linux
# Developed by Elizabeth Mills
# With grateful acknowlegements to Helmuthdu, Carl Duff and Dylan Schacht
# Revision date: 30th April 2018

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
# auto_warning          36    guided_partitions  221
# autopart              46    guided_recalc      266
# prepare_device        72    guided_root        293
# prepare_partitions   132    guided_home        360
#                             swap_message       421
# select_filesystem    191    guided_swap        430
# guided_message       208    display_results    544
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
                    # Decide partition sizes based on device size
  prepare_device                                    # Create partition table and device variables
  RootType="ext4"                                   # Default for auto
  HomeType="ext4"                                   # Default for auto
  if [ $DiskSize -ge 50 ]; then                     # ------ /root /home /swap partitions ------
    HomeSize=$((DiskSize-19))                       # /root 15 GiB, /home from 31GiB, /swap 4GiB
    prepare_partitions "${StartPoint}" "15GiB" "${HomeSize}GiB" "100%"
  elif [ $DiskSize -ge 30 ]; then                   # ------ /root /home /swap partitions ------
    HomeSize=$((DiskSize-16))                       # /root 15 GiB, /home 12 to 22GiB, /swap 3GiB
    prepare_partitions "${StartPoint}" "13GiB" "${HomeSize}GiB" "100%"
  elif [ $DiskSize -ge 18 ]; then                   # ------ /root & /swap partitions only ------
    RootSize=$((DiskSize-2))                        # /root 16 to 28GiB, /swap 2GiB
    prepare_partitions "${StartPoint}" "${RootSize}GiB" "0" "100%"
  elif [ $DiskSize -gt 10 ]; then                   # ------ /root & /swap partitions only ------
    RootSize=$((DiskSize-1))                        # /root 9 to 17GiB, /swap 1GiB
    prepare_partitions "${StartPoint}" "${RootSize}GiB" "0" "100%"
  else                                              # ------/root partition &  Swap file only -----
    prepare_partitions "${StartPoint}" "100%" "0" "0"
    SwapFile="2G"                                   # Swap file
    SwapPartition=""                                # Clear swap partition variable
  fi
  AutoPart="AUTO"                                   # Set auto-partition flag
}

function prepare_device # Called by autopart, guided_MBR and guided_EFI
{                       # Create partition table
  GrubDevice="/dev/${UseDisk}"
  Home="N"                                          # No /home partition at this point
  DiskSize=$(lsblk -l "$RootDevice" | grep "${UseDisk} " | awk '{print $4}' | sed "s/G\|M\|K//g" | cut -d'.' -f1) # eg: 149
  get_unit=$(lsblk -l "$RootDevice" | grep "${UseDisk} " | awk '{print $4}') # eg: 149.1G
  disk_unit=${get_unit: -1}                         # eg: G
  case "$disk_unit" in                              # For converting to MiB 
  "G") Factor=1024 ;;
  "M") Factor=1 ;;
  *) Factor=0
  esac
  FreeSpace="$((DiskSize*Factor))"                  # For guided and auto partitioning
  # Create a new partition table
  if [ ${UEFI} -eq 1 ]; then                        # Installing in UEFI environment
    while true
    do
      message_first "A partition is needed for"
      Message="$Message EFI boot"
      message_subsequent "can be anything from 512MiB upwards but"
      Message="EFI boot $Message"
      message_subsequent "it is not necessary to exceed"
      Message="$Message 1024MiB"
      message_subsequent "Please enter the desired size"
      Message="$Message \n [ eg: 550M or 1024M ] ... "
      dialog --backtitle "$Backtitle" --title " EFI boot partition " --ok-label "$Ok" --inputbox "$Message" 18 70 2>output.file
      retval=$?
      # Check input
      if [ $retval -ne 0 ]; then continue 1; fi
      Result="$(cat output.file)"
      if [ $retval -eq 1 ] || [ -z "$Result" ] || [ "$Result" = "0" ]; then
        continue
      else
        RESPONSE="${Result^^}"
      fi
      CheckInput=${RESPONSE: -1}
      if [ "$CheckInput" != "M" ]; then
        continue
      fi
    done
    parted_script "mklabel gpt"                     # Create new filesystem
    parted_script "mkpart ESP fat32 1MiB $RESPONSE" # EFI boot partition
    EFIPartition="${GrubDevice}1"                   # Define EFI partition 
    Chars=${#RESPONSE}                              # Count characters in variable
    efi_size=${RESPONSE:0:Chars-1}                  # $RESPONSE stripped of unit
    FreeSpace="$((FreeSpace-efi_size))"             # For guided partitioning
    mkfs.vfat -F32 ${EFIPartition} 2>> feliz.log    # Format EFI boot partition
    efi_size=$((efi_size+1))
    StartPoint="${efi_size}MiB"                     # For next partition
  else                                              # Installing in BIOS environment
    parted_script "mklabel msdos"                   # Create new filesystem
    StartPoint="1MiB"                               # For next partition
  fi
}

function prepare_partitions # Called from autopart for either EFI or BIOS system
{                           # Uses gnu parted to create partitions 
  # Receives up to 4 arguments
  #   $1 is the starting point of the root partition  - 1MiB if MBR, 513MiB if GPT
  #   $2 is size of root partition                    - 8GiB upwards to 100%
  #   $3 is size of home partition or null            - may be xGiB x% or "0"
  #   $4 if passed is size of swap partition          - may be xMiB xGiB x% or "0"
  # Note:
  # An appropriate partition table has already been created in prepare_device
  # If system is EFI, prepare_device has also created the /boot partition at
  #   /dev/${UseDisk}1 and the startpoint (passed here as $1) has been set to follow /boot

  StartPoint="$1"
  # Set the partition number for parted commands
  if [ $UEFI -eq 1 ]; then                            # eg: 1 in sda1
    MountDevice=2                                     # Next after EFI
  else
    MountDevice=1                                     # Or 1 if not on EFI
  fi
  # 1) Make /root partition at startpoint
  guided_recalc "$1"                                  # Get numeric part of startpoint
  Start="$Calculator"
  guided_recalc "$2"                                  # Get numeric part of root size
  End=$((Start+Calculator))
  EndPoint="${End}MiB"
  parted_script "mkpart primary ext4 ${StartPoint} ${EndPoint}" # eg: parted /dev/sda mkpart primary ext4 1MiB 12000MiB
  RootPartition="${GrubDevice}${MountDevice}"         # eg: /dev/sda2 if there is an EFI partition
  mkfs."{RootType}" "${RootPartition}" &>> feliz.log  # eg: mkfs.ext4 /dev/sda1
  # Set first partition as bootable
  parted_script "set 1 boot on"                       # eg: parted /dev/sda set 1 boot on
  StartPoint="${EndPoint}"                            # For /home or /swap
  MountDevice=$((MountDevice+1))                      # Advance partition numbering for next step
  # 2) Make /home partition at startpoint
  if [ -n "$3" ] && [ "$3" != "0" ]; then
    Start="$End"
    guided_recalc "$3"                                # Get numeric part og home size
    End=$((Start+Calculator))
    EndPoint="${End}MiB"
    parted_script "mkpart primary ext4 ${StartPoint} ${EndPoint}" # eg: parted /dev/sda mkpart primary ext4 12000GiB 19000GiB
    HomePartition="${GrubDevice}${MountDevice}"
    AddPartList[0]="${HomePartition}"                 # eg: /dev/sda2  | add to
    AddPartMount[0]="/home"                           # Mountpoint     | array of
    AddPartType[0]="$HomeType"                        # Filesystem     | additional partitions
    Home="Y"
    mkfs."$HomeType" "${HomePartition}" &>> feliz.log # eg: mkfs.ext4 /dev/sda3
    StartPoint="${EndPoint}"                          # Reset startpoint for /swap
    MountDevice=$((MountDevice+1))                    # Advance partition numbering
  fi
  # 3) Make /swap partition at startpoint
  if [ -n "$4" ] && [ "$4" != "0" ]; then
    EndPoint="${4}"
    parted_script "mkpart primary linux-swap ${StartPoint} ${EndPoint}" # eg: parted /dev/sda mkpart primary linux-swap 31GiB 100%
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
  menu_dialog_variable="ext4 ext3 btrfs xfs None"         # Set the menu elements
  menu_dialog 16 55 "$_Exit"                              # Display the menu
  if [ $retval -ne 0 ] || [ "$Result" == "None" ]; then   # Nothing selected
    PartitionType=""
    return 1
  else
    PartitionType="$Result"
  fi
}

function guided_message # Inform user
{
  message_first_line "Here you can set the size and format of the partitions"
  message_subsequent "you wish to create. When ready, Feliz will wipe the disk"
  message_subsequent "and create a new partition table with your settings"
  message_subsequent "$limitations"
  message_subsequent "Do you wish to continue?"
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
    message_first_line "There is no space for a"
    translate "partition"
    Message="$Message /swap $Result"
    message_subsequent "You can assign a swap-file"
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
  AutoPart="GUIDED"                         # Set auto-partition flag
}

function guided_recalc  # Calculate remaining disk space
{                       # $1 is a partition size eg: 10MiB or 100% or perhaps 0
  if [ -z "$1" ] || [  "$1" == 0 ]; then Calculator=0; return; fi # Just in case
  local Passed
  Chars=${#1}                               # Count characters in variable
  if [ ${1: -1} = "%" ]; then               # Allow for percentage
    Passed=${1:0:Chars-1}                   # Passed variable stripped of unit
    Value=$((FreeSpace*100/Passed))         # Convert percentage to value
    Calculator=$Value
  elif [ ${1: -1} = "G" ]; then
    Passed=${1:0:Chars-1}                   # Passed variable stripped of unit
    Calculator=$((Passed*Factor))
  elif [ ${1: -3} = "GiB" ]; then  
    Passed=${1:0:Chars-3}                   # Passed variable stripped of unit
    Calculator=$((Passed*Factor))
  elif [ ${1: -1} = "M" ]; then
    Calculator=${1:0:Chars-1}               # (M or MiB) Passed variable stripped of unit
  elif [ ${1: -3} = "MiB" ]; then
    Calculator=${1:0:Chars-3}               # (M or MiB) Passed variable stripped of unit
  else
    echo "Error at ${BASH_SOURCE[0]} ${FUNCNAME[0]} line $LINENO"
  fi
  # Recalculate available space
  FreeSpace=$((FreeSpace-Calculator))
}

function guided_root # MBR & EFI Set variables: RootSize, RootType
{
  if [ $Factor -gt 0 ]; then          # Factor is set by prepare_device
    FreeGigs=$((FreeSpace/Factor))
  else
    FreeGigs=0
    Return 1
  fi
  while true
  do
    # Clear display, show /boot and available space
    if [ $UEFI -eq 1 ]; then
      message_first_line "EFI Partition : ${efi_size}MiB"
      message_subsequent "You now have"
    else
      message_first_line "You have"
    fi
    Message="$Message ${FreeGigs}GiB"
    Message="$Message available on the chosen device"
    message_subsequent "A partition is needed for"
    Message="$Message /root"
    message_subsequent "It should not be less than"
    Message="$Message 8GiB"
    message_subsequent "ideally more, up to 20GiB"
    message_subsequent "You can use all the remaining space on the device, if you wish"
    message_subsequent "You may want to leave room for a"
    translate "partition"
    Message="$Message /swap $Result"
    message_subsequent "and perhaps also a"
    translate "partition"
    Message="$Message /home $Result"
    Message="$Message \n"
    message_subsequent "Please enter the desired size"
    Message="$Message \n [ eg: 12G or 100% ] ... "
    dialog --backtitle "$Backtitle" --title " Root " --ok-label "$Ok" --inputbox "$Message" 18 70 2>output.file
    retval=$?
    if [ $retval -ne 0 ]; then continue 1; fi
    Result="$(cat output.file)"
    if [ $retval -eq 1 ] || [ -z "$Result" ] || [ "$Result" = "0" ]; then
        continue        # Cannot be zero or blank
      else
        RESPONSE="${Result^^}"
      fi
    # Check that entry includes 'G or M or %'
    CheckInput=${RESPONSE: -1}
    if [ "$CheckInput" != "%" ] && [ "$CheckInput" != "G" ] && [ "$CheckInput" != "M" ]; then
      translate "You must include M or G or %"
      dialog --backtitle "$Backtitle" --ok-label "$Ok" --msgbox "\n$Result\n" 6 50
      RootSize=""
      continue
    else
      if [ "$CheckInput" = "%" ]; then
        RootSize="${RESPONSE}"
      else
        RootSize="${RESPONSE}iB"
      fi
      Partition="/root"
      create_filesystem
      RootType=${PartitionType}
      break
    fi
  done
}

function guided_home # MBR & EFI Set variables: HomeSize, HomeType
{
  if [ $Factor -gt 0 ]; then
    FreeGigs=$((FreeSpace/Factor))
  else
    FreeGigs=0
    Return 1
  fi
  while true
  do
    # Show /root, /swap and available space
    translate "partition"
    message_first_line "/root $Result : ${RootType} : ${RootSize}"
    message_subsequent "You now have"
    Message="$Message ${FreeGigs}GiB"
    Message="$Message available on the chosen device"
    message_subsequent "There is space for a"
    translate "partition"
    Message="$Message /home $Result"
    message_subsequent "You can use all the remaining space on the device, if you wish"
    translate "partition"
    message_subsequent "You may want to leave room for a"
    Message="$Message /swap $Result \n"
    message_subsequent "Please enter the desired size"
    translate "Size"
    message_subsequent "${Result} [ eg: 10G or 0 or 100% ] ... "
    dialog --backtitle "$Backtitle" --title " Home " --ok-label "$Ok" --inputbox "$Message" 16 70 2>output.file
    retval=$?
    Result="$(cat output.file)"
    if [ $retval -eq 1 ] || [ -z "$Result" ] || [ "$Result" = "0" ]; then
      HomeSize="0"
      return 0
    else
      RESPONSE="${Result^^}"
    fi
    case ${RESPONSE} in
      "" | 0) HomeSize="0"
          break ;;
      *) # Check that entry includes 'G or M'
          CheckInput=${RESPONSE: -1}
        if [ "$CheckInput" != "%" ] && [ "$CheckInput" != "G" ] && [ "$CheckInput" != "M" ]; then
          translate "You must include M or G or %"
          dialog --backtitle "$Backtitle" --ok-label "$Ok" --msgbox "\nResult\n" 8 75
          HomeSize=""
          continue
        else
          if [ "$CheckInput" = "%" ]; then
            HomeSize="${RESPONSE}"
          else
            HomeSize="${RESPONSE}iB"
          fi
          create_filesystem
          HomeType=${PartitionType}
          break
        fi
    esac
  done
}

function swap_message
{
  message_subsequent "can be anything from 512MiB upwards but"
  Message="/swap $Message"
  message_subsequent "it is not necessary to exceed"
  Message="$Message 4GiB"
  message_subsequent "You can use all the remaining space on the device, if you wish"
}

function guided_swap # MBR & EFI Set variable: SwapSize
{
  # Show /boot and /root
  if [ $Factor -gt 0 ]; then
    FreeGigs=$((FreeSpace/Factor))
  else
    FreeGigs=0
    Return 1
  fi
  while true
  do
    if [ ${FreeSpace} -gt 0 ]; then
      # show /root and available space
      translate "partition"
      Message="/root $Result : ${RootType} : ${RootSize}"
      translate "partition"
      Message="$Message \n/home $Result : ${HomeType} : ${HomeSize}"
      message_subsequent "You now have"
      Message="$Message ${FreeGigs}GiB"
      Message="$Message available on the chosen device"
  
      if [ ${FreeSpace} -gt 10 ]; then
        message_subsequent "There is space for a"
        translate "partition"
        Message="$Message /swap $Result"
        swap_message
      elif [ ${FreeSpace} -gt 5 ]; then
        message_subsequent "There is space for a"
        translate "partition"
        Message="$Message /swap $Result"
        swap_message
      else
        message_subsequent "There is just space for a"
        translate "partition"
        Message="$Message /swap $Result"
        swap_message
      fi
      Message="$Message \n"
      message_subsequent "Please enter the desired size"
      translate "Size"
      message_subsequent "$Result [ eg: 2G or 0 or 100% ] ... "
      dialog --backtitle "$Backtitle" --title " Swap " --ok-label "$Ok" --inputbox "$Message" 18 70 2>output.file
      retval=$?
      Result="$(cat output.file)"
      if [ $retval -eq 1 ] || [ -z "$Result" ] || [ "$Result" = "0" ]; then
        RESPONSE=0
      else
        RESPONSE="${Result^^}"
      fi
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
          translate "You must include M or G or %"
          dialog --backtitle "$Backtitle" --ok-label "$Ok" --msgbox "\n$Result\n" 6 50
          SwapSize=""
          continue
        else
          if [ "$CheckInput" = "%" ]; then
            SwapSize="${RESPONSE}"
          else
            SwapSize="${RESPONSE}iB"
          fi
          Chars=${#RESPONSE}                # Count characters in variable
          swap_value=${RESPONSE:0:Chars-1}  # Separate the value from the unit
          StartPoint=$(((DiskSize*Factor)-(FreeGigs*1024)))
          if [ "$CheckInput" = "%" ]; then
            EndPoint="${SwapSize}"
          else
            end_value=$((StartPoint+swap_value))
            EndPoint="${end_value}MiB"
          fi
          parted_script "mkpart primary linux-swap ${StartPoint}MiB ${EndPoint}" # eg: parted /dev/sda mkpart primary linux-swap 31GiB 100%
          SwapPartition="${GrubDevice}${MountDevice}"
          mkswap "$SwapPartition"
          MakeSwap="Y"
          break
        fi
      esac
    else
      message_first_line "There is no space for a"
      translate "partition"
      Message="$Message /swap $Result"
      message_subsequent "but you can assign a swap file"
      Message="$Message \n"
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
  fdisk -l "${RootDevice}" > output.file
  p=" "
  while read -r Item; do             # Read items from the output.file file
    p="$p \n $Item"                  # Add to $p with newline after each $Item
  done < output.file

  dialog --backtitle "$Backtitle" --ok-label "$Ok" --msgbox "\n Partitioning of ${GrubDevice} \n $p" 20 77
}
