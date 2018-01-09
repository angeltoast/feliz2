#!/bin/bash

# The Feliz installation scripts for Arch Linux
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

# In this module - settings for partitioning:
# ------------------------    ------------------------
# Functions           Line    Functions           Line
# ------------------------    ------------------------
# check_parts           40    allocate_root       291
# build_lists          108    check_filesystem    347
# partitioning_options 152    allocate_swap       361
# choose_device        172    no_swap_partition   416   
#                             set_swap_file       431
# allocate_partitions  214    more_partitions     452 
# select_filesystem    242    choose_mountpoint   503 
# edit_label           257    display_partitions  559 
# ------------------------    ------------------------

function check_parts { # Called by feliz.sh
                       # Tests for existing partitions, informs user, calls build_lists to prepare arrays
                       # Displays menu of options, then calls partitioning_options to act on user selection
  translate "Choose from existing partitions"
  LongPart1="$Result"
  translate "Guided manual partitioning tool"
  LongPart2="$Result"
  translate "Allow feliz to partition the whole device"
  LongPart3="$Result"
  title="Partitioning"

  ShowPartitions=$(lsblk -l | grep 'part' | cut -d' ' -f1) # List of all partitions on all connected devices
  PARTITIONS=$(echo $ShowPartitions | wc -w)

  if [ $PARTITIONS -eq 0 ]; then          # If no partitions exist, offer options
    while [ $PARTITIONS -eq 0 ]; do
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

      dialog --backtitle "$Backtitle" --title " $title " --no-tags \
        --ok-label "$Ok" --cancel-label "$Cancel" --menu "$Message" 24 70 4 \
        2 "$LongPart2" \
        3 "$LongPart3" 2>output.file
      if [ $? -ne 0 ]; then return 1; fi
      Result=$(cat output.file)
      partitioning_options                # Act on user selection
      if [ $? -ne 0 ]; then 
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

    for part in ${PartitionList}; do
      Message="${Message}\n        $part ${PartitionArray[${part}]}"
    done

    dialog --backtitle "$Backtitle" --title " $title " --no-tags \
      --ok-label "$Ok" --cancel-label "$Cancel" --menu "$Message" 18 78 4 \
      1 "$LongPart1" \
      2 "$LongPart2" \
      3 "$LongPart3" 2>output.file
    if [ $? -ne 0 ]; then return 1; fi
    Result=$(cat output.file)

    partitioning_options                  # Act on user selection
    if [ $? -ne 0 ]; then return 1; fi
  fi
  return 0
}

function build_lists { # Called by check_parts to generate details of existing partitions
  # 1) Produces a list of partition IDs, from which items are removed as allocated to root, etc.
  #    This is the 'master' list, and the two associative arrays are keyed to this list.
  # 2) Saves any existing labels on any partitions into an associative array - Labelled
  # 3) Assembles information about all partitions in another associative array - PartitionArray

  # 1) Make a simple list variable of all partitions up to sd*99
                         # | starts /dev/  | select 1st field | ignore /dev/
  PartitionList=$(fdisk -l | grep '^/dev/' | cut -d' ' -f1 | cut -d'/' -f3) # eg: sdb1

  # 2) List IDs of all partitions with "LABEL=" | select 1st field (eg: sdb1) | remove colon | remove /dev/
    ListLabelledIDs=$(blkid /dev/sd* | grep '/dev/sd.[0-9]' | grep LABEL= | cut -d':' -f1 | cut -d'/' -f3)
    # If at least one labelled partition found, add a matching record to associative array Labelled[]
    for item in $ListLabelledIDs; do      
      Labelled[$item]=$(blkid /dev/sd* | grep "/dev/$item" | sed -n -e 's/^.*LABEL=//p' | cut -d'"' -f2)
    done

  # 3) Add records to the other associative array, PartitionArray, corresponding to PartitionList
    for part in ${PartitionList}; do
      # Get size and mountpoint of that partition
      SizeMount=$(lsblk -l | grep "${part} " | awk '{print $4 " " $7}')      # eg: 7.5G [SWAP]
      # And the filesystem:        | just the text after TYPE= | select first text inside double quotations
      Type=$(blkid /dev/$part | sed -n -e 's/^.*TYPE=//p' | cut -d'"' -f2) # eg: ext4
      PartitionArray[$part]="$SizeMount $Type" # ... and save them to the associative array
    done
    # Add label and bootable flag to PartitionArray
    for part in ${PartitionList}; do
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
  return 0
}

