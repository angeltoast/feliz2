#!/bin/bash

# The Feliz installation scripts for Arch Linux
# Developed by Elizabeth Mills
# With grateful acknowlegements to Helmuthdu, Carl Duff and Dylan Schacht
# Revision date: 4th October 2017

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
EFIPartition=""   # "/dev/sda1"
UEFI_MOUNT=""    	# UEFI mountpoint
DualBoot="N"      # For formatting EFI partition

# In this module - functions for guided creation of a GPT or EFI partition table:
# -----------------------    ------------------------    -----------------------
# EFI Functions      Line    EFI Functions       Line    BIOS Functions     Line
# -----------------------    ------------------------    -----------------------
# TestUEFI            41     EasyRecalc          262     WipeDevice         601
#                            EasyBoot            278     GuidedMBR          608
# AllocateEFI         97     EasyRoot            309     GuidedRoot         652
# EasyEFI            136     EasySwap            354     GuidedSwap         701
# EasyDevice         178     EasyHome            422     GuidedHome         771
# EasyDiskSize       215     ActionEasyPart      469     ActionGuided       819
# -----------------------    ------------------------    -----------------------

TestUEFI() { # Called at launch of Feliz script, before all other actions
  tput setf 0             # Change foreground colour to black temporarily to hide error messages
  dmesg | grep -q "efi: EFI"           # Test for EFI (-q tells grep to be quiet)
  if [ $? -eq 0 ]; then                # check exit code; 0 = EFI, else BIOS
    UEFI=1                             # Set variable UEFI ON
    mount -t efivarfs efivarfs /sys/firmware/efi/efivars 2> feliz.log

# read -p "DEBUG f-part2 $LINENO"   # Basic debugging - copy and paste wherever a break is needed

  else
    UEFI=0                            # Set variable UEFI OFF
  fi
 tput sgr0                            # Reset colour
}

AllocateEFI() { # Called at start of AllocateRoot, before allocating root partition
  # Uses list of available partitions in PartitionList created in ManagePartitions
  print_heading
	Remaining=""
	local Counter=0
  Partition=""
	PartitionType=""
  Echo
	PrintOne "Here are the partitions that are available"
	PrintOne "First you should select one to use for EFI /boot"
	PrintOne "This must be of type vfat, and may be about 512MiB"
  Echo
  Translate "or Exit to try again"
  listgen2 "$PartitionList" "$Result" "$_Ok $_Exit" "PartitionArray"
  Reply=$Response               # This will be the number of the selected item in the list
                                # (not necessarily the partition number)
  if [ $Result != "$_Exit" ]; then  # But $Result is the identity (eg: /dev/sda1)
    PassPart=$Result
    SetLabel "$Result"
    UpdateArray                 # Remove the selected partition from $PartitionArray[]
  else                          # Exit selected
    CheckParts                  # Restart process
  fi

  Counter=0
  for i in ${PartitionList}
  do
    Counter=$((Counter+1))
    if [ $Counter -eq $Reply ]; then
			Partition="/dev/$i"
			EFIPartition="${Partition}"
		else
			Remaining="$Remaining $i"	# Add next available partition
		fi
	done

  PartitionList=$Remaining			# Replace original PartitionList with remaining options
  Parted "set 1 boot on"             # Make /root Bootable
}

EasyEFI() { # Main EFIfunction - Inform user of purpose, call each step
  EasyDevice              # Get details of device to use
  EasyDiskSize            # Get available space in MiB
  print_heading
  Echo
  PrintOne "Here you can set the size and format of the partitions"
  PrintOne "you wish to create. When ready, Feliz will wipe the disk"
  PrintOne "and create a new partition table with your settings"
  Echo
  Translate "We begin with the"
  PrintOne "$Result" "$_BootPartition"
  Echo
  EasyBoot                # Create /boot partition
  EasyRecalc "$BootSize"  # Recalculate remaining space
  EasyRoot                # Create /root partition
  EasyRecalc "$RootSize"  # Recalculate remaining space after adding /root
  if [ ${FreeSpace} -gt 0 ]; then
    EasySwap
  else
    Echo
    PrintOne "There is no space for a /swap partition, but you can"
    PrintOne "assign a swap-file. It is advised to allow some swap"
    PrintOne "Do you wish to allocate a swapfile?"
    Echo
    Buttons "Yes/No" "$_Yes $_No" "$_Instructions"
    Echo
    if [ $Response -eq 1 ]; then
      print_heading
      Echo
      SetSwapFile         # Note: Global variable SwapFile is set by SetSwapFile
                          # (SwapFile is created during installation by MountPartitions)
    fi
  fi
  if [ $SwapSize ]; then
    EasyRecalc "$SwapSize"  # Recalculate remaining space after adding /swap
  fi
  if [ ${FreeSpace} -gt 2 ]; then
    EasyHome
  fi
  ActionEasyPart          # Perform formatting and partitioning
}

