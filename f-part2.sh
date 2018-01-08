#!/bin/bash

# The Feliz installation scripts for Arch Linux
# Developed by Elizabeth Mills  liz@feliz.one
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
# The Free Software Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.

# Variables for UEFI Architecture
UEFI=0            # 1 = UEFI; 0 = BIOS
EFIPartition=""   # eg: /dev/sda1
UEFI_MOUNT=""    	# UEFI mountpoint
DualBoot="N"      # For formatting EFI partition

# In this module - functions for guided creation of a GPT or EFI partition table:
# -----------------------    ------------------------    -----------------------
# General Functions  Line    EFI Functions       Line    BIOS Functions     Line
# -----------------------    ------------------------    -----------------------
# allocate_uefi       40     guided_EFI           192    guided_MBR         235
# enter_size          61     guided_EFI_Boot      273    
# select_device       68     guided_EFI_Root      301    guided_MBR_root    341
# get_device_size    130     guided_EFI_Swap      390    guided_MBR_swap    451
# recalculate_space  176     guided_EFI_Home      515    guided_MBR_home    561
# -----------------------    ------------------------    -----------------------

function allocate_uefi {  # Called at start of allocate_root, as first step of EFI partitioning
                          # before allocating root partition. Uses list of available partitions in
                          # PartitionList created in f-part1.sh/BuildPartitionLists
	Remaining=""
	local Counter=0
  Partition=""
	PartitionType=""

	translate "Here are the partitions that are available"
  title="$Result"
	message_first_line "First you should select one to use for EFI /boot"
	message_subsequent "This must be of type vfat, and may be about 512MiB"
  display_partitions
  if [ $retval -ne 0 ]; then return; fi
  PassPart="/dev/${Result}" # eg: sda1
  SetLabel "/dev/${Result}"
	EFIPartition="/dev/${Result}"
  PartitionList=$(echo "$PartitionList" | sed "s/$Result //")  # Remove selected item
  return 0
}

function enter_size { # Called by guided_EFI_Root, guided_EFI_Swap, guided_EFI_Home
                      # guided_MBR_root, guided_MBR_swap, guided_MBR_home
  message_subsequent "Please enter the desired size"
  message_subsequent "or, to allocate all the remaining space, enter"
  Message="$Message 100%"
  return 0
}

function select_device {  # Called by feliz.sh
                          # User chooses device to use for auto partition
                          # from all connected devices
  DiskDetails=$(lsblk -l | grep 'disk' | cut -d' ' -f1)     # eg: sda sdb
  UseDisk=$DiskDetails                                      # If more than one, $UseDisk will be first
  local Counter=$(echo "$DiskDetails" | wc -w)
  if [ $Counter -gt 1 ]; then   # If there are multiple devices ask user which to use
    UseDisk=""            # Reset for user choice
    while [ "$UseDisk" = "" ]; do
      message_first_line "There are"
      Message="$Message $Counter"
      translate "devices available"
      Message="$Message $Result"
      message_subsequent "Which do you wish to use for this installation?"

      Counter=0
      for i in $DiskDetails; do
        Counter=$((Counter+1))
        message_first_line "" "$Counter) $i"
      done

      title="Selecting a device"
      echo $DiskDetails > list.file

      # Prepare list for display as a radiolist
      local -a ItemList=                                # Array will hold entire checklist
      local Items=0
      local Counter=0
      while read -r Item; do                              # Read items from the file
        Counter=$((Counter+1)) 
        Items=$((Items+1))
        ItemList[${Items}]="${Item}"                      # and copy each one to the variable
        Items=$((Items+1))
        ItemList[${Items}]="${Item}" 
        Items=$((Items+1))
        ItemList[${Items}]="off"                          # with added off switch and newline
      done < list.file
      Items=$Counter

      dialog --backtitle "$Backtitle" --title " $title " --ok-label "$Ok" \
        --cancel-label "$Cancel"--no-tags --radiolist "${Message}" \
          $1 $2 ${Items} ${ItemList[@]} 2>output.file
      retval=$?
      Result=$(cat output.file)                           # Return values to calling function
      rm list.file
      
      if [ $retval -ne 0 ]; then
        dialog --title "$title" --yes-label "$Yes" --no-label "$No" --yesno \
        "\nPartitioning cannot continue without a device.\nAre you sure you don't want to select a device?" 10 40
        if [ $retval -eq 0 ]; then return 1; fi
      fi
      UseDisk="${Result}"
    done
  fi
  GrubDevice="/dev/${UseDisk}"  # Full path of selected device
  return 0
}

