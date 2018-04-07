#!/bin/bash

# The Feliz installation scripts for Arch Linux
# Developed by Elizabeth Mills  liz@feliz.one
# With grateful acknowlegements to Helmuthdu, Carl Duff and Dylan Schacht
# Revision date: 4th April 2018

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
# check_parts           45    no_swap_partition   346
# use_parts             87    set_swap_file       361
# build_lists           99    more_partitions     382
# allocate_partitions  142    choose_mountpoint   430 
# parted_script        150    display_partitions  461  
# allocate_root        200    allocate_uefi       489 
# allocate_swap        245    
# select_device        285    get_device_size     570 
# ------------------------    ------------------------

# Variables for UEFI Architecture
UEFI=0                  # 1 = UEFI; 0 = BIOS
EFIPartition=""         # eg: /dev/sda1
UEFI_MOUNT=""    	      # UEFI mountpoint
DualBoot="N"            # For formatting EFI partition

function check_parts {  # Called by feliz.sh and f-set.sh
                        # Tests for existing partitions, informs user, calls build_lists to prepare arrays
                        # Displays menu of options, then calls partitioning_options to act on user selection
  if [ "$UEFI" -eq 1 ]; then
    GrubDevice="EFI"                                                   # Preset $GrubDevice if installing in EFI
  fi

  ShowPartitions=$(lsblk -l "$RootDevice" | grep 'part' | cut -d' ' -f1) # List all partitions on the device
  PARTITIONS=$(echo "$ShowPartitions" | wc -w)

  if [ "$PARTITIONS" -eq 0 ]; then                                     # If no partitions exist, notify
    message_first_line "There are no partitions on the device"
    message_subsequent "Please read the 'partitioning' file for advice."

    translate "Exit Feliz to the command line"
    first_item="$Result"
    translate "Shut down this session"
    second_item="$Result"
    translate "Allow Feliz to partition the device"
    third_item="$Result"
    translate "Use Guided Manual Partitioning"
    fourth_item="$Result"
    translate "Display the 'partitioning' file"
    fifth_item="$Result"

    while true
    do
      dialog --backtitle "$Backtitle" --title " Partitioning " \
      --ok-label "$Ok" --cancel-label "$Cancel" --menu "$Message" 15 50 5 \
        1 "$first_item" \
        2 "$second_item" \
        3 "$third_item" \
        4 "$fourth_item" \
        5 "$fifth_item" 2>output.file
      if [ $? -ne 0 ]; then return 1; fi
      Result=$(cat output.file)
    
      case $Result in
        1) exit ;;
        2) shutdown -h now ;;
        3) auto_warning
            if [ $retval -ne 0 ]; then continue; fi         # If 'No' then display menu again
            autopart ;;
        4) guided_partitions ;;
        *) more partitioning                              # Use bash 'more' to display help file
          continue
      esac
      if [ $? -eq 0 ]; then return 0; else return 1; fi
    done
  else
    autopart="MANUAL"
  fi
}

function use_parts {    # Called by feliz.sh/the_start step 7 to display existing partitions
  build_lists                                           # Generate list of partitions and matching array
  translate "Here is a list of available partitions"
  Message="\n               ${Result}:\n"

  for part in ${PartitionList}; do
    Message="${Message}\n        $part ${PartitionArray[${part}]}"
  done
}