EasyDevice() { # EFI - Get details of device to use from all connected devices
  DiskDetails=$(lsblk -l | grep 'disk' | cut -d' ' -f1)     # eg: sda
  UseDisk=$DiskDetails                                      # If more than one, $UseDisk will be first
  local Counter=0
  CountDisks=0
  for i in $DiskDetails   # Count lines in $DiskDetails
  do
    Counter=$((Counter+1))
    Drives[$Counter]=$i
  done
  if [ $Counter -gt 1 ]   # If there are multiple devices
  then                    # ask user which to use
    UseDisk=""            # Reset for user choice
    while [ -z $UseDisk ]
    do
      print_heading
      Translate "There are"
      _P1="$Result $Counter"
      Translate "devices available"
      PrintOne "$_P1" "$Result"
      PrintOne "Which do you wish to use for this installation?"
      Echo
      Counter=0
      for i in $DiskDetails
      do
        Counter=$((Counter+1))
        PrintOne "" "$Counter) $i"
      done
      Echo
      Translate "Please enter the number of your selection"
      TPread "${Result}: "
      UseDisk="${Drives[$Response]}"
    done
  fi
  GrubDevice="/dev/${UseDisk}"  # Full path of selected device
}

EasyDiskSize() { # EFI - Establish size of device in MiB
  DiskSize=$(lsblk -l | grep "${UseDisk}\ " | awk '{print $4}') # 1) Get disk size eg: 465.8G
  Unit=${DiskSize: -1}                                          # 2) Save last character (eg: G)
  # 3) Remove last character for calculations
  Chars=${#DiskSize}              # Count characters in variable
  Available=${DiskSize:0:Chars-1} # Separate the value from the unit
  # 4) Must be integer, so remove any decimal point and any character following
  Available=${Available%.*}
  if [ $Unit = "G" ]; then
    FreeSpace=$((Available*1024))
    Unit="M"
  elif [ $Unit = "T" ]; then
    FreeSpace=$((Available*1024*1024))
    Unit="M"
  else
    FreeSpace=$Available
  fi
  # 5) Warn user if space is limited
  if [ ${FreeSpace} -lt 2048 ]; then      # If less than 2GiB
    Translate "Your device has only"
    _P1="$Result ${FreeSpace}MiB:"
    Translate "This is not enough for an installation"
    PrintOne "$_P1" "$Result"
    PrintOne "Press any key"
    Translate "Exit"
    read -pn1 "$Result"
    exit
  elif [ ${FreeSpace} -lt 4096 ]; then    # If less than 4GiB
    Translate "Your device has only"
    _P1="$Result ${FreeSpace}MiB:"
    Translate "This is just enough for a basic"
    PrintOne "$_P1" "$Result"
    PrintOne "installation, but you should choose light applications only"
    PrintOne "and you may run out of space during installation or at some later time"
    Translate "Please press Enter to continue"
    TPread "${Result}"
  elif [ ${FreeSpace} -lt 8192 ]; then    # If less than 8GiB
    Translate "Your device has"
    _P1="$Result ${FreeSpace}MiB:"
    Translate "This is enough for"
    PrintOne "$_P1" "$Result"
    PrintOne "installation, but you should choose light applications only"
    Translate "Please press Enter to continue"
    TPread "${Result}"
  fi
}

EasyRecalc() {                          # EFI - Calculate remaining disk space
  local Passed=$1
  case ${Passed: -1} in
    "%") Calculator=$FreeSpace          # Allow for 100%
    ;;
    "G") Chars=${#Passed}               # Count characters in variable
        Passed=${Passed:0:Chars-1}      # Passed variable stripped of unit
        Calculator=$((Passed*1024))
    ;;
    *) Chars=${#Passed}                 # Count characters in variable
        Calculator=${Passed:0:Chars-1}  # Passed variable stripped of unit
  esac
  # Recalculate available space
  FreeSpace=$((FreeSpace-Calculator))
}

