#!/bin/bash

# The Feliz installation scripts for Arch Linux
# Developed by Elizabeth Mills  liz@feliz.one
# With grateful acknowlegements to Helmuthdu, Carl Duff and Dylan Schacht
# Revision date: 20th December 2017

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

# In this module - settings for partitioning:
# ------------------------    ------------------------
# Functions           Line    Functions           Line
# ------------------------    ------------------------
# check_parts           41    edit_label          386
# build_lists          117    allocate_root       425
# partitioning_options 163    check_filesystem    483
# choose_device        203    allocate_swap       495   
# partition_maker      252    no_swap_partition   554
# autopart             294    set_swap_file       571
# allocate_partitions  337    more_partitions     592 
# select_filesystem    373    choose_mountpoint   628 
# display_partitions   683 
# ------------------------    ------------------------

function check_parts()   # Called by feliz.sh
{ # Test for existing partitions

  # partitioning_options menu options="leave cfdisk guided auto"
  translate "Choose from existing partitions"
  LongPart1="$Result"
  translate "Open cfdisk so I can partition manually"
  LongPart2="$Result"
  translate "Guided manual partitioning tool"
  LongPart3="$Result"
  translate "Allow feliz to partition the whole device"
  LongPart4="$Result"
  title="Partitioning"

  ShowPartitions=$(lsblk -l | grep 'part' | cut -d' ' -f1) # List of all partitions on all connected devices
  PARTITIONS=$(echo $ShowPartitions | wc -w)

  if [ $PARTITIONS -eq 0 ]; then          # If no partitions exist, offer options
    while [ $PARTITIONS -eq 0 ]
    do
      message_first_line "If you are uncertain about partitioning, you should read the Arch Wiki"
      message_subsequent "There are no partitions on the device, and at least"
      if [ ${UEFI} -eq 1 ]; then          # Installing in UEFI environment
        message_subsequent "two partitions are needed - one for EFI /boot, and"
        message_subsequent "one partition is needed for the root directory"
        message_subsequent "There is a guided manual partitioning option"
        message_subsequent "or you can exit now to use an external tool"
      else                                # Installing in BIOS environment
        message_subsequent "one partition is needed for the root directory"
      fi
      Message="${Message}\n"
      message_subsequent "If you choose to do nothing now, the script will"
      message_subsequent "terminate to allow you to partition in some other way"
 
      dialog --backtitle "$Backtitle" --title " $title " \
        --ok-label "$Ok" --cancel-label "$Cancel" --menu "$Message" 24 70 4 \
        1 "$LongPart2" \
        2 "$LongPart3" \
        3   "$LongPart4" 2>output.file
      retval=$?
      if [ $retval -ne 0 ]; then abandon "$title"; fi
      if [ $retval -ne 0 ]; then return 1; fi
      Result=$(cat output.file)
      Result=$((Result+1))                # Because this menu excludes option 1
      partitioning_options                        # partitioning_options options
      retval=$?
      if [ $retval -ne 0 ]; then 
        dialog --backtitle "$Backtitle" --ok-label "$Ok" \
          --infobox "Exiting to allow you to partition the device" 6 30
        exit
      fi
      # Check that partitions have been created
      ShowPartitions=$(lsblk -l | grep 'part' | cut -d' ' -f1)
      PARTITIONS=$(echo $ShowPartitions | wc -w)
    done
    build_lists                          # Generate list of partitions and matching array
  else                                   # There are existing partitions on the device
    build_lists                          # Generate list of partitions and matching array
    translate "Here is a list of available partitions"
    Message="\n               ${Result}:\n"
    
    for part in ${PartitionList}
    do
      Message="${Message}\n        $part ${PartitionArray[${part}]}"
    done

    dialog --backtitle "$Backtitle" --title " $title " \
      --ok-label "$Ok" --cancel-label "$Cancel" --menu "$Message" 24 78 4 \
      1 "$LongPart1" \
      2 "$LongPart2" \
      3 "$LongPart3" \
      4 "$LongPart4" 2>output.file
    retval=$?
    if [ $retval -ne 0 ]; then return 1; fi
    Result=$(cat output.file)

    partitioning_options                # Action user selection
    retval=$?
    if [ $retval -ne 0 ]; then return 1; fi
  fi
  return 0
}

