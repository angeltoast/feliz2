#!/bin/bash

# The Feliz installation scripts for Arch Linux
# Developed by Elizabeth Mills
# With grateful acknowlegements to Helmuthdu, Carl Duff and Dylan Schacht
# Revision date: 3rd June 2018

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
#                  and partitions, and functions for auto-partitioning
# ------------------------    ----------------------
# Functions           Line    Functions         Line 
# ------------------------    ----------------------
# auto_warning          36    guided_recalc      249
# autopart              46    guided_root        275
# prepare_device        72    guided_home        339
# prepare_partitions   132    swap_message       398
# guided_partitions    196    guided_swap        407
# ------------------------    ----------------------

function auto_warning # Called by f-part/check_parts before autopart
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
  AutoPart="AUTO"                                   # Set auto-partition flag
  prepare_device                                    # Create partition table and device variables
  RootType="ext4"                                   # Default for auto
  HomeType="ext4"                                   # Default for auto
  # Use partition variables ($DiskSize & $Start are initialized in MiB by prepare_device)
  if [ $DiskSize -ge 50 ]; then                     # ------ /root /home /swap partitions ------
    HomeSize=$((DiskSize-19))                       # /root 15 GiB, /home from 31GiB, /swap 4GiB
    prepare_partitions "${Start}" "$((15*1024))" "$((HomeSize*1024))" "$((4*1024))"
  elif [ $DiskSize -ge 30 ]; then                   # ------ /root /home /swap partitions ------
    HomeSize=$((DiskSize-16))                       # /root 15 GiB, /home 12 to 22GiB, /swap 3GiB
    prepare_partitions "${Start}" "$((13*1024))" "$((HomeSize*1024))" "$((3*1024))"
  elif [ $DiskSize -ge 18 ]; then                   # ------ /root & /swap partitions only ------
    RootSize=$((DiskSize-2))                        # /root 16 to 28GiB, /swap 2GiB
    prepare_partitions "${Start}" "$((RootSize*1024))" "0" "$((2*1024))"
  elif [ $DiskSize -gt 10 ]; then                   # ------ /root & /swap partitions only ------
    RootSize=$((DiskSize-1))                        # /root 9 to 17GiB, /swap 1GiB
    prepare_partitions "${Start}" "$((RootSize*1024))" "0" "1024"
  else                                              # ------/root partition &  Swap file only -----
    prepare_partitions "${Start}" "$((DiskSize-Start))" "0" "0"
    SwapFile="2G"                                   # Swap file
    SwapPartition=""                                # Clear swap partition variable
  fi
}

function prepare_device # Called by autopart, guided_MBR and guided_EFI
{                       # Create partition table
  GrubDevice="/dev/${UseDisk}"
  Home="N"                                          # No /home partition at this point
  DiskSize=$(lsblk -l "$RootDevice" | grep "${UseDisk} " | awk '{print $4}' | sed "s/G\|M\|K//g" | cut -d'.' -f1) # eg: 149
  get_unit=$(lsblk -l "$RootDevice" | grep "${UseDisk} " | awk '{print $4}') # eg: 149.1G
  disk_unit=${get_unit: -1}                         # eg: G
  case "$disk_unit" in                              
  "G") DiskSize="$((DiskSize*1024))" ;;             # Convert all sizes to MiB 
  "M") DiskSize="$DiskSize" ;;
  *) Error "${BASH_SOURCE[0]} ${FUNCNAME[0]} line $LINENO"
    return 1
  esac
  FreeSpace="$DiskSize"
  # Create a new partition table
  if [ ${UEFI} -eq 1 ]; then                        # Installing in UEFI environment
    while true
    do
      if [ "$AutoPart" == "AUTO" ]; then
        RESPONSE="550M"
        break
      else
        message_first_line "A partition is needed for"
        Message="$Message EFI boot"
        message_subsequent "can be anything from 512MiB upwards but"
        Message="EFI boot $Message"
        message_subsequent "it is not necessary to exceed"
        Message="$Message 1024MiB"
        message_subsequent "Please enter the desired size in megabytes"
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
        if [ "$CheckInput" = "M" ]; then
          break
        fi
      fi
    done
    parted_script "mklabel gpt"                         # Create new filesystem
    parted_script "mkpart ESP fat32 1MiB ${RESPONSE}" # EFI boot partition
    EFIPartition="${GrubDevice}1"                       # Define EFI partition 
    Chars=${#RESPONSE}                                  # Count characters in variable
    efi_size=${RESPONSE:0:Chars-1}                      # $RESPONSE stripped of unit
    FreeSpace="$((FreeSpace-efi_size))"                 # For guided partitioning
    mkfs.vfat -F32 ${EFIPartition} 2>> feliz.log        # Format EFI boot partition
    Start=$((efi_size+1))                               # For next partition
  else                                                  # Installing in BIOS environment
    parted_script "mklabel msdos"                       # Create new filesystem
    Start=1                                             # For next partition
  fi
  # Prepare to count devices
  if [ $UEFI -eq 1 ]; then                              # eg: 1 in sda1
    MountDevice=2                                       # Next after EFI
  else
    MountDevice=1                                       # Or 1 if not on EFI
  fi
}