function partitioning_options { # Called without arguments by check_parts after user selects an action
  case $Result in
  1) echo "Manual partition allocation" >> feliz.log  # Manual allocation of existing Partitions
    AutoPart="MANUAL" ;;                              # Flag - MANUAL/AUTO/GUIDED/NONE
  2) if [ ${UEFI} -eq 1 ]; then
      guided_EFI                                      # Calls guided manual partitioning functions              
      if [ $? -ne 0 ]; then return 1; fi              # then sets GUIDED flag to trigger action_EFI ...
    else                                              # 
      guided_MBR                                      # ... or action_MBR, in installation phase
      if [ $? -ne 0 ]; then return 1; fi
    fi
    AutoPart="GUIDED" ;;
  3) AutoPart=""                                      # Checks if multiple devices, and allows selection
    choose_device
    if [ $? -eq 1 ]; then return 1; fi                # AUTO flag triggers autopart in installation phase
  esac
  return 0
}

function choose_device { # Called from partitioning_options or partitioning_optionsEFI
                         # Select device for autopartition
                         # Sets AutoPart and UseDisk; returns 0 if completed, 1 if interrupted
  while [ -z ${AutoPart} ]; do
    DiskDetails=$(lsblk -l | grep 'disk' | cut -d' ' -f1)
    # Count lines. If more than one disk, ask user which to use
    local Counter
    Counter=$(echo "$DiskDetails" | wc -w)
    menu_dialogVariable="$DiskDetails"
    UseDisk=""
    if [ $Counter -gt 1 ]; then
      while [ -z $UseDisk ]; do
        translate "These are the available devices"
        title="$Result"
        message_first_line "Which do you wish to use for this installation?"
        message_subsequent "   (Remember, this is auto-partition, and any data"
        translate "on the chosen device will be destroyed)"
        Message="${Message}\n      ${Result}\n"
        
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
    dialog --backtitle "$Backtitle" --title " $title " \
      --yes-label "$Yes" --no-label "$No" --yesno "\n$Message" 10 55 2>output.file
    if [ $? -eq 0 ]; then
      AutoPart="AUTO"
    else
      AutoPart="NONE"
    fi
  done
  return 0
}

function allocate_partitions { # Called by feliz.sh after check_parts
                               # Calls allocate_root, allocate_swap, no_swap_partition, more_partitions
  RootPartition=""
  while [ "$RootPartition" = "" ]; do
    allocate_root                       # User must select root partition
    if [ $? -ne 0 ]; then return 1; fi
  done
  if [ "${PartitionList}" = "" ]; then return 0; fi
                                        # All others are optional
  if [ -n "${PartitionList}" ]; then    # If there are unallocated partitions
    allocate_swap                       # Display display them for user to choose swap
  else                                  # If there is no partition for swap
    no_swap_partition                   # Inform user and allow swapfile
  fi
  if [ "${PartitionList}" = "" ]; then return 0; fi
  for i in ${PartitionList}; do         # Check contents of PartitionList
    echo $i > output.file               # If anything found, echo to file
    break                               # Break on first find
  done
  Result="$(cat output.file)"           # Check for output
  if [ "${Result}" != "" ]; then        # If any remaining partitions
    more_partitions                     # Allow user to allocate
  fi
  return 0
}

function select_filesystem { # Called by allocate_root and more_partitions (via choose_mountpoint)
                             # and guided_MBR and guided_EFI 
                             # Receives two arguments (window size)
  translate "Please select the file system for"
  title="$Result ${Partition}"
  message_first_line "It is not recommended to mix the btrfs file-system with others"
  menu_dialogVariable="ext4 ext3 btrfs xfs"
  
  menu_dialog $1 $2
  if [ $? -ne 0 ]; then return 1; fi
  PartitionType="$Result"
  return 0
}