function build_lists() # Called by check_parts to generate details of existing partitions
{ # 1) Produces a list of partition IDs, from which items are removed as allocated to root, etc.
  #    This is the 'master' list, and the two associative arrays are keyed to this.
  # 2) Saves any existing labels on any partitions into an associative array, Labelled[]
  # 3) Assembles information about all partitions in another associative array, PartitionArray

  # 1) Make a simple list variable of all partitions up to sd*99
                                         # | includes keyword " TYPE=" | select 1st field | ignore /dev/
    PartitionList=$(sudo blkid /dev/sd* | grep /dev/sd.[0-9] | grep ' TYPE=' | cut -d':' -f1 | cut -d'/' -f3) # eg: sdb1
    
  # 2) List IDs of all partitions with "LABEL=" | select 1st field (eg: sdb1) | remove colon | remove /dev/
    ListLabelledIDs=$(sudo blkid /dev/sd* | grep /dev/sd.[0-9] | grep LABEL= | cut -d':' -f1 | cut -d'/' -f3)
    # If at least one labelled partition found, add a matching record to associative array Labelled[]
    for item in $ListLabelledIDs
    do      
      Labelled[$item]=$(sudo blkid /dev/sd* | grep /dev/$item | sed -n -e 's/^.*LABEL=//p' | cut -d'"' -f2)
    done

  # 3) Add records to the other associative array, PartitionArray, corresponding to PartitionList
    for part in ${PartitionList}
    do
      # Get size and mountpoint of that partition
      SizeMount=$(lsblk -l | grep "${part} " | awk '{print $4 " " $7}')      # eg: 7.5G [SWAP]
      # And the filesystem:        | just the text after TYPE= | select first text inside double quotations
      Type=$(sudo blkid /dev/$part | sed -n -e 's/^.*TYPE=//p' | cut -d'"' -f2) # eg: ext4
      PartitionArray[$part]="$SizeMount $Type" # ... and save them to the associative array
    done
    # Add label and bootable flag to PartitionArray
    for part in ${PartitionList}
    do
      # Test if flagged as bootable
      Test=$(sfdisk -l 2>/dev/null | grep /dev | grep "$part" | grep '*')
      if [ -n "$Test" ]; then
        Bootable="Bootable"
      else
        Bootable=""
      fi
      # Read the current record for this partition in the array
      Temp="${PartitionArray[${part}]}"
      # ... and add the new data
      PartitionArray[${part}]="$Temp ${Labelled[$part]} ${Bootable}" 
      # eg: PartitionArray[sdb1] = "912M /media/elizabeth/Lubuntu dos Lubuntu 17.04 amd64"
      #               | partition | size | -- mountpoint -- | filesystem | ------ label ------- |
    done
}

function partitioning_options()  # Called by check_parts after user selects an action.
{ # Directs response to selected option
  case $Result in
    1) echo "Manual partition allocation" >> feliz.log  # Existing Partitions option
    ;;
    2) cfdisk 2>> feliz.log     # Open cfdisk for manual partitioning
      tput setf 0               # Change foreground colour to black temporarily to hide error message
      clear
      partprobe 2>> feliz.log   # Inform kernel of changes to partitions
      tput sgr0                 # Reset colour
      return 0                  # finish partitioning
    ;;
    3) if [ ${UEFI} -eq 1 ]; then
        guided_EFI              # Guided manual partitioning functions
        retval=$?
        if [ $retval -ne 0 ]; then return 1; fi
        tput setf 0             # Change foreground colour to black temporarily to hide error message
        clear
        partprobe 2>> feliz.log #Inform kernel of changes to partitions
        tput sgr0               # Reset colour
        ShowPartitions=$(lsblk -l | grep 'part' | cut -d' ' -f1)
      else
        guided_MBR
        if [ $? -ne 0 ]; then return 1; fi
        tput setf 0             # Change foreground colour to black temporarily to hide error message
        clear
        partprobe 2>> feliz.log # Inform kernel of changes to partitions
        tput sgr0               # Reset colour
      fi
    ;;
    4) choose_device
      retval=$?
      if [ $retval -ne 0 ]; then return 1; fi
    ;;
    *) not_found 10 50 "Error reported at function $FUNCNAME line $LINENO in $SOURCE0 called from $SOURCE1"
  esac
}