function prepare_partitions # Called from autopart and guided_partitions
{                           # Creates partitions via parted_script (in f-part.sh)
      # All sizes passed to this function MUST be in MiB, numeric only
      # ie: 0 or 15000 (NOT ... 15G or 15Gib or 15000M or 15000MiB or 100%)
  
      # Receives up to 4 arguments (all in MiB)
      #   $1 is the starting point of the root partition  - 1 if MBR, up to 1025 if GPT
      #   $2 is size of root partition                    - 8000 upwards
      #   $3 is size of home partition or null            - may be nnnn or 0
      #   $4 if passed is size of swap partition          - may be nnnn or 0
      # Note:
      # An appropriate partition table has already been created in prepare_device
      # If system is EFI, prepare_device has also created the /boot partition at
      #  /dev/${UseDisk}1 and Start (passed here as $1) has been set to follow /boot

  # 1) Make /root partition
  local Start="$1"                                    # Probably the same as global Start
  local Size="$2"                                     # root size
  local End=$((Start+Size))

  parted_script "mkpart primary $RootType ${Start}M ${End}M"
  # eg: parted --script /dev/sda mkpart primary ext4 1M 12000M
  RootPartition="${GrubDevice}${MountDevice}"         # eg: /dev/sda2 if there is an EFI partition
  mkfs."$RootType" "$RootPartition" # &>> feliz.log     # eg: mkfs.ext4 /dev/sda1
  # Set first partition as bootable
  parted_script "set $MountDevice boot on"            # eg: parted /dev/sda set 1 boot on
  Start="$End"                                        # For /home or /swap
  MountDevice=$((MountDevice+1))                      # Advance partition numbering for next step
  # 2) Make /home partition
  if [ -n "$3" ] && [ "$3" != "0" ]; then
    Size="$3"                                         # home size
    End=$((Start+Size))
    parted_script "mkpart primary $HomeType ${Start}M ${End}M"
    # eg: parted --script /dev/sda mkpart primary ext4 12000M 19000M
    HomePartition="${GrubDevice}${MountDevice}"
    AddPartList[0]="${HomePartition}"                 # eg: /dev/sda2  | add to
    AddPartMount[0]="/home"                           # Mountpoint     | array of
    AddPartType[0]="$HomeType"                        # Filesystem     | additional partitions
    Home="Y"
    mkfs."$HomeType" "$HomePartition" # &>> feliz.log     # eg: mkfs.ext4 /dev/sda3
    Start="$End"                                      # Reset start for /swap
    MountDevice=$((MountDevice+1))                    # Advance partition number
  fi
  
  # 3) Make /swap partition
  if [ -n "$4" ] && [ "$4" != "0" ]; then
    Size="$4"
    End=$((Start+Size))
    parted_script "mkpart primary linux-swap ${Start}M ${End}M"
    # eg: parted --script /dev/sda mkpart primary ext4 19000M 21000M
    SwapPartition="${GrubDevice}${MountDevice}"
    MakeSwap="Y"
    mkswap "$SwapPartition"
  fi
  
  # Display partitions for user
  fdisk -l "${RootDevice}" > output.file
  p=" "
  while read -r Item; do             # Read items from the output.file file
    p="$p \n $Item"                  # Add to $p with newline after each $Item
  done < output.file
  dialog --backtitle "$Backtitle" --ok-label "$Ok" --msgbox "\n Partitioning of ${GrubDevice} \n $p" 20 77
}