EasyBoot() { # EFI - Set variable: BootSize
  LoopRepeat="Y"
  while [ ${LoopRepeat} = "Y" ]
  do
    FreeGigs=$((FreeSpace/1024))
    Translate "You have"
    _P1="$Result ${FreeGigs}GiB"
    Translate "available on the chosen device"
    PrintOne "$_P1 " "$Result"
    PrintOne "All we need to set here is the size of your /boot partition"
    PrintOne "It should be no less than 512MiB and need be no larger than 1GiB"
    Echo
    Translate "Size"
    TPread "${Result} (M = Megabytes, G = Gigabytes) [eg: 512M or 1G]: "
    RESPONSE="${Response^^}"
    # Check that entry includes 'M or G'
    CheckInput=${RESPONSE: -1}
    Echo
    if [ ${CheckInput} != "M" ] && [ ${CheckInput} != "G" ] && [ ${CheckInput} != "M" ]; then
      print_heading
      PrintOne "You must include M, G or %"
      Echo
      BootSize=""
      continue
    else
      BootSize="${RESPONSE}"
      break
    fi
  done
}

EasyRoot() { # EFI - Set variables: RootSize, RootType
  LoopRepeat="Y"
  FreeGigs=$((FreeSpace/1024))
  while [ ${LoopRepeat} = "Y" ]
  do
    # Clear display, show /boot and available space
    print_heading
    PrintOne "$_BootPartition" ": ${BootSize}"
    Echo
    Translate "You now have"
    _P1="$Result ${FreeGigs}GiB"
    Translate "available on the chosen device"
    PrintOne "$_P1 " "$Result"
    Echo
    PrintOne "A partition is needed for /root"
    PrintOne "You can use all the remaining space on the device, if you wish"
    PrintOne "although you may want to leave room for a /swap partition"
    PrintOne "and perhaps also a /home partition"
    PrintOne "The /root partition should not be less than 8GiB"
    PrintOne "ideally more, up to 20GiB"
    AllocateAll
    Translate "Size"
    TPread "${Result} [eg: 12G or 100%]: "
    RESPONSE="${Response^^}"
    # Check that entry includes 'G or %'
    CheckInput=${RESPONSE: -1}
    Echo
    if [ ${CheckInput} != "%" ] && [ ${CheckInput} != "G" ] && [ ${CheckInput} != "M" ]; then
      PrintOne "You must include M, G or %"
      RootSize=""
      continue
    else
      RootSize=$RESPONSE
      Partition="/root"
      print_heading
      select_filesystem
      RootType=${PartitionType}
      break
    fi
  done
}