function choose_device()  # Called from partitioning_options or partitioning_optionsEFI
{ # Choose device for autopartition
  AutoPart="OFF"
  until [ ${AutoPart} != "OFF" ]
  do
    DiskDetails=$(lsblk -l | grep 'disk' | cut -d' ' -f1)
    # Count lines. If more than one disk, ask user which to use
    local Counter=$(echo "$DiskDetails" | wc -w)
    menu_dialogVariable="$DiskDetails"
    UseDisk=""
    if [ $Counter -gt 1 ]
    then
      while [ -z $UseDisk ]
      do
        translate "These are the available devices"
        title="$Result"
        message_first_line "Which do you wish to use for this installation?"
        message_subsequent "   (Remember, this is auto-partition, and any data"
        translate "on the chosen device will be destroyed)"
        Message="${Message}\n      ${Result}\n"
        echo
        
        menu_dialog 15 60
        if [ $retval -ne 0 ]; then return 1; fi
        UseDisk="${Result}"
      done
    else
      UseDisk=$DiskDetails
    fi
    title="Warning"
    translate "This will erase any data on"
    Message="${Result} /dev/${UseDisk}"
    message_subsequent "Are you sure you wish to continue?"
    Message="${Message}\n${Result}"
    dialog --backtitle "$Backtitle" --title " $title " \
      --yes-label "$Yes" --no-label "$No" --yesno "\n$Message" 10 55 2>output.file
    retval=$?
    case $retval in
    0) AutoPart="ON"
      return 0
    ;;
    1) UseDisk=""
    ;;
    *) not_found 10 50 "Error reported at function $FUNCNAME line $LINENO in $SOURCE0 called from $SOURCE1"
    esac
    return 1
  done
}

partition_maker() { # Called from autopart() for both EFI and BIOS systems
                    # Receives up to 4 arguments
                    # $1 is the starting point of the first partition
                    # $2 is size of root partition
                    # $3 if passed is size of home partition
                    # $4 if passed is size of swap partition
                    # Note that an appropriate partition table has already been created in autopart()
                    #   If EFI the /boot partition has also been created at /dev/sda1 and set as bootable
                    #   and the startpoint has been set to follow /boot
                    
  local StartPoint=$1                               # Local variable 

  # Set the device to be used to 'set x boot on'    # $MountDevice is numerical - eg: 1 in sda1
  MountDevice=1                                     # Start with first partition = [sda]1
                                                    # Make /boot at startpoint
  parted_script "mkpart primary ext4 ${StartPoint} ${2}"   # eg: parted /dev/sda mkpart primary ext4 1MiB 12GiB
  parted_script "set ${MountDevice} boot on"               # eg: parted /dev/sda set 1 boot on
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
}

function autopart() # Called by choose_device
{ # Consolidated automatic partitioning for BIOS or EFI environment
  GrubDevice="/dev/${UseDisk}"
  Home="N"                                          # No /home partition at this point
  DiskSize=$(lsblk -l | grep "${UseDisk}\ " | awk '{print $4}' | sed "s/G\|M\|K//g") # Get disk size
  tput setf 0                                       # Change foreground colour to black to hide error message
  clear

  # Create a new partition table
  if [ ${UEFI} -eq 1 ]; then                        # Installing in UEFI environment
    sgdisk --zap-all ${GrubDevice} &>> feliz.log    # Remove all existing filesystems
    wipefs -a ${GrubDevice} &>> feliz.log           # from the drive
    parted_script "mklabel gpt"                            # Create new filesystem
    parted_script "mkpart primary fat32 1MiB 513MiB"       # EFI boot partition
    StartPoint="513MiB"                             # For next partition
  else                                              # Installing in BIOS environment
    dd if=/dev/zero of=${GrubDevice} bs=512 count=1 # Remove any existing partition table
    parted_script "mklabel msdos"                          # Create new filesystem
    StartPoint="1MiB"                               # For next partition
  fi

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
  tput sgr0                                         # Reset colour
}

function allocate_partitions()  # Called by feliz.sh after check_parts
{ # Calls allocate_root, allocate_swap, no_swap_partition, more_partitions
  
  RootPartition=""
  while [ "$RootPartition" = "" ]
  do
    allocate_root                       # User must select root partition
    retval=$?
    if [ $retval -ne 0 ]; then return 1; fi
  done
                                        # All others are optional
  if [ -n "${PartitionList}" ]; then    # If there are unallocated partitions
    allocate_swap                       # Display display them for user to choose swap
    retval=$?
    if [ $retval -ne 0 ]; then return 1; fi
  else                                  # If there is no partition for swap
    no_swap_partition                      # Inform user and allow swapfile
    retval=$?
    if [ $retval -ne 0 ]; then return 1; fi
  fi
  
  for i in ${PartitionList}             # Check contents of PartitionList
  do
    echo $i > output.file               # If anything found, echo to file
    break                               # Break on first find
  done
  Result="$(cat output.file)"           # Check for output
  if [ "${Result}" = "" ]; then         # If any remaining partitions
    more_partitions                     # Allow user to allocate
    retval=$?
    if [ $retval -ne 0 ]; then return 1; fi
  fi
}