function guided_partitions  # Called by f-part/check_parts
{                           # Calls each guided partitioning function
  # local MountDevice="$MountDevice"
  limitations="This facility will create"
  if [ $UEFI -eq 1 ]; then  # EFI system
    limitations="$limitations /boot /root /swap & /home"
  else                      # BIOS system
    limitations="$limitations /root /swap & /home"
  fi
  # Inform user about guided partitioning
  message_first_line "Here you can set the size and format of the partitions"
  message_subsequent "you wish to create. When ready, Feliz will wipe the disk"
  message_subsequent "and create a new partition table with your settings"
  message_subsequent "$limitations"
  message_subsequent "Do you wish to continue?"
  dialog --backtitle "$Backtitle" --title " $title " \
      --yes-label "$Yes" --no-label "$No" --yesno "\n$Message" 12 60
  retval=$?
  if [ $retval -ne 0 ]; then return 1; fi   # If 'No' then return to caller
  AutoPart="GUIDED"                         # Set auto-partition flag
  prepare_device                            # Create partition table and prepare device size variables
  if [ $? -ne 0 ]; then return 1; fi        # If error then return to caller
                                            # If an ESP is required, it was set during prepare_device
  guided_root                               # Prepare $RootSize variable (eg: 9GiB) & $RootType)
  if [ $? -ne 0 ]; then return 1; fi        # If error then return to caller

  guided_recalc "$RootSize"                 # Recalculate remaining space after adding /root
  if [ $? -ne 0 ]; then return 1; fi        # If error then return to caller
  RootSize="$Calculator"                    # RootSize is now in MiB (numeric only)
  # MountDevice=$((MountDevice+1))            # Advance partition number
  if [ ${FreeSpace} -gt 2 ]; then
    guided_home                             # Prepare $HomeSize & $HomeType
    if [ $? -ne 0 ]; then return 1; fi      # If error then return to caller
    guided_recalc "$HomeSize"               # Recalculate remaining space after adding /home
    if [ $? -ne 0 ]; then return 1; fi      # If error then return to caller
    HomeSize="$Calculator"                  # HomeSize is now in MiB (numeric only)
  fi
  # MountDevice=$((MountDevice+1))            # Advance partition number
  if [ ${FreeSpace} -gt 1 ]; then
    guided_swap                             # Prepare $SwapSize
    if [ $? -ne 0 ]; then return 1; fi      # If error then return to caller
    guided_recalc "$SwapSize"               # Use guided_recalc to convert SwapSize
    if [ $? -ne 0 ]; then return 1; fi      # If error then return to caller
    SwapSize="$Calculator"                  # SwapSize is now in MiB (numeric only)
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
  prepare_partitions "$Start" "$RootSize" "$HomeSize" "$SwapSize" # variables all in MiB
}