function edit_label { # Called by allocate_root, allocate_swap & more_partitions
                      # If a partition has a label, allow user to change or keep it
  Label="${Labelled[$1]}"
  
  if [ -n "${Label}" ]; then
    translate "The partition you have chosen is labelled"
    local Message="$Result '${Label}'"
    translate "Keep that label"
    local Keep="$Result"
    translate "Delete the label"
    local Delete="$Result"
    translate "Enter a new label"
    local Edit="$Result"

    dialog --backtitle "$Backtitle" --title " $PassPart " \
      --ok-label "$Ok" --cancel-label "$Cancel" --menu "$Message" 24 50 3 \
      1 "$Keep" \
      2 "$Delete" \
      3 "$Edit" 2>output.file
    if [ $? -ne 0 ]; then return 1; fi
    Result="$(cat output.file)"  
    # Save to the -A array
    case $Result in
      1) Labelled[$PassPart]=$Label ;;
      2) Labelled[$PassPart]="" ;;
      3) Message="Enter a new label"
        dialog_inputbox 10 40
        if [ $retval -ne 0 ] || [ -z "$Result" ]; then return 1; fi
        Labelled[$PassPart]=$Result
    esac
  fi
  return 0
}

function allocate_root {  # Called by allocate_partitions
                          # Display partitions for user-selection of one as /root
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
  if [ $retval -ne 0 ]; then        # User selected <Cancel>
    PartitionType=""
    return 1
  fi
  
  PassPart=${Result:0:4}            # eg: sda4
  MountDevice=${PassPart:3:2}       # Save the device number for 'set x boot on'
  Partition="/dev/$Result"
  RootPartition="${Partition}"

  if [ $AutoPart = "MANUAL" ]; then # Not required for AUTO or GUIDED
                                    # Check if there is an existing filesystem on the selected partition
    check_filesystem                # This sets variable CurrentType and starts the Message
    Message="\n${Message}"
    if [ -n ${CurrentType} ]; then
      message_subsequent "You can choose to leave it as it is, but should"
      message_subsequent "understand that not reformatting the /root"
      message_subsequent "partition can have unexpected consequences"
    fi
    
    select_filesystem  18 75                               # This sets variable PartitionType
    if [ $? -ne 0 ]; then                                  # User has cancelled the operation
      PartitionType=""                                     # PartitionType can be empty (will not be formatted)
    else
      PartitionType="$Result"
    fi
    
    RootType="${PartitionType}" 
  
    if [ ${UEFI} -eq 0 ]; then                                    # Installing in BIOS environment
      parted_script "set ${MountDevice} boot on"                  # Make /root bootable
    fi
  fi
  
  Label="${Labelled[${PassPart}]}"
  if [ -n "${Label}" ]; then
    edit_label $PassPart
  fi

  PartitionList=$(echo "$PartitionList" | sed "s/$PassPart//")  # Remove the used partition from the list
  return 0
}

function check_filesystem { # Called by choose_mountpoint & allocate_root
                            # Finds if there is an existing file system on the selected partition
                            # Sets $CurrentType and prepares $Message
  CurrentType=$(blkid "$Partition" | sed -n -e 's/^.*TYPE=//p' | cut -d'"' -f2)

  if [ -n ${CurrentType} ]; then
    message_first_line "The selected partition"
    translate "is currently formatted to"
    Message="$Message $Result $CurrentType"
    message_subsequent "Reformatting it will remove all data currently on it"
  fi
  return 0
}