EasySwap() { # EFI - Set variable: SwapSize
  # Clear display, show /boot and /root
  LoopRepeat="Y"
  FreeGigs=$((FreeSpace/1024))
  while [ ${LoopRepeat} = "Y" ]
  do
    # Clear display, show /boot and available space
    print_heading
    PrintOne "$_BootPartition" ": ${BootSize}"
    PrintOne "$_RootPartition" ": ${RootType} : ${RootSize}"
    Echo
    Translate "You now have"
    _P1="$Result ${FreeGigs}GiB"
    Translate "available on the chosen device"
    PrintOne "$_P1 " "$Result"
    Echo
    if [ ${FreeSpace} -gt 10 ]; then
      Translate "There is space for a"
      PrintOne "$Result $_SwapPartition"
      PrintOne "Swap can be anything from 512MiB upwards but"
      PrintOne "it is not necessary to exceed 4GiB"
      PrintOne "You may want to leave room for a /home partition"
      Echo
    elif [ ${FreeSpace} -gt 5 ]; then
      Translate "There is space for a"
      PrintOne "$Result $_SwapPartition"
      PrintOne "Swap can be anything from 512MiB upwards but"
      PrintOne "it is not necessary to exceed 4GiB"
      PrintOne "You may want to leave room for a /home partition"
      Echo
    else
      Translate "There is just space for a"
      PrintOne "$Result $_SwapPartition"
      PrintOne "Swap can be anything from 512MiB upwards but"
      PrintOne "it is not necessary to exceed 4GiB"
      Echo
    fi
    AllocateAll
    Translate "Size"
    sleep 1               # To prevent keyboard bounce
    TPread "$Result [eg: 2G or 100% or 0]: "
    RESPONSE="${Response^^}"
    Echo
    case ${RESPONSE} in
      '' | 0) PrintOne "Do you wish to allocate a swapfile?"
        Buttons "Yes/No" "$_Yes $_No" "$_Instructions"
        Echo
        if [ $Response -eq 1 ]; then
          SetSwapFile
        fi
        break
      ;;
      *) # Check that entry includes 'G or %'
        CheckInput=${RESPONSE: -1}
        if [ ${CheckInput} != "%" ] && [ ${CheckInput} != "G" ] && [ ${CheckInput} != "M" ]; then
          PrintOne "You must include M, G or %"
          RootSize=""
          continue
        else
          SwapSize=$RESPONSE
          break
        fi
    esac
  done
  # If no space remains, offer swapfile, else create swap partition
}

EasyHome() { # EFI - Set variables: HomeSize, HomeType
  LoopRepeat="Y"
  FreeGigs=$((FreeSpace/1024))
  while [ ${LoopRepeat} = "Y" ]
  do
    # Clear display, show /boot and available space
    print_heading
    PrintOne "$_BootPartition" ": ${BootSize}"
    PrintOne "$_RootPartition :" " ${RootType} : ${RootSize}"
    PrintOne "$_SwapPartition :" " ${SwapSize}"
    Echo
    Translate "You now have"
    _P1="$Result ${FreeGigs}GiB"
    Translate "available on the chosen device"
    PrintOne "$_P1 " "$Result"
    Echo
    Translate "There is space for a"
    PrintOne "$Result $_HomePartition"
    PrintOne "You can use all the remaining space on the device, if you wish"
    Echo
    PrintOne "Please enter the desired size"
    Echo
    Translate "Size"
    TPread "$Result [eg: ${FreeGigs}G or 100% or 0]: "
    RESPONSE="${Response^^}"
    Echo
    case ${RESPONSE} in
      "" | 0) break
      ;;
      *) # Check that entry includes 'G or %'
          CheckInput=${RESPONSE: -1}
        if [ ${CheckInput} != "%" ] && [ ${CheckInput} != "G" ] && [ ${CheckInput} != "M" ]; then
          PrintOne "You must include M, G or %"
          HomeSize=""
          continue
        else
          HomeSize=$RESPONSE
          Partition="/home"
          print_heading
          select_filesystem
          HomeType=${PartitionType}
          break
        fi
    esac
  done
}

ActionEasyPart() { # EFI Final step. Uses the variables set above to create GPT partition table & all partitions
  while :
  do                                # Get user approval
    print_heading
    PrintOne "$_BootPartition:" "${BootSize}"
    PrintOne "$_RootPartition :" "${RootType} : ${RootSize}"
    PrintOne "$_SwapPartition :" "${SwapSize}"
    PrintOne "$_HomePartition :" "${HomeType} : ${HomeSize}"
    Echo
    PrintOne "That's all the preparation done"
    PrintOne "Feliz will now create a new partition table"
    PrintOne "and set up the partitions you have defined"
    Echo
    Translate "This will erase any data on"
    PrintOne "$Result " "${UseDisk}"
    PrintOne "Are you sure you wish to continue?"
    Echo
    Buttons "Yes/No" "$_Yes $_No" "$_Instructions"
    case $Response in
      "1" | "$_Yes") WipeDevice   # Format the drive
        Parted "mklabel gpt"        # Create EFI partition table
        break
       ;;
      "2" | "$_No") UseDisk=""
        CheckParts                  # Go right back to start
        ;;
        *) not_found
    esac
  done