function guided_recalc  # Called by prepare_partitions & guided_partitions
                        # Convert to MiB and calculate remaining disk space
{                       # $1 is a partition size eg: 10G or 100% or perhaps 0
  if [ -z "$1" ] || [  "$1" == 0 ]; then Calculator=0; return; fi # Just in case
  local Passed
  Chars=${#1}                               # Count characters in variable
  Passed=${1:0:Chars-1}                     # Passed variable stripped of unit
  if [ ${1: -1} == "%" ]; then               # Allow for percentage
    Calculator=$((FreeSpace*Passed/100))    # Convert percentage to value in MiB
  elif [ ${1: -1} == "G" ]; then
    Calculator=$((Passed*1024))             # Convert to MiB
  elif [ ${1: -1} == "M" ]; then
    Calculator="$Passed"                    # Passed value
  else
    Calculator=0                            # Just in case
    Error "${BASH_SOURCE[0]} ${FUNCNAME[0]} line $LINENO"
    return 1
  fi
  # Recalculate available space
  FreeSpace=$((FreeSpace-Calculator))
}

function guided_root # MBR & EFI Set variables: RootSize, RootType
{
  FreeGigs=$((FreeSpace/1024))    # Display FreeSpace in GiB
  
  while true
  do
  # 1) Show /boot and available space
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
  # 2) User enters size of /root
    dialog --backtitle "$Backtitle" --title " Root " --ok-label "$Ok" --inputbox "$Message" 18 70 2>output.file
    retval=$?
    if [ $retval -ne 0 ]; then continue 1; fi
    Result="$(cat output.file)"
    if [ $retval -eq 1 ] || [ -z "$Result" ] || [ "$Result" = "0" ]; then
        continue        # Cannot be zero or blank
      else
        RESPONSE="${Result^^}"
      fi
  # 3) Check that entry includes 'G or M or %'
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
        RootSize="${RESPONSE}"
      fi
      Partition="${GrubDevice}${MountDevice}"   # eg: /dev/sda2 if there is an EFI partition
      RootPartition="${Partition}"
      create_filesystem 1                       # Get partition type
      RootType="$PartitionType"
      break
    fi
  done
}

function guided_home # MBR & EFI Set variables: HomeSize, HomeType
{
  FreeGigs=$((FreeSpace/1024))    # Display Freespace in GiB
 
  while true
  do
  # 1) Show /root, /swap and available space
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
  # 2) User enters size of /home
    dialog --backtitle "$Backtitle" --title " Home " --ok-label "$Ok" --inputbox "$Message" 16 70 2>output.file
    retval=$?
    Result="$(cat output.file)"
    if [ $retval -eq 1 ] || [ -z "$Result" ] || [ "$Result" = "0" ]; then
      HomeSize="0"
      return 0
    else
      RESPONSE="${Result^^}"
    fi
    HomeType=""
    case ${RESPONSE} in
      "" | 0) HomeSize="0"
          return 0 ;;
      *) # 3) Check that entry includes 'G or M or %'
          CheckInput=${RESPONSE: -1}
        if [ "$CheckInput" != "%" ] && [ "$CheckInput" != "G" ] && [ "$CheckInput" != "M" ]; then
          translate "You must include M or G or %"
          dialog --backtitle "$Backtitle" --ok-label "$Ok" --msgbox "\nResult\n" 8 75
          HomeSize=""
          continue
        else
          HomeSize="${RESPONSE}"
          Partition="${GrubDevice}${MountDevice}"   # eg: /dev/sda3 if there is an EFI partition
          HomePartition="${Partition}"
          create_filesystem                         # Get filesystem variable
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
  while true
  do
    if [ ${FreeSpace} -gt 0 ]; then           # show /root /home and available space
      FreeGigs=$((FreeSpace/1024))            # To display Freespace in GiB
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
          break ;;
      *) # Check that entry includes 'G or M or %'
        CheckInput=${RESPONSE: -1}
        if [ "$CheckInput" != "%" ] && [ "$CheckInput" != "G" ] && [ "$CheckInput" != "M" ]; then
          translate "You must include M or G or %"
          dialog --backtitle "$Backtitle" --ok-label "$Ok" --msgbox "\n$Result\n" 6 50
          SwapSize=""
          continue
        else
          SwapSize="${RESPONSE}"
          Partition="${GrubDevice}${MountDevice}"   # eg: /dev/sda2 if there is an EFI partition
          SwapPartition="${Partition}"
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