function build_lists { # Called by check_parts to generate details of existing partitions
  # 1) Produces a list of partition IDs, from which items are removed as allocated to root, etc.
  #    This is the 'master' list, and the two associative arrays are keyed to this list.
  # 2) Saves any existing labels on any partitions into an associative array - Labelled
  # 3) Assembles information about all partitions in another associative array - PartitionArray

  # 1) Make a simple list variable of all partitions up to sd*99
                         # | starts /dev/  | select 1st field | ignore /dev/
  PartitionList=$(fdisk -l | grep '^/dev/' | cut -d' ' -f1 | cut -d'/' -f3) # eg: sda1 sdb1 sdb2

  # 2) List IDs of all partitions with "LABEL=" | select 1st field (eg: sdb1) | remove colon | remove /dev/
    ListLabelledIDs=$(blkid /dev/sd* | grep '/dev/sd.[0-9]' | grep LABEL= | cut -d':' -f1 | cut -d'/' -f3)
    # If at least one labelled partition found, add a matching record to associative array Labelled[]
    for item in $ListLabelledIDs; do      
      Labelled[$item]=$(blkid /dev/sd* | grep "/dev/$item" | sed -n -e 's/^.*LABEL=//p' | cut -d'"' -f2)
    done

  # 3) Add records to the other associative array, PartitionArray, corresponding to PartitionList
    for part in ${PartitionList}; do
      # Get size and mountpoint of that partition
      SizeMount=$(lsblk -l "$RootDevice" | grep "${part} " | awk '{print $4 " " $7}')      # eg: 7.5G [SWAP]
      # And the filesystem:        | just the text after TYPE= | select first text inside double quotations
      Type=$(blkid /dev/"$part" | sed -n -e 's/^.*TYPE=//p' | cut -d'"' -f2) # eg: ext4
      PartitionArray[$part]="$SizeMount $Type" # ... and save them to the associative array
    done
    # Add label and bootable flag to PartitionArray
    for part in ${PartitionList}; do
      # Test if flagged as bootable
      Test=$(sfdisk -l 2>/dev/null | grep '/dev' | grep "$part" | grep '*')
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

function allocate_partitions { # Called by feliz.sh
                               # Calls allocate_root, allocate_swap, no_swap_partition, more_partitions
  RootPartition=""
  while [ -z "$RootPartition" ]; do
    allocate_root                       # User must select root partition
    if [ "$?" -ne 0 ]; then return 1; fi
  done
                                        # All others are optional
  if [ -n "$PartitionList" ]; then      # If there are unallocated partitions
    allocate_swap                       # Display display them for user to choose swap
  else                                  # If there is no partition for swap
    no_swap_partition                   # Inform user and allow swapfile
  fi
  if [ -z "$PartitionList" ]; then return 0; fi
  for i in ${PartitionList}; do         # Check contents of PartitionList
    echo "$i" > output.file               # If anything found, echo to file
    break                               # Break on first find
  done
  Result="$(cat output.file)"           # Check for output
  if [ "${Result}" != "" ]; then        # If any remaining partitions
    more_partitions                     # Allow user to allocate
  fi
}

function parted_script { # Calls GNU parted tool with options
  parted --script "/dev/${UseDisk}" "$1" 2>> feliz.log
}

function check_filesystem { # Called by choose_mountpoint & allocate_root
                            # Checks file system type on the selected partition
                            # Sets $CurrentType to existing file system type
  CurrentType=$(blkid "$Partition" | sed -n -e 's/^.*TYPE=//p' | cut -d'"' -f2)
}


function allocate_root {  # Called by allocate_partitions
                          # Display partitions for user-selection of one as /root
                          #  (uses list of all available partitions in PartitionList)
  if [ "$UEFI" -eq 1 ]; then        # Installing in UEFI environment
    allocate_uefi                   # First allocate the /boot partition
    retval=$?
    if [ $retval -ne 0 ]; then return 1; fi
  fi
  Remaining=""
  Partition=""
  PartitionType=""
  message_first_line "Please select a partition to use for /root"
  display_partitions
  if [ $retval -ne 0 ]; then        # User selected <Cancel>
    PartitionType=""
    return 1
  fi
  
  PassPart=${Result:0:4}            # eg: sda4
  MountDevice=${PassPart:3:2}       # Save the device number for 'set x boot on'
  Partition="/dev/$Result"
  RootPartition="${Partition}"

  if [ "$AutoPart" = "MANUAL" ]; then # Not required for AUTO or GUIDED
                                    # Check if there is an existing filesystem on the selected partition
    check_filesystem                # This sets variable CurrentType and starts the Message
    Message="\n${Message}"
    if [ -n "$CurrentType" ]; then
      dialog --backtitle "$Backtitle" --title " Root Partition " \
    --yes-label "$Yes" --no-label "$No" --yesno "\nReformat the root partition?" 6 50
      retval=$?
      if [ $retval -eq 0 ]; then
        PartitionType="$CurrentType"    # Reformat to current type
      else
        PartitionType=""                # PartitionType can be empty (will not be formatted)
      fi
      RootType="${PartitionType}"
    fi
  fi

  PartitionList=$(echo "$PartitionList" | sed "s/$PassPart//")  # Remove the used partition from the list
}

function allocate_swap { # Called by allocate_partitions
  message_first_line "Select a partition for"
  Message="$Message /swap"
  message_subsequent "Or you can assign a swap file"
  message_subsequent "Warning: Btrfs does not support swap files"
  SwapPartition=""
  SwapFile=""
  translate "If you skip this step, no swap will be allocated"
  title="$Result"
  SavePartitionList="$PartitionList"
  PartitionList="$PartitionList swapfile"
  display_partitions  # Sets $retval & $Result, and returns 0 if it completes
  if [ $retval -ne 0 ]; then
    FormatSwap="N"
    return 1          # Returns 1 to caller if no partition selected
  fi
  FormatSwap="Y"
  Swap="$Result"
  if [ "$Swap" = "swapfile" ]; then
    set_swap_file
  else
    SwapPartition="/dev/$Swap"
    IsSwap=$(blkid "$SwapPartition" | grep 'swap' | cut -d':' -f1)
    MakeSwap="Y"
  fi
  PartitionList="$SavePartitionList"                                        # Restore PartitionList without 'swapfile'
  if [ -z "$SwapPartition" ] && [ -z "$SwapFile" ]; then
    translate "No provision has been made for swap"
    dialog --ok-label "$Ok" --msgbox "$Result" 6 30
  elif [ -n "$SwapPartition" ] && [ "$SwapPartition" != "swapfile" ]; then
    PartitionList=$(echo "$PartitionList" | sed "s/$Swap//")              # Remove the used partition from the list
  elif [ -n "$SwapFile" ]; then
    dialog --ok-label "$Ok" --msgbox "Swap file = ${SwapFile}" 5 20
  fi
  return 0
}

function select_device {  # Called by f-part.sh/check_parts
                          # Detects available devices
  # First list all devices with their sizes
  DiskDetails=$(lsblk -l -o NAME,SIZE,TYPE | grep disk | sed 's/disk//')  # eg: sda 10G sdb 215G

  local Counter=$(echo "$DiskDetails" | wc -w)
  Counter=$((Counter/2))
  if [ "$Counter" -gt 1 ]; then   # If there are multiple devices ask user which to use
    UseDisk=""                    # Reset
    while [ -z "$UseDisk" ]; do
      message_first_line "There are"
      Message="$Message $Counter"
      translate "devices available"
      Message="$Message $Result"
      message_subsequent "Which do you wish to use for this installation?"

      declare -a ItemList=()                                    # Array will hold entire list for menu display
      Items=0
      for Item in $DiskDetails; do 
        Items=$((Items+1))
        ItemList[${Items}]="${Item}"                            # eg: sda1
      done
      
      if [ "$Items" -gt 0 ]; then                               # Display for selection
        dialog --backtitle "$Backtitle" --title " $title " --ok-label "$Ok" \
        --cancel-label "$Cancel" --menu "$Message" 18 70 ${Items} "${ItemList[@]}" 2>output.file
        retval=$?
        Result=$(cat output.file)
        UseDisk="$Result"

        if [ "$retval" -ne 0 ]; then
          dialog --title "$title" --yes-label "$Yes" --no-label "$No" --yesno \
          "\nPartitioning cannot continue without a device.\nAre you sure you don't want to select a device?" 10 50
          if [ "$?" -eq 0 ]; then
            UseDisk=""
            RootDevice=""
            return 1
          fi
        fi
        UseDisk="$Result"
      fi
    done
  else                          # If only one device
    UseDisk=$(echo "$DiskDetails" | cut -d' ' -f1)        # Save just the name
  fi

  RootDevice="/dev/${UseDisk}"  # Full path of selected device
  EFIPartition="${RootDevice}1"
}

function no_swap_partition {  # Called by allocate_partitions when there are no unallocated partitions
  message_first_line "There are no partitions available for swap"
  message_subsequent "but you can assign a swap file"
  dialog --backtitle "$Backtitle" --title " $title " \
    --yes-label "$Yes" --no-label "$No"--yesno "\n$Message" 14 60 2>output.file
  case $? in
  0) set_swap_file
    SwapPartition="" ;;
  *) SwapPartition=""
    SwapFile=""
  esac
  return 0
}