# Boot partition
# --------------
  # Calculate end-point
  Unit=${BootSize: -1}                # Save last character of boot (eg: M)
  Chars=${#BootSize}                  # Count characters in boot variable
  Var=${BootSize:0:Chars-1}           # Remove unit character from boot variable
  if [ ${Unit} = "G" ]; then
    Var=$((Var*1024))                 # Convert to MiB
  fi
  EndPoint=$((Var+1))                 # Add start and finish. Result is MiBs, numerical only (has no unit)
  Parted "mkpart primary fat32 1MiB ${EndPoint}MiB"
  Parted "set 1 boot on"
  EFIPartition="${GrubDevice}1"       # "/dev/sda1"
  NextStart=${EndPoint}               # Save for next partition. Numerical only (has no unit)

# Root partition
# --------------
  # Calculate end-point
  Unit=${RootSize: -1}                # Save last character of root (eg: G)
  Chars=${#RootSize}                  # Count characters in root variable
  Var=${RootSize:0:Chars-1}           # Remove unit character from root variable
  if [ ${Unit} = "G" ]; then
    Var=$((Var*1024))                 # Convert to MiB
    EndPart=$((NextStart+Var))        # Add to previous end
    EndPoint="${EndPart}MiB"          # Add unit
  elif [ ${Unit} = "M" ]; then
    EndPart=$((NextStart+Var))        # Add to previous end
    EndPoint="${EndPart}MiB"          # Add unit
  elif [ ${Unit} = "%" ]; then
    EndPoint="${Var}%"
  fi
  # Make the partition
  Parted "mkpart primary ${RootType} ${NextStart}MiB ${EndPoint}"
  RootPartition="${GrubDevice}2"      # "/dev/sda2"
  NextStart=${EndPart}                # Save for next partition. Numerical only (has no unit)

# Swap partition
# --------------
  if [ $SwapSize ]; then
    # Calculate end-point
    Unit=${SwapSize: -1}              # Save last character of swap (eg: G)
    Chars=${#SwapSize}                # Count characters in swap variable
    Var=${SwapSize:0:Chars-1}         # Remove unit character from swap variable
    if [ ${Unit} = "G" ]; then
      Var=$((Var*1024))               # Convert to MiB
      EndPart=$((NextStart+Var))      # Add to previous end
      EndPoint="${EndPart}MiB"        # Add unit
    elif [ ${Unit} = "M" ]; then
      EndPart=$((NextStart+Var))      # Add to previous end
      EndPoint="${EndPart}MiB"        # Add unit
    elif [ ${Unit} = "%" ]; then
      EndPoint="${Var}%"
    fi
    # Make the partition
    Parted "mkpart primary linux-swap ${NextStart}MiB ${EndPoint}"
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
    if [ ${Unit} = "G" ]; then
      Var=$((Var*1024))               # Convert to MiB
      EndPart=$((NextStart+Var))      # Add to previous end
      EndPoint="${EndPart}MiB"        # Add unit
    elif [ ${Unit} = "M" ]; then
      EndPart=$((NextStart+Var))      # Add to previous end
      EndPoint="${EndPart}MiB"        # Add unit
    elif [ ${Unit} = "%" ]; then
      EndPoint="${Var}%"
    fi
    # Make the partition
    Parted "mkpart primary ${HomeType} ${NextStart}MiB ${EndPoint}"
    HomePartition="${GrubDevice}4"    # "/dev/sda4"
    Home="Y"
    AddPartList[0]="${GrubDevice}4"   # /dev/sda4     | add to
    AddPartMount[0]="/home"           # Mountpoint    | array of
    AddPartType[0]="ext4"             # Filesystem    | additional partitions
  fi
  ShowPart1="$_BootPartition : $(lsblk -l | grep "${UseDisk}1" | awk '{print $4, $1}')" >/dev/null
  ShowPart2="$_RootPartition : $(lsblk -l | grep "${UseDisk}2" | awk '{print $4, $1}')" >/dev/null
  ShowPart3="$_SwapPartition : $(lsblk -l | grep "${UseDisk}3" | awk '{print $4, $1}')" >/dev/null
  ShowPart4="$_HomePartition : $(lsblk -l | grep "${UseDisk}4" | awk '{print $4, $1}')" >/dev/null
  AutoPart=1                  # Treat as auto-partitioned. Set flag to 'on' for mounting
  print_heading
  PrintOne "Partitioning of" "${GrubDevice}" "successful"
  Echo
  PrintOne "" "$ShowPart1"
  PrintMany "" "$ShowPart2"
  PrintMany "" "$ShowPart3"
  PrintMany "" "$ShowPart4"
  Echo
  Translate "Press Enter to continue"
  Buttons "Yes/No" "$_Ok" "$Result"
}

WipeDevice() {                # Format the drive for EFI
  tput setf 0                 # Change foreground colour to black temporarily to hide error message
  sgdisk --zap-all /dev/sda   # Remove all partitions
  wipefs -a /dev/sda          # Remove filesystem
  tput sgr0                   # Reset colour
}

GuidedMBR() { # Main MBR function - Inform user of purpose, call each step
  EasyDevice                  # Get details of device to use
  EasyDiskSize                # Get available space in MiB
  print_heading
  Echo
  PrintOne "Here you can set the size and format of the partitions"
  PrintOne "you wish to create. When ready, Feliz will wipe the disk"
  PrintOne "and create a new partition table with your settings"
  PrintOne "This facility is restricted to creating /root, /swap and /home"
  Echo
  Translate "Are you sure you wish to continue?"
  Buttons "Yes/No" "$_Yes $_No" "$Result"
  if [ $Response -eq 2 ]; then
    CheckParts
  fi
  GuidedRoot                  # Create /root partition
  EasyRecalc "$RootSize"      # Recalculate remaining space after adding /root
  if [ ${FreeSpace} -gt 0 ]; then
    GuidedSwap
  else
    PrintOne "There is no space for a /swap partition, but you can"
    PrintOne "assign a swap-file. It is advised to allow some swap"
    Echo
    PrintOne "Do you wish to allocate a swapfile?"
    Echo
    Buttons "Yes/No" "$_Yes $_No" "$_Instructions"
    Echo
    if [ $Response -eq 1 ]; then
      print_heading
      Echo
      SetSwapFile # Note: Global variable SwapFile is set by SetSwapFile
                  # and SwapFile is created during installation by MountPartitions
    fi
  fi
  if [ $SwapSize ]; then
    EasyRecalc "$SwapSize"  # Recalculate remaining space after adding /swap
  fi
  if [ ${FreeSpace} -gt 2 ]; then
    GuidedHome
  fi
  # Perform formatting and partitioning
  ActionGuided
}

GuidedRoot() { # BIOS - Set variables: RootSize, RootType
  LoopRepeat="Y"
  FreeGigs=$((FreeSpace/1024))
  while [ ${LoopRepeat} = "Y" ]
  do
    # Clear display, show /boot and available space
    print_heading
    Translate "We begin with the"
    PrintOne "$Result" " $_RootPartition"
    Echo
    Translate "You have"
    _P1="$Result ${FreeGigs}GiB"
    Translate "available on the chosen device"
    PrintOne "$_P1" " $Result"
    Echo
    PrintOne "You can use all the remaining space on the device, if you wish"
    PrintOne "although you may want to leave room for a /swap partition"
    PrintOne "and perhaps also a /home partition"
    PrintOne "The /root partition should not be less than 8GiB"
    PrintOne "ideally more, up to 20GiB"
    AllocateAll
    Translate "Size"
    TPread "$Result [eg: 12G or 100%]: "
    RESPONSE="${Response^^}"
    # Check that entry includes 'G or %'
    CheckInput=${RESPONSE: -1}
    Echo
    if [ -z ${CheckInput} ]; then
      continue
    elif [ ${CheckInput} != "%" ] && [ ${CheckInput} != "G" ] && [ ${CheckInput} != "M" ]; then
      PrintOne "You must include M, G or %"
      RootSize=""
      continue
    else
      RootSize=$RESPONSE
      Partition="/root"
      print_heading
      Translate "allocated to /root"
      PrintOne "${RootSize}" "$Result"
      select_filesystem
      RootType=${PartitionType}
      break
    fi
  done
}

GuidedSwap() { # BIOS - Set variable: SwapSize
  # Clear display, show /boot and /root
  LoopRepeat="Y"
  FreeGigs=$((FreeSpace/1024))
  while [ ${LoopRepeat} = "Y" ]
  do
    # Clear display, show /root and available space
    print_heading
    PrintOne "$_RootPartition" ": ${RootType} : ${RootSize}"
    Echo
    Translate "You now have"
    _P1="$Result ${FreeGigs}GiB"
    Translate "available on the chosen device"
    PrintOne "$_P1" "$Result"
    Echo
    if [ ${FreeSpace} -gt 10 ]; then
      Translate "There is space for a"
      PrintOne "$Result" " $_SwapPartition"
      PrintOne "Swap can be anything from 512MiB upwards but"
      PrintOne "it is not necessary to exceed 4GiB"
      PrintOne "You may want to leave room for a /home partition"
    elif [ ${FreeSpace} -gt 5 ]; then
      Translate "There is space for a"
      PrintOne "$Result" " $_SwapPartition"
      PrintOne "Swap can be anything from 512MiB upwards but"
      PrintOne "it is not necessary to exceed 4GiB"
      PrintOne "You can use all the remaining space on the device, if you wish"
      PrintOne "You may want to leave room for a /home partition"
    else
      Translate "There is just space for a"
      PrintOne "$Result" " $_SwapPartition"
      PrintOne "Swap can be anything from 512MiB upwards but"
      PrintOne "it is not necessary to exceed 4GiB"
      PrintOne "You can use all the remaining space on the device, if you wish"
    fi
    AllocateAll
    Translate "Size"
    TPread "$Result [eg: 2G ... 100% ... 0]: "
    RESPONSE="${Response^^}"
    Echo
    case ${RESPONSE} in
      '' | 0) Echo
          PrintOne "Do you wish to allocate a swapfile?"
          Echo
        Buttons "Yes/No" "$_Yes $_No" "$_Instructions"
        Echo
        if [ $Response -eq 1 ]; then
          print_heading
          SetSwapFile
        fi
        break
      ;;
      *) # Check that entry includes 'G or %'
        CheckInput=${RESPONSE: -1}
        if [ ${CheckInput} != "%" ] && [ ${CheckInput} != "G" ] && [ ${CheckInput} != "M" ]; then
          PrintOne "You must include M, G or %"
          RootSize=""
          continue
        else
          SwapSize=$RESPONSE
          break
        fi
    esac
  done
  # If no space remains, offer swapfile, else create swap partition
}