function get_device_size {  # Called by feliz.sh
                            # Establish size of device in MiB and inform user
  DiskSize=$(lsblk -l | grep "${UseDisk}\ " | awk '{print $4}') # 1) Get disk size eg: 465.8G
  Unit=${DiskSize: -1}                                          # 2) Save last character (eg: G)
                                  # Remove last character for calculations
  Chars=${#DiskSize}              # Count characters in variable
  Available=${DiskSize:0:Chars-1} # Separate the value from the unit
                                  # Must be integer, so remove any decimal
  Available=${Available%.*}       # point and any character following
  if [ $Unit = "G" ]; then
    FreeSpace=$((Available*1024))
    Unit="M"
  elif [ $Unit = "T" ]; then
    FreeSpace=$((Available*1024*1024))
    Unit="M"
  else
    FreeSpace=$Available
  fi

  if [ ${FreeSpace} -lt 2048 ]; then    # Warn user if space is less than 2GiB
    message_first_line "Your device has only"
    Message="$Message ${FreeSpace}MiB:"
    message_first_line "This is not enough for an installation"
    translate "Exit"
    dialog --backtitle "$Backtitle" --ok-label "$Ok" --infobox "$Message" 10 60
    return 1
  elif [ ${FreeSpace} -lt 4096 ]; then                            # If less than 4GiB
    message_first_line "Your device has only"
    Message="$Message ${FreeSpace}MiB:"
    message_subsequent "This is just enough for a basic"
    message_subsequent "installation, but you should choose light applications only"
    message_subsequent "and you may run out of space during installation or at some later time"
    dialog --backtitle "$Backtitle" --ok-label "$Ok" --infobox "$Message" 10 60
  elif [ ${FreeSpace} -lt 8192 ]; then                            # If less than 8GiB
    message_first_line "Your device has"
    Messgae="$Message ${FreeSpace}MiB:"
    message_subsequent "This is enough for"
    message_subsequent "installation, but you should choose light applications only"
    dialog --backtitle "$Backtitle" --ok-label "$Ok" --infobox "$Message" 10 60
  fi
  return 0
}

function recalculate_space {  # Called by guided_MBR & guided_EFI
                              # Calculate remaining disk space
  local Passed=$1
  case ${Passed: -1} in
  "%") Calculator=$FreeSpace ;;       # Allow for 100%
  "G") Chars=${#Passed}               # Count characters in variable
        Passed=${Passed:0:Chars-1}      # Passed variable stripped of unit
        Calculator=$((Passed*1024)) ;;
    *) Chars=${#Passed}                 # Count characters in variable
       Calculator=${Passed:0:Chars-1}   # Passed variable stripped of unit
  esac
  FreeSpace=$((FreeSpace-Calculator))   # Recalculate available space
  return 0
}