function select_filesystem()  # Called by allocate_root and more_partitions (via choose_mountpoint) & guided_
{ # and guided_MBR and guided_EFI 
  # Receives two arguments: $1 $2 are window size
  # User chooses filesystem from menu
  translate "Please select the file system for"
  title="$Result ${Partition}"
  message_first_line "It is not recommended to mix the btrfs file-system with others"
  menu_dialogVariable="ext4 ext3 btrfs xfs"
  
  menu_dialog $1 $2
  retval=$?
  if [ $retval -ne 0 ]; then return 1; fi
  PartitionType="$Result"
}

function edit_label() # Called by allocate_root, allocate_swap & more_partitions
{ # If a partition has a label, allow user to change or keep it
  Label="${Labelled[$1]}"
  
  if [ -n "${Label}" ]; then
    # Inform the user and accept input
    translate "The partition you have chosen is labelled"
    Message="$Result '${Label}'"
    translate "Keep that label"
    Keep="$Result"
    translate "Delete the label"
    Delete="$Result"
    translate "Enter a new label"
    Edit="$Result"

    dialog --backtitle "$Backtitle" --title " $PassPart " \
      --ok-label "$Ok" --cancel-label "$Cancel" --menu "$Message" 24 50 3 \
      1 "$Keep" \
      2 "$Delete" \
      3 "$Edit" 2>output.file
    retval=$?
    if [ $retval -ne 0 ]; then return 1; fi
    Result="$(cat output.file)"  
    # Save to the -A array
    case $Result in
      1) Labelled[$PassPart]=$Label
      ;;
      2) Labelled[$PassPart]=""
      ;;
      3) Message="Enter a new label"                  # English.lan #87
        dialog_inputbox 10 40
        retval=$?
        if [ $retval -ne 0 ]; then return 1; fi
        if [ -z $Result ]; then return 1; fi
        Labelled[$PassPart]=$Result
    esac
  fi
}

function allocate_root() # Called by allocate_partitions
{ # Display partitions for user-selection of one as /root
  #  (uses list of all available partitions in PartitionList)

  if [ ${UEFI} -eq 1 ]; then        # Installing in UEFI environment
    allocate_uefi                   # First allocate the /boot partition (sets boot on for EFI)
    retval=$?
    if [ $retval -ne 0 ]; then return 1; fi
  fi
  Remaining=""
  Partition=""
  PartitionType=""
  message_first_line "Please select a partition to use for /root"
  display_partitions
  retval=$?
  if [ $retval -ne 0 ]; then
    PartitionType=""
    return 1
  fi
  
  PassPart=${Result:0:4}          # eg: sda4
  MountDevice=${PassPart:3:2}     # Save the device number for 'set x boot on'
  Partition="/dev/$Result"
  RootPartition="${Partition}"

  # Before going to select_filesystem, check if there is an existing file system on the selected partition
  check_filesystem  # This sets variable CurrentType and starts the Message
  Message="\n${Message}"
  if [ -n ${CurrentType} ]; then
    message_subsequent "You can choose to leave it as it is, but should"
    message_subsequent "understand that not reformatting the /root"
    message_subsequent "partition can have unexpected consequences"
  fi
  
  # Now select a filesystem
  select_filesystem  18 75      # This sets variable PartitionType
  retval=$?
  if [ $retval -ne 0 ]; then    # User has cancelled the operation
    PartitionType=""            # PartitionType can be empty (will not be formatted)
  else
    PartitionType="$Result"
  fi
  
  RootType="${PartitionType}" 
  Label="${Labelled[${PassPart}]}"
  if [ -n "${Label}" ]; then
    edit_label $PassPart
  fi

  if [ ${UEFI} -eq 0 ]; then                    # Installing in BIOS environment
    parted_script "set ${MountDevice} boot on"         # Make /root bootable
  fi

  PartitionList=$(echo "$PartitionList" | sed "s/$PassPart//") # Remove the used partition from the list

}