GuidedHome() { # BIOS - Set variables: HomeSize, HomeType
  FreeGigs=$((FreeSpace/1024))
  while :
  do
    # Clear display, show /root, /swap and available space
    print_heading
    PrintOne "$_RootPartition" ": ${RootType} : ${RootSize}"
    PrintOne "$_SwapPartition" ": ${SwapSize}"
    Echo
    Translate "You now have"
    _P1="$Result ${FreeGigs}GiB"
    Translate "available on the chosen device"
    PrintOne "$_P1" "$Result"
    Echo
    Translate "There is space for a"
    PrintOne "$Result" "$_HomePartition"
    PrintOne "You can use all the remaining space on the device, if you wish"
    AllocateAll
    Translate "Size"
    TPread "${Result} [eg: 100% or 0]: "
    RESPONSE="${Response^^}"
    Echo
    case ${RESPONSE} in
      "" | 0) break
      ;;
      *) # Check that entry includes 'G or %'
          CheckInput=${RESPONSE: -1}
        if [ ${CheckInput} != "%" ] && [ ${CheckInput} != "G" ] && [ ${CheckInput} != "M" ]; then
          PrintOne "You must include M, G or %"
          HomeSize=""
          continue
        else
          HomeSize=$RESPONSE
          Partition="/home"
          print_heading
          Translate "of remaining space allocated to"
          PrintOne "${HomeSize}" "$Result $_HomePartition"
          select_filesystem
          HomeType=${PartitionType}
          break
        fi
    esac
  done
}