function guided_EFI {  # Called by f-part1.sh/partitioning_options as the first step
                       # in EFI guided partitioning option - Inform user of purpose, call each step
  select_device                   # Get details of device to use
  get_device_size                 # Get available space in MiB

  message_first_line "Here you can set the size and format of the partitions"
  message_subsequent "you wish to create. When ready, Feliz will wipe the disk"
  message_subsequent "and create a new partition table with your settings"
  Message="${Message}\n"
  message_subsequent "Are you sure you wish to continue?"
  dialog --backtitle "$Backtitle" --yes-label "$Yes" --no-label "$No" --yesno "$Message" 15 70
  if [ $? -ne 0 ]; then return 1; fi   # Inform calling function
  
  message_first_line "We begin with the"
  translate "partition"
  Message="$Message /boot $Result"

  guided_EFI_Boot                  # Create /boot partition
  recalculate_space "$BootSize"    # Recalculate remaining space
  
  guided_EFI_Root                  # Create /root partition
  recalculate_space "$RootSize"    # Recalculate remaining space
  if [ ${FreeSpace} -gt 0 ]; then
    guided_EFI_Swap
    if [ $SwapSize ] && [ $SwapSize != "" ]; then recalculate_space "$SwapSize"; fi  # Recalculate available space
  else
    message_first_line "There is no space for a /swap partition, but you can"
    message_subsequent "assign a swap-file. It is advised to allow some swap"
    message_subsequent "Do you wish to allocate a swapfile?"

    dialog --backtitle "$Backtitle" --title " $title " --yes-label "$Yes" \
      --no-label "$No" --yesno "\n$Message" 10 55 2>output.file
    if [ $? -ne 0 ]; then return 1; fi
    set_swap_file           # Note: Global variable SwapFile is set by set_swap_file
  fi                     # (SwapFile will be created during installation by mount_partitions)

  if [ ${FreeSpace} -gt 2 ]; then guided_EFI_Home; fi
  AutoPart="GUIDED"
  return 0
}

function guided_MBR { # Called by f-part1.sh/partitioning_options as the first step in the 
                      # guided BIOS partitioning option - Inform user of purpose, call each step
  message_first_line "Here you can set the size and format of the partitions"
  message_subsequent "you wish to create. When ready, Feliz will wipe the disk"
  message_subsequent "and create a new partition table with your settings"
  message_subsequent "This facility is restricted to creating"
  Message="${Message} /root, /swap & /home\n"
  message_subsequent "Are you sure you wish to continue?"

  dialog --backtitle "Feliz" --yes-label "$Yes" --no-label "$No" --yesno "$Message" 15 70
  if [ $? -ne 0 ]; then return 1; fi                  # User cancelled guided partitioning

  guided_MBR_root                                     # Create /root partition
  if [ $? -ne 0 ]; then return 1; fi                  # User cancelled guided root

  recalculate_space "$RootSize"                       # Recalculate remaining space
  if [ ${FreeSpace} -gt 0 ]; then
    guided_MBR_swap
    if [ $SwapSize ] && [ $SwapSize != "" ]; then
      recalculate_space "$SwapSize"                   # Recalculate remaining space
    fi
  else
    message_first_line "There is no space for a /swap partition, but you can"
    message_subsequent "assign a swap-file. It is advised to allow some swap"
    Message="${Message}\n"
    message_subsequent "Do you wish to allocate a swapfile?"
    dialog --backtitle "$Backtitle" --yes-label "$Yes" --no-label "$No" --yesno "$Message" 15 70
    if [ $? -eq 0 ]; then
      set_swap_file                                   # Note: Global variable SwapFile is set by set_swap_file
    fi                                                # and SwapFile is created during installation by mount_partitions
  fi

  if [ ${FreeSpace} -gt 0 ]; then guided_MBR_home; fi

  AutoPart="GUIDED"
  return 0
}