function check_filesystem()
{ # Finds if there is an existing file system on the selected partition
  CurrentType=$(sudo blkid $Partition | sed -n -e 's/^.*TYPE=//p' | cut -d'"' -f2)

  if [ -n ${CurrentType} ]; then
    message_first_line "The selected partition"
    translate "is currently formatted to"
    Message="$Message $Result $CurrentType"
    message_subsequent "Reformatting it will remove all data currently on it"
  fi
}

function allocate_swap()
{
  message_first_line "Select a partition for swap from the ones that"
  message_subsequent "remain, or you can allocate a swap file"
  message_subsequent "Warning: Btrfs does not support swap files"
  
  SwapPartition=""
  
  translate "If you skip this step, no swap will be allocated"
  title="$Result"

  SavePartitionList="$PartitionList"
  PartitionList="$PartitionList swapfile"
  
  SwapFile=""
  
  display_partitions
  retval=$?
  if [ $retval -ne 0 ]; then return 1; fi
  case "$Result" in
  "swapfile") set_swap_file
            SwapPartition=""
            return 0
  ;;
  *) SwapPartition="/dev/$Result"
    IsSwap=$(sudo blkid $SwapPartition | grep 'swap' | cut -d':' -f1)
    if [ -n "$IsSwap" ]; then
      translate "is already formatted as a swap partition"
      Message="$SwapPartition $Result"
      message_subsequent "Reformatting it will change the UUID, and if this swap"
      message_subsequent "partition is used by another operating system, that"
      message_subsequent "system will no longer be able to access the partition"
      message_subsequent "Do you wish to reformat it?"
      MakeSwap="N"
      dialog --backtitle "$Backtitle" --title " $title " \
        --yes-label "$Yes" --no-label "$No" --yesno "\n$Message" 13 70 2>output.file
      retval=$?
      if [ $retval -ne 0 ]; then return 1; fi
      Result=$(cat output.file)
      MakeSwap="Y"
      Label="${Labelled[${SwapPartition}]}"
      if [ -n "${Label}" ]; then
        edit_label "$PassPart"
      fi
    fi
    
    PartitionList="$SavePartitionList"                            # Restore PartitionList without 'swapfile'
    
    if [ $SwapPartition ] && [ $SwapPartition = "" ]; then
      translate "No provision has been made for swap"
      dailog --ok-label "$Ok" --msgbox "$Result" 6 30
    elif [ $SwapFile ]; then
      dailog --ok-label "$Ok" --msgbox "Swap file = ${SwapFile}" 5 20
    elif [ $SwapPartition ] && [ $SwapPartition != "swapfile" ]; then
      PartitionList=$(echo "$PartitionList" | sed "s/$Result//")  # Remove the used partition from the list
    fi
  esac
}

function no_swap_partition()
{ # There are no unallocated partitions
  message_first_line "There are no partitions available for swap"
  message_subsequent "but you can allocate a swap file, if you wish"
  title="Create a swap file?"

  dialog --backtitle "$Backtitle" --title " $title " \
    --yes-label "$Yes" --no-label "$No"--yesno "\n$Message" 10 55 2>output.file
  retval=$?
  case $retval in
  0) set_swap_file
    SwapPartition=""
   ;;
  *) SwapPartition=""
    SwapFile=""
  esac
}

function set_swap_file()
{
  SwapFile=""
  while [ ${SwapFile} = "" ]
  do
    message_first_line "Allocate the size of your swap file"
    dialog_inputbox "M = Megabytes, G = Gigabytes [eg: 512M or 2G]: "
    if [ $retval -ne 0 ]; then SwapFile=""; return 0; fi
    RESPONSE="${Result^^}"
    # Check that entry includes 'M or G'
    CheckInput=$(grep "G\|M" <<< "${RESPONSE}" )
    if [ -z ${CheckInput} ]; then
      message_first_line "You must include M or G"
      SwapFile=""
    else
      SwapFile=$RESPONSE
      break
    fi
  done
}