AllocateAll() {
  Echo
  PrintOne "Please enter the desired size"
  Translate "or, to allocate all the remaining space, enter"
  PrintOne "$Result: " "100%"
  Echo
}

ActionGuided() { # Final BIOS step - Uses the variables set above to create partition table & all partitions
  while :
  do
    # Get user approval
    print_heading
    if [ -n "${RootSize}" ]; then
      PrintOne "$_RootPartition " ": ${RootType} : ${RootSize}"
    fi
    if [ -n "${SwapSize}" ]; then
      PrintOne "$_SwapPartition " ": ${SwapSize}"
    elif [ -n "${SwapFile}" ]; then
      PrintOne "$_SwapFile " ": ${SwapFile}"
    fi
    if [ -n "${HomeSize}" ]; then
      PrintOne "$_HomePartition :" "${HomeType} : ${HomeSize}"
    fi
    Echo
    PrintOne "That's all the preparation done"
    PrintOne "Feliz will now create a new partition table"
    PrintOne "and set up the partitions you have defined"
    Echo
    Translate "This will erase any data on"
    PrintOne "$Result " "${UseDisk}"
    PrintOne "Are you sure you wish to continue?"
    Echo
    Buttons "Yes/No" "$_Yes $_No" "$_Instructions"
    case $Response in
      "1" | "Y" | "y") Parted "mklabel msdos"  # Create mbr partition table
        break
       ;;
      "2" | "N" | "n") UseDisk=""
        CheckParts                    # Go right back to start
        ;;
        *) not_found
    esac
  done