function guided_EFI_Boot {  # Called by guided_EFI
                            # EFI - User sets variable: BootSize
  BootSize=""
  while [ ${BootSize} = "" ]; do
    title="/boot"
    FreeGigs=$((FreeSpace/1024))
    message_first_line "You have"
    Message="$Message ${FreeGigs}GiB"
    translate "available on the chosen device"
    Message="$Message ${Result}\n"
    message_subsequent "All we need to set here is the size of your /boot partition"
    message_subsequent "It should be no less than 512MiB and need be no larger than 1GiB"

    dialog_inputbox 12 70
    RESPONSE="${Result^^}"
    # Check that entry includes 'M or G'
    CheckInput=${RESPONSE: -1}
    echo
    if [ ${CheckInput} != "M" ] && [ ${CheckInput} != "G" ] && [ ${CheckInput} != "M" ]; then
      message_first_line "You must include M, G or %"
      dialog --backtitle "$Backtitle" --ok-label "$Ok" --infobox "$Message" 10 60
      BootSize=""
    else
      BootSize="${RESPONSE}"
    fi
  done
  return 0
}

function guided_EFI_Root {  # Celled by guided_EFI - User sets variables: RootSize, RootType
  
  RootSize=""
  FreeGigs=$((FreeSpace/1024))
  while [ ${RootSize} = "" ]; do
    title="/root"
    # Show /boot and available space
    translate "partition"
    Message="/boot $Result: ${BootSize}\n"
    message_subsequent "You now have"
    Message="$Message ${FreeGigs}GiB"
    translate "available on the chosen device"
    Message="$Message ${Result}\n"
    message_subsequent "A partition is needed for /root"
    message_subsequent "You can use all the remaining space on the device, if you wish"
    message_subsequent "although you may want to leave room for a /swap partition"
    message_subsequent "and perhaps also a /home partition"
    message_subsequent "The /root partition should not be less than 8GiB"
    message_subsequent "ideally more, up to 20GiB"
    
    enter_size               # Adds advice about 100%
    
    dialog_inputbox 30 70
    RESPONSE="${Result^^}"
    # Check that entry includes 'G or %'
    CheckInput=${RESPONSE: -1}
    echo
    if [ ${CheckInput} != "%" ] && [ ${CheckInput} != "G" ] && [ ${CheckInput} != "M" ]; then
      message_first_line "You must include M, G or %"
      RootSize=""
    else
      RootSize=$RESPONSE
      Partition="/root"
      select_filesystem
      RootType=${PartitionType}
    fi
  done
  return 0
}

function guided_MBR_root { # Called by guided_MBR - Set variables: RootSize, RootType
  
  RootSize=""
  FreeGigs=$((FreeSpace/1024))
  while [ "$RootSize" = "" ]; do
    # Show /boot and available space
    title="/root"
    message_first_line "We begin with the"
    translate "partition"
    Message="$Message /root $Result \n"
    message_subsequent "You have"
    Message="$Message ${FreeGigs}G"
    translate "available on the chosen device"
    Message="$Message ${Result}\n"
    message_subsequent "You can use all the remaining space on the device, if you wish"
    message_subsequent "although you may want to leave room for a /swap partition"
    message_subsequent "and perhaps also a /home partition"
    message_subsequent "The /root partition should not be less than 8G"
    message_subsequent "ideally more, up to 20G"
    enter_size        # Adds advice to message about 100%
    
    dialog_inputbox 30 75

    RESPONSE="${Result^^}"
    # Check that entry includes 'G or %'
    CheckInput1=${RESPONSE: -1}
    if [ -z ${CheckInput1} ]; then
      RootSize=""
    elif [ ${CheckInput1} != "%" ] && [ ${CheckInput1} != "G" ] && [ ${CheckInput1} != "M" ]; then
      message_first_line "You must include M, G or %"
      dialog --backtitle "$Backtitle" --ok-label "$Ok" --msgbox "$Message"
      RootSize=""
    else
      RootSize=$RESPONSE
      Partition="/root"
      print_heading
      translate "allocated to /root"
      Message="${RootSize}" "$Result"
      select_filesystem 30 60
      RootType=${PartitionType}
    fi
  done
  return 0
}