function more_partitions()
{ # If partitions remain unallocated, user may select for /home, etc
  local Elements=$(echo "$PartitionList" | wc -w)

  while [ $Elements -gt 0 ]
  do
    message_first_line "The following partitions are available"
    message_subsequent "If you wish to use one, select it from the list"

    display_partitions 
    if [ $retval -ne 0 ]; then return 1; fi # $retval greater than 0 means user cancelled or escaped; no partition selected
    PassPart=${Result:0:4}                  # $retval 0 means user selected a partition; isolate first 4 characters
    Partition="/dev/$PassPart"
    choose_mountpoint                           # Complete details
    retval=$?                               # May return 1 if cancelled by user
    if [ $retval -ne 0 ]; then return 1; fi # $retval greater than 0 means user cancelled or escaped; no details added, so abort
    
    Label="${Labelled[${PassPart}]}"
    if [ -n "${Label}" ]; then
      edit_label $PassPart
      
    fi

    PartitionList=$(echo "$PartitionList" | sed "s/$PassPart//") # Remove the used partition from the list
    Elements=$(echo "$PartitionList" | wc -w)

  done
  # Ensure that if AddPartList (the defining array) is empty, all others are too
  if [ -z ${#AddPartList[@]} ]
  then
    AddPartList=""
    AddPartMount=""
    AddPartType=""
  fi
}

function choose_mountpoint() # Called by more_partitions
{ # Allows user to choose filesystem and mountpoint
  # Returns 0 if completed, 1 if interrupted

  check_filesystem                                    # Before going to select_filesystem, check the partition
  if [ ${CurrentType} ]; then
    message_first_line "You can choose to leave it as it is, by selecting Exit, but not"
    message_subsequent "reformatting an existing partition can have unexpected consequences"
  fi
  
  select_filesystem
  retval=$?                                         # May return 1 if cancelled by user; no filesystem selected
  if [ $retval -ne 0 ]; then return 1; fi           # $retval greater than 0 means user cancelled or escaped, so abort

  PartMount=""
  while [ ${PartMount} = "" ]
  do
    message_first_line "Enter a mountpoint for"
    Message="$Message ${Partition}\n(eg: /home) ... "
    
    dialog_inputbox                                        # Get a mountpoint
    retval=$?                                       # May return 1 if cancelled by user; no mountpoint selected
    if [ $retval -ne 0 ]; then return 1; fi         # $retval greater than 0 means user cancelled or escaped, so abort
    
    CheckInput=${Response:0:1}                      # First character of ${Response}
    case ${CheckInput} in                           # Check that entry includes '/'
      '') message_first_line "You must enter a valid mountpoint"
          PartMount=""
          ;;
      *) if [ ${CheckInput} != "/" ]; then
            PartMount="/${Response}"
        else
            PartMount="${Response}"
        fi
    esac

    if [ ${#AddPartMount[@]} -gt 0 ]; then          # If there are existing (extra) mountpoints
      for MountPoint in ${AddPartMount}             # Go through AddPartMount checking each item against PartMount
      do
        if [ $MountPoint = $PartMount ]; then       # If the mountpoint has already been used
          dialog --backtitle "$Backtitle" --ok-label "$Ok" \
            --msgbox "\nMountpoint ${PartMount} has already been used.\nPlease use a different mountpoint." 6 30
          PartMount=""
          break
        fi
      done
    fi
  done
  # Add the selected partition to the arrays for extra partitions
  ExtraPartitions=${#AddPartList[@]}                # Count items in AddPartList
  AddPartList[$ExtraPartitions]="${Partition}"      # Add this item (eg: /dev/sda5)
  AddPartType[$ExtraPartitions]="${PartitionType}"  # Add filesystem
  AddPartMount[$ExtraPartitions]="${PartMount}"
  return 0
}

function display_partitions() # Called by more_partitions, allocate_swap & allocate_root
{ # Uses $PartitionList & ${PartitionArray[@]} to generate a menu of available partitions
  # Sets $retval (0/1) and $Result (Item text)
  # Calling function must validate output

  declare -a ItemList=()                                    # Array will hold entire list
  Items=0
  for Item in $PartitionList
  do 
    Items=$((Items+1))
    ItemList[${Items}]="${Item}"                            # and copy each one to the array
    Items=$((Items+1))
    if [ "$Item" = "swapfile" ]; then
      ItemList[${Items}]="Use a swap file"
    else
      ItemList[${Items}]="${PartitionArray[${Item}]}"       # Second element is required
    fi
  done

  dialog --backtitle "$Backtitle" --title " $title " --ok-label "$Ok" \
    --cancel-label "$Cancel" --menu "$Message" 18 70 ${Items} "${ItemList[@]}" 2>output.file
  retval=$?
  Result=$(cat output.file)
}