function allocate_swap { # Called by allocate_partitions
  message_first_line "Select a partition for swap from the ones that"
  message_subsequent "remain, or you can allocate a swap file"
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
    IsSwap=$(blkid $SwapPartition | grep 'swap' | cut -d':' -f1)
    if [ -n "$IsSwap" ]; then
      title="Swap"
      translate "is already formatted as a swap partition"
      Message="$SwapPartition $SwapPartition"
      message_subsequent "Reformatting it will change the UUID, and if this swap"
      message_subsequent "partition is used by another operating system, that"
      message_subsequent "system will no longer be able to access the partition"
      message_subsequent "Do you wish to reformat it?"
      MakeSwap="N"
      dialog --backtitle "$Backtitle" --title " $title " \
        --yes-label "$Yes" --no-label "$No" --yesno "\n$Message" 13 70 2>output.file
      case $? in
      0) FormatSwap="Y" ;;
      *FormatSwap="Y") FormatSwap="N"
      esac
    fi
    MakeSwap="Y"
    Label="${Labelled[${SwapPartition}]}"
    if [ "${Label}" ] && [ "${Label}" != "" ]; then
      edit_label "$PassPart"
    fi
  fi
  PartitionList="$SavePartitionList"                                        # Restore PartitionList without 'swapfile'
  if [ -z "$SwapPartition" ]; then
    translate "No provision has been made for swap"
    dialog --ok-label "$Ok" --msgbox "$Result" 6 30
  elif [ -n "$SwapPartition" ] && [ "$SwapPartition" != "swapfile" ]; then
    PartitionList=$(echo "$PartitionList" | sed "s/$Swap//")              # Remove the used partition from the list
  elif [ -n "$SwapFile" ]; then
    dialog --ok-label "$Ok" --msgbox "Swap file = ${SwapFile}" 5 20
  fi
  return 0
}

function no_swap_partition {  # Called by allocate_partitions when there are no unallocated partitions
  message_first_line "There are no partitions available for swap"
  message_subsequent "but you can allocate a swap file, if you wish"
  title="Create a swap file?"
  dialog --backtitle "$Backtitle" --title " $title " \
    --yes-label "$Yes" --no-label "$No"--yesno "\n$Message" 10 55 2>output.file
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
    message_first_line "Allocate the size of your swap file"
    message_subsequent "M = Megabytes, G = Gigabytes [eg: 512M or 2G]"
    dialog_inputbox 12 60
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
    choose_mountpoint   # Calls check_filesystem & select_filesystem, then dialog_inputbox to manually enter mountpoint
                        # Validates response, warns if already used, then adds the partition to
    retval=$?           # the arrays for extra partitions. Returns 0 if completed, 1 if interrupted

    if [ $retval -ne 0 ]; then return 1; fi # Inform calling function that user cancelled; no details added
    
    Label="${Labelled[${PassPart}]}"
    if [ -n "$Label" ]; then
      edit_label $PassPart
    fi

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
  declare -i formatPartition=0                    # Set to reformat

  check_filesystem                                # Check the partition for existing filesystem
  if [ -n "$CurrentType" ]; then
    PartitionType="$CurrentType"                  # Save current type in case retained
    message_subsequent "You can choose to leave it as it is, by selecting Exit, but not"
    message_subsequent "reformatting an existing partition can have unexpected consequences"
    Message="$Message \n"
    message_subsequent "Do you wish to reformat it?"
    dialog --backtitle "$Backtitle" --title " $title " \
      --yes-label "$Yes" --no-label "$No" --yesno "\n$Message" 15 70
    formatPartition=$?                            # 0 = Yes 1 = No
  fi

  if [ $formatPartition -eq 0 ]; then             # Reformat
    select_filesystem 12 50                       # Calls menu_dialog to display list of filesystems
                                                  # Sets $retval & $PartitionType
                                                  # Returns 0 if completed, 1 if interrupted
    if [ $? -ne 0 ]; then return 1; fi            # Inform calling function if no filesystem selected
  fi

  message_first_line "Enter a mountpoint for"
  Message="$Message ${Partition}\n(eg: /home) ... "
  
  dialog_inputbox 10 50                           # User manually enters a mountpoint; Sets $retval & $Result
                                                  # Returns 0 if completed, 1 if cancelled by user
  if [ $retval -ne 0 ]; then return 1; fi         # No mountpoint selected, so inform calling function
  Response=$(echo "$Result" | sed 's/ //')        # Remove any spaces
  CheckInput=${Response:0:1}                      # First character of user input
  if [ ${CheckInput} = "/" ]; then                # Ensure that entry includes '/'
    PartMount="${Response}"
  else
    PartMount="/${Response}"
  fi

  if [ ${#AddPartMount[@]} -gt 0 ]; then          # If there are existing (extra) mountpoints
    for MountPoint in ${AddPartMount}; do         # Go through AddPartMount
      if [ $MountPoint = $PartMount ]; then       # If the mountpoint has already been used
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