function guided_EFI_Swap {  # Called by guided_EFI
                            # User sets variable: SwapSize
  RootSize=""
  FreeGigs=$((FreeSpace/1024))
  while [ ${RootSize} = "" ]; do
    title="/swap"
    # Show /boot and available space
    translate "partition"
    Message="/boot $Result: ${BootSize}"
    Message="${Message}\n/root $Result: ${RootType} : ${RootSize}\n"
    message_first_line "You now have"
    Message="$Message ${FreeGigs}GiB"
    translate "available on the chosen device"
    Message="$Message ${Result}\n"
    if [ ${FreeSpace} -gt 10 ]; then
      message_first_line "There is space for a"
      translate "partition"
      Message="$Message /swap $Result"
      message_subsequent "Swap can be anything from 512MiB upwards but"
      message_subsequent "it is not necessary to exceed 4GiB"
      message_subsequent "You may want to leave room for a /home partition"
    elif [ ${FreeSpace} -gt 5 ]; then
      message_first_line "There is space for a"
      translate "partition"
      Message="$Message /swap $Result"
      message_subsequent "Swap can be anything from 512MiB upwards but"
      message_subsequent "it is not necessary to exceed 4GiB"
      message_subsequent "You may want to leave room for a /home partition"
    else
      message_first_line "There is just space for a"
      translate "partition"
      Message="$Message /swap $Result"
      message_subsequent "Swap can be anything from 512MiB upwards but"
      message_subsequent "it is not necessary to exceed 4GiB"
    fi
    enter_size        # Adds advice about 100%

    dialog_inputbox 30 70
    RESPONSE="${Result^^}"
    case ${RESPONSE} in
    '' | 0) message_first_line "Do you wish to allocate a swapfile?"
      dialog  --backtitle "$Backtitle" --yes-label "$Yes" --no-label "$No" --yesno "$Message"
      if [ $retval -eq 0 ]; then
        set_swap_file
      fi
      return 0 ;;
    *) # Check that entry includes 'G or %'
      CheckInput=${RESPONSE: -1}
      if [ ${CheckInput} != "%" ] && [ ${CheckInput} != "G" ] && [ ${CheckInput} != "M" ]; then
        message_first_line "You must include M, G or %"
        RootSize=""
      else
        SwapSize=$RESPONSE
      fi
    esac
  done
  return 0
}

function guided_MBR_swap { # Called by guided_MBR - Set variable: SwapSize

  FreeGigs=$((FreeSpace/1024))
  SwapSize=""
  translate "partition"
  while [ "$SwapSize" = "" ]; do
    # Show /root and available space
    title="/swap"
    Message="/root $Result: ${RootType} : ${RootSize}\n"
    message_subsequent "You now have"
    Message="$Message ${FreeGigs}GiB"
    translate "available on the chosen device"
    Message="$Message ${Result}\n"
    if [ ${FreeSpace} -gt 10 ]; then
      message_subsequent "There is space for a"
      translate "partition"
      Message="$Message /swap ${Result}\n"
      message_subsequent "Swap can be anything from 512MiB upwards but"
      message_subsequent "it is not necessary to exceed 4GiB"
      message_subsequent "You may want to leave room for a /home partition"
    elif [ ${FreeSpace} -gt 5 ]; then
      message_subsequent "There is space for a"
      translate "partition"
      Message="$Message /swap ${Result}\n"
      message_subsequent "Swap can be anything from 512MiB upwards but"
      message_subsequent "it is not necessary to exceed 4GiB"
      message_subsequent "You can use all the remaining space on the device, if you wish"
      message_subsequent "You may want to leave room for a /home partition"
    else
      message_subsequent "There is just space for a"
      translate "partition"
      Message="$Message /swap ${Result}\n"
      message_subsequent "Swap can be anything from 512MiB upwards but"
      message_subsequent "it is not necessary to exceed 4GiB"
      message_subsequent "You can use all the remaining space on the device, if you wish"
    fi
    enter_size        # Adds advice about 100%
    
    dialog_inputbox 30 75
    RESPONSE="${Result^^}"

    case ${RESPONSE} in
    ''|0) message_first_line "Do you wish to allocate a swapfile?"
      dialog --backtitle "$Backtitle" --yes-label "$Yes" --no-label "$No" --yesno "$Message" 10 50
      if [ $? -eq 0 ]; then
        set_swap_file
      fi
      return 0 ;;
    *) # Check that entry includes 'G or %'
      CheckInput=${RESPONSE: -1}
      if [ ${CheckInput} != "%" ] && [ ${CheckInput} != "G" ] && [ ${CheckInput} != "M" ]; then
        message_first_line "You must include M, G or %"
        dialog --backtitle "$Backtitle" --ok-label "$Ok" --msgbox "$Message"
        SwapSize=""
      else
        SwapSize=$RESPONSE
      fi
    esac
  done
  return 0
}