# Root partition
# --------------
  # Calculate end-point
  Unit=${RootSize: -1}                # Save last character of root (eg: G)
  Chars=${#RootSize}                  # Count characters in root variable
  Var=${RootSize:0:Chars-1}           # Remove unit character from root variable
  if [ ${Unit} = "G" ]; then
    Var=$((Var*1024))                 # Convert to MiB
    EndPart=$((1+Var))                # Start at 1MiB
    EndPoint="${EndPart}MiB"          # Append unit
  elif [ ${Unit} = "M" ]; then
    EndPart=$((1+Var))                # Start at 1MiB
    EndPoint="${EndPart}MiB"          # Append unit
  elif [ ${Unit} = "%" ]; then
    EndPoint="${Var}%"
  fi
  Parted "mkpart primary ext4 1MiB ${EndPoint}"
  Parted "set 1 boot on"
  RootPartition="${GrubDevice}1"      # "/dev/sda1"
  NextStart=${EndPart}                # Save for next partition. Numerical only (has no unit)

# Swap partition
# --------------
  if [ $SwapSize ]; then
    # Calculate end-point
    Unit=${SwapSize: -1}              # Save last character of swap (eg: G)
    Chars=${#SwapSize}                # Count characters in swap variable
    Var=${SwapSize:0:Chars-1}         # Remove unit character from swap variable
    if [ ${Unit} = "G" ]; then
      Var=$((Var*1024))               # Convert to MiB
      EndPart=$((NextStart+Var))      # Add to previous end
      EndPoint="${EndPart}MiB"        # Append unit
    elif [ ${Unit} = "M" ]; then
      EndPart=$((NextStart+Var))      # Add to previous end
      EndPoint="${EndPart}MiB"        # Append unit
    elif [ ${Unit} = "%" ]; then
      EndPoint="${Var}%"
    fi
    # Make the partition
    Parted "mkpart primary linux-swap ${NextStart}MiB ${EndPoint}"
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
    if [ ${Unit} = "G" ]; then
      Var=$((Var*1024))               # Convert to MiB
      EndPart=$((NextStart+Var))      # Add to previous end
      EndPoint="${EndPart}MiB"        # Append unit
    elif [ ${Unit} = "M" ]; then
      EndPart=$((NextStart+Var))      # Add to previous end
      EndPoint="${EndPart}MiB"        # Append unit
    elif [ ${Unit} = "%" ]; then
      EndPoint="${Var}%"
    fi
    # Make the partition
    Parted "mkpart primary ${HomeType} ${NextStart}MiB ${EndPoint}"
    HomePartition="${GrubDevice}3"    # "/dev/sda3"
    Home="Y"
    AddPartList[0]="${GrubDevice}3"   # /dev/sda3     | add to
    AddPartMount[0]="/home"           # Mountpoint    | array of
    AddPartType[0]="${HomeType}"      # Filesystem    | additional partitions
  fi
  AutoPart=1 # Treat as auto-partitioned. Set flag to 'on' for mounting
}