function set_swap_file {
  SwapFile=""
  while [ -z ${SwapFile} ]; do
    message_first_line "Set the size of your swap file"
    message_subsequent "M = Megabytes, G = Gigabytes [ eg: 512M or 2G ]"
    title="Swap File"

    dialog_inputbox 12 60
 
    if [ $retval -ne 0 ]; then SwapFile=""; return 0; fi
    RESPONSE="${Result^^}"
    # Check that entry includes 'M or G'
    CheckInput=$(grep "G\|M" <<< "${RESPONSE}" )
    if [ -z "$CheckInput" ]; then
      message_first_line "You must include M or G"
      SwapFile=""
    else
      SwapFile="$RESPONSE"
      break
    fi
  done
  return 0
}

function more_partitions {  # Called by allocate_partitions if partitions remain
                            # unallocated. User may select for /home, etc
  translate "Partitions"
  title="$Result"
  declare -i Elements
  Elements=$(echo "$PartitionList" | wc -w)

  while [ "$Elements" -gt 0 ]; do
    message_first_line "The following partitions are available"
    message_subsequent "If you wish to use one, select it from the list"

    display_partitions                        # Sets $retval & $Result, and returns 0 if completed

    if [ "$retval" -ne 0 ]; then return 1; fi # User cancelled or escaped; no partition selected. Inform caller
    PassPart=${Result:0:4}                    # Isolate first 4 characters of partition
    Partition="/dev/$PassPart"
    choose_mountpoint   # Calls dialog_inputbox to manually enter mountpoint
                        # Validates response, warns if already used, then adds the partition to
    retval=$?           # the arrays for extra partitions. Returns 0 if completed, 1 if interrupted

    if [ $retval -ne 0 ]; then return 1; fi # Inform calling function that user cancelled; no details added

    # If this point has been reached, then all data for a partiton has been accepted
    # So add it to the arrays for extra partitions
    ExtraPartitions=${#AddPartList[@]}                # Count items in AddPartList

    AddPartList[$ExtraPartitions]="${Partition}"      # Add this item (eg: /dev/sda5)
    AddPartType[$ExtraPartitions]="${PartitionType}"  # Add filesystem
    AddPartMount[$ExtraPartitions]="${PartMount}"     # And the mountpoint
  
    PartitionList=$(echo "$PartitionList" | sed "s/$PassPart//") # Remove the used partition from the list
    Elements=$(echo "$PartitionList" | wc -w)                     # and count remaining partitions
  done

  # Ensure that if AddPartList (the defining array) is empty, all others are too
  if [ ${#AddPartList[@]} -eq 0 ]; then
    AddPartMount=()
    AddPartType=()
  fi

  return 0
}

function choose_mountpoint {  # Called by more_partitions. Uses $Partition set by caller
                              # Allows user to choose filesystem and mountpoint
                              # Returns 0 if completed, 1 if interrupted
  declare -i formatPartition=0                      # Set to reformat
  message_first_line "Enter a mountpoint for"
  Message="$Message ${Partition}\n(eg: /home) ... "
  
  dialog_inputbox 10 50                           # User manually enters a mountpoint; Sets $retval & $Result
                                                  # Returns 0 if completed, 1 if cancelled by user
  if [ $retval -ne 0 ]; then return 1; fi         # No mountpoint selected, so inform calling function
  Response=$(echo "$Result" | sed 's/ //')        # Remove any spaces
  CheckInput=${Response:0:1}                      # First character of user input
  if [ "$CheckInput" = "/" ]; then                # Ensure that entry includes '/'
    PartMount="$Response"
  else
    PartMount="/${Response}"
  fi

  if [ ${#AddPartMount[@]} -gt 0 ]; then          # If there are existing (extra) mountpoints
    for MountPoint in ${AddPartMount}; do         # Go through AddPartMount
      if [ "$MountPoint" = "$PartMount" ]; then       # If the mountpoint has already been used
        dialog --backtitle "$Backtitle" --ok-label "$Ok" \
          --msgbox "\nMountpoint ${PartMount} has already been used.\nPlease use a different mountpoint." 6 30
        PartMount=""                              # Ensure that outer loop will continue
        break
      fi
    done
  fi
  return 0
}

function display_partitions { # Called by more_partitions, allocate_swap & allocate_root
                              # Uses $PartitionList & PartitionArray to generate menu of available partitions
                              # Sets $retval (0/1) and $Result (Item text from output.file - eg: sda1)
                              # Calling function must validate output
  declare -a ItemList=()                                    # Array will hold entire list for menu display
  Items=0
  for Item in $PartitionList; do 
    Items=$((Items+1))
    ItemList[${Items}]="${Item}"                            # eg: sda1
    Items=$((Items+1))
    if [ "$Item" = "swapfile" ]; then
      ItemList[${Items}]="Use a swap file"
    else
      ItemList[${Items}]="${PartitionArray[${Item}]}"       # Matching $Item in associative array of partition details
    fi
  done
  
  if [ "$Items" -gt 0 ]; then                               # Display for selection
    dialog --backtitle "$Backtitle" --title " $title " --ok-label "$Ok" \
    --cancel-label "$Cancel" --menu "$Message" 18 70 ${Items} "${ItemList[@]}" 2>output.file
    retval=$?
    Result=$(cat output.file)
    return 0
  else
    return 1                                                # There are no items to display
  fi
}

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
	message_subsequent "This must be of type vfat, and may be about 512M"
  display_partitions
  if [ $retval -ne 0 ]; then return 1; fi
  PassPart="/dev/${Result}" # eg: sda1
  SetLabel="/dev/${Result}"
	EFIPartition="/dev/${Result}"
  PartitionList=$(echo "$PartitionList" | sed "s/${Result}$//")  # Remove selected item
}

function get_device_size {  # Called by feliz.sh
                            # Establish size of device $UseDisk in MiB and inform user
  DiskSize=$(lsblk -l "$RootDevice" | grep "$UseDisk " | awk '{print $4}') # 1) Get disk size eg: 465.8G
  Unit=${DiskSize: -1}                                          # 2) Save last character (eg: G)
                                  # Remove last character for calculations
  Chars=${#DiskSize}              # Count characters in variable
  Available=${DiskSize:0:Chars-1} # Separate the value from the unit
                                  # Must be integer, so remove any decimal
  Available=${Available%.*}       # point and any character following
  if [ "$Unit" = "G" ]; then
    FreeSpace=$((Available*1024))
    Unit="M"
  elif [ "$Unit" = "T" ]; then
    FreeSpace=$((Available*1024*1024))
    Unit="M"
  else
    FreeSpace=$Available
  fi

  if [ "$FreeSpace" -lt 2048 ]; then    # Warn user if space is less than 2GiB
    message_first_line "Your device has only"
    Message="$Message ${FreeSpace}MiB:"
    message_first_line "This is not enough for an installation"
    translate "Exit"
    dialog --backtitle "$Backtitle" --ok-label "$Ok" --infobox "$Message" 10 60
    return 1
  elif [ "$FreeSpace" -lt 4096 ]; then                            # If less than 4GiB
    message_first_line "Your device has only"
    Message="$Message ${FreeSpace}MiB:"
    message_subsequent "This is just enough for a basic"
    message_subsequent "installation, but you should choose light applications only"
    message_subsequent "and you may run out of space during installation or at some later time"
    dialog --backtitle "$Backtitle" --ok-label "$Ok" --infobox "$Message" 10 60
  elif [ "$FreeSpace" -lt 8192 ]; then                            # If less than 8GiB
    message_first_line "Your device has"
    Messgae="$Message ${FreeSpace}MiB:"
    message_subsequent "This is enough for"
    message_subsequent "installation, but you should choose light applications only"
    dialog --backtitle "$Backtitle" --ok-label "$Ok" --infobox "$Message" 10 60
  fi
}