function guided_EFI_Home { # Called by guided_EFI - Set variables: HomeSize, HomeType
  
  HomeSize=""
  FreeGigs=$((FreeSpace/1024))
  while [ ${HomeSize} = "" ]; do
    title="/home"
    # Show /boot and available space
    Message="/boot $Result: ${BootSize}"
    Message="${Message}\n/root $Result: ${RootType} : ${RootSize}"
    Message="${Message}\n/swap $Result: ${SwapSize}\n"
    message_subsequent "You now have"
    Message="$Message ${FreeGigs}GiB"
    translate "available on the chosen device"
    Message="$Message ${Result}\n"
    message_subsequent "There is space for a"
    translate "partition"
    Message="$Message /home $Result"
    message_subsequent "You can use all the remaining space on the device, if you wish"
    enter_size        # Adds advice about 100%

    dialog_inputbox 30 75
    RESPONSE="${Result^^}"
    case ${RESPONSE} in
    "" | 0) HomeSize="" ;;
    *) # Check that entry includes 'G or %'
        CheckInput=${RESPONSE: -1}
        if [ ${CheckInput} != "%" ] && [ ${CheckInput} != "G" ] && [ ${CheckInput} != "M" ]; then
          message_first_line "You must include M, G or %"
          HomeSize=""
        else
          HomeSize=$RESPONSE
          Partition="/home"
          print_heading
          select_filesystem
          HomeType=${PartitionType}
        fi
    esac
  done
  return 0
}

function guided_MBR_home { # Called by guided_MBR - Set variables: HomeSize, HomeType
  
  FreeGigs=$((FreeSpace/1024))
  HomeSize=""
  while [ -z "$HomeSize" ]; do
    # Show /root, /swap and available space
    title="/home"
    Message="/root $Result: ${RootType}: ${RootSize}"
    message_subsequent "/swap ${Result}: ${SwapSize}\n"
    translate "You now have"
    Message="${Message} ${FreeGigs}GiB"
    translate "available on the chosen device"
    Message="$Message ${Result}\n"
    message_subsequent "There is space for a"
    translate "partition"
    Message="${Message} /home $Result"
    message_subsequent "You can use all the remaining space on the device, if you wish"
    enter_size        # Adds advice about 100%

    dialog_inputbox 16 70
    RESPONSE="${Result^^}"
    case ${RESPONSE} in
    "") return 0 ;;
    *) # Check that entry includes 'G or %'
        CheckInput=${RESPONSE: -1}
      if [ ${CheckInput} != "%" ] && [ ${CheckInput} != "G" ] && [ ${CheckInput} != "M" ]; then
        message_first_line "You must include M, G or %"
        dialog --backtitle "$Backtitle" --ok-label "$Ok" --msgbox "$Message"
        HomeSize=""
      else
        HomeSize=$RESPONSE
        Partition="/home"
        translate "of remaining space allocated to"
        Message="${HomeSize} $Result"
        translate "partition"
        Message="${Message} /home $Result"
        select_filesystem 12 60
        HomeType=${PartitionType}
      fi
    esac
  done
  return 0
}
