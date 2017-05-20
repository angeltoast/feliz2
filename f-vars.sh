#!/bin/bash

# The Feliz2 installation scripts for Arch Linux
# Developed by Elizabeth Mills
# Revision date: 26th February 2017

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

# 1) Global functions

print_heading() {   # Always use this function to clear the screen
  tput sgr0         # Make sure colour inversion is reset
  clear
  local T_COLS=$(tput cols)             # Get width of terminal
  tput cup 0 $(((T_COLS/2)-20))         # Move the cursor to left of center
  printf "%-s\n" "$_Backtitle"           # Display backtitle
  printf "%$(tput cols)s\n"|tr ' ' '-'  # Draw a line across width of terminal
  cursor_row=3                          # Save cursor row after heading
}

PrintOne() {  # Receives up to 2 arguments
              # If $2 contains anything, don't translate $1
              # Prints text centred according to content and screen size
  if [ ! "$2" ]; then
    Translate "$1"
    Text="$Result"
  else
    Text="$1 $2"
  fi
  local width=$(tput cols)
  EMPTY=" "
  local stpt=0
  local lov=${#Text}
  if [ ${lov} -lt ${width} ]; then
    stpt=$(( (width - lov) / 2 ))
    EMPTY="$(printf '%*s' $stpt)"
  fi
  Echo "$EMPTY $Text"
}

PrintMany() { # Receives up to 2 arguments
              # If $2 contains anything, don't translate $1
              # Then print aligned according to content and screen size
  if [ ! "$2" ]; then
    Translate "$1"
    Text="$Result"
  else
    Text="$1 $2"
  fi
  Echo "$EMPTY $Text"
}

read_timed() { # Timed display - $1 = text to display; $2 = duration
  local T_COLS=$(tput cols)
  local lov=${#1}
  local stpt=0
  if [ $2 ]; then
    tim=$2
  else
    tim=2
  fi
  if [ ${lov} -lt ${T_COLS} ]; then
    stpt=$(( (T_COLS - lov) / 2 ))
    EMPTY="$(printf '%*s' $stpt)"
  else
    EMPTY=""
  fi
  read -t ${tim} -p "$EMPTY $1"
  cursor_row=$((cursor_row+1))
}

SetLanguage() {
  _Backtitle="Feliz2 - Arch Linux installation script"
  print_heading
  PrintOne "" "Idioma/Język/Language/Langue/Limba/Língua/Sprache"
  Echo
  listgen1 "$(ls *.lan | cut -d'.' -f1)" "" "Ok"
  case $Result in
  "" | "Exit") LanguageFile=English.lan
  ;;
  *) LanguageFile="${Result}.lan"
  esac
  # Some common translations
  Translate "Feliz2 - Arch Linux installation script"
  _Backtitle="$Result"
  # listgen1/2 variables
  Translate "Ok"
  _Ok="$Result"
  Translate "Exit"
  _Exit="$Result"
  Translate "Exit to finish"
  _Quit="$Result"
  Translate "Use arrow keys to move. Enter to select"
  _Instructions="${Result}"
  Translate "Yes"
  _Yes="$Result"
  Translate "No"
  _No="$Result"
  Translate "or"
  _or="$Result"
  # listgenx variables
  Translate "Please enter the number of your selection"
  _xNumber="$Result"
  Translate "or ' ' to exit"
  _xExit="$Result"
  Translate "'<' for previous page"
  _xLeft="$Result"
  Translate "'>' for next page"
  _xRight="$Result"
  # Partitioning
  Translate "/boot partition"
  _BootPartition="$Result"
    Translate "/root partition"
  _RootPartition="$Result"
    Translate "/swap partition"
  _SwapPartition="$Result"
    Translate "/home partition"
  _HomePartition="$Result"
}

Translate() { # Called by ReadOne & ReadMany and by other functions as required
              # $1 is text to be translated
  Text="$1"
  # Get line number of text in English.lan
  #                      exact match only | restrict to first find | display only number
  RecordNumber=$(grep -n "^${Text}$" English.lan | head -n 1 | cut -d':' -f1)
  case $RecordNumber in
  "" | 0) Result="$Text"  # If not found, use English
  ;;
  *) Result="$(head -n ${RecordNumber} ${LanguageFile} | tail -n 1)" # Read item from target file
  esac
}

# 2) Declaration of variables and arrays

# Partition variables and arrays
declare -a AddPartList    # Array of additional partitions eg: /dev/sda5
declare -a AddPartMount   # Array of mountpoints for the same partitions eg: /home
declare -a AddPartType    # Array of format type for the same partitions eg: ext4
declare -a PartitionArray # Array of long identifiers
declare -a NewArray       # For copying any array

declare -a button_start   # Used in listgen
declare -a button_text    # Used in listgen
declare -a button_len     # Used in listgen

declare -A LabellingArray # Associative array of user labels for partitions
declare -A Labelled       # Associative array of labelled partitions
declare -A FileSystem     # Associative array of filesystem types (ext* swap)
BootSize=""               # Boot variable for EasyEFI
RootSize=""               # Root variable for EasyEFI
SwapSize=""               # Swap variable for EasyEFI
HomeSize=""               # Home variable for EasyEFI
HomeType=""               # Home variable for EasyEFI
SwapPartition=""          # eg: /dev/sda3
FormatSwap="N"            # User selects whether to reuse swap
MakeSwap="Y"
SwapFile=""               # eg: 2G
IsSwap=""                 # Result of lsblk test
RootPartition=""          # eg: /dev/sda2
RootType=""               # eg: ext4
Partition=""              # eg: sda1
AutoPart=0                # Flag - changes to 1 if auto-partition is chosen
UseDisk="sda"             # Used if more than one disk
DiskDetails=0             # Size of selected disk
TypeList="ext3 ext4 btrfs xfs" # Partition format types

# Grub & kernel variables
GrubDevice=""             # eg: /dev/sda
Kernel="1"                # Default 1 = LTS
IsInVbox="N"              # Result of test to see if installation is in Virtualbox
OSprober="Y"

# Location variables
CountryCode=""            # eg: GB ... for mirrorlist
CountryLocale=""          # eg: en_GB.UTF-8
Countrykbd=""             # eg: uk
ZONE=""                   # eg: Europe For time
SUBZONE=""                # eg: London
LanguageFile="English.lan" # For translation
RecordNumber=0            # Used during translation

# Desktop environment, display manager and greeter variables
DesktopEnvironment=""     # eg: xfce
DisplayManager=""         # eg: lightdm
Greeter=""                # eg: lightdm-gtk-greeter (Not required for some DMs)

# Root and user variables
HostName=""               # eg: arch-linux
UserName=""               # eg: archie
Scope=""                  # Installation scope ... 'Full' or 'Basic'

# Miscellaneous
PrimaryFile=""

# ---- Partitioning ----
PartitioningOptions="cfdisk guided auto leave"
LongPart[1]="Open cfdisk so I can partition manually"
LongPart[2]="Guided manual partitioning tool"
LongPart[3]="Allow feliz to partition the whole device"
LongPart[4]="Choose from existing partitions"
# EFI
EFIPartitioningOptions="guided auto leave"
LongPartE[1]="Guided manual partitioning tool"
LongPartE[2]="Allow feliz to partition the whole device"
LongPartE[3]="Choose from existing partitions"

# ---- Arrays for extra Applications ----
CategoriesList="Accessories Desktop_Environments Graphical Internet Multimedia Office Programming Window_Managers"
Categories[1]="Accessories         "
Categories[2]="Desktop_Environments"
Categories[3]="Graphical"
Categories[4]="Internet"
Categories[5]="Multimedia"
Categories[6]="Office"
Categories[7]="Programming"
Categories[8]="Window_Managers"
# Accessories
Accessories="brasero conky galculator gparted hardinfo leafpad lxterminal pcmanfm"
LongAccs[1]="Disc burning application from Gnome            "
LongAccs[2]="Desktop time and system information"
LongAccs[3]="Handy desktop calculator"
LongAccs[4]="Tool to make/delete/resize partitions"
LongAccs[5]="Displays information about your hardware and OS"
LongAccs[6]="Handy lightweight text editor from LXDE"
LongAccs[7]="Lightweight terminal emulator from LXDE"
LongAccs[8]="The file manager from LXDE"
# Desktops
Desktops="Budgie Cinnamon Deepin Gnome KDE LXDE LXQt Mate MateGTK3 Xfce"
LongDesk[1]="Modern desktop focusing on simplicity & elegance"
LongDesk[2]="Slick DE from the Mint team"
LongDesk[3]="The Deepin Desktop Environment"
LongDesk[4]="Full-featured, modern DE"
LongDesk[5]="Plasma 5 and accessories pack"
LongDesk[6]="Traditional, lightweight DE"
LongDesk[7]="Lightweight and modern Qt DE"
LongDesk[8]="Traditional DE from the Mint team"
LongDesk[9]="GTK3 version of the Mate DE"
LongDesk[10]="Lightweight, highly configurable DE"
# Graphical
Graphical="avidemux blender gimp handbrake imagemagick inkscape gthumb simple-scan xsane"
LongGraph[1]="Video editor for simple cutting, filtering and encoding"
LongGraph[2]="fully integrated 3D graphics creation suite"
LongGraph[3]="Advanced image editing suite"
LongGraph[4]="Simple yet powerful video ripper"
LongGraph[5]="Command-line image manipulation"
LongGraph[6]="Vector graphics editor comparable to CorelDraw"
LongGraph[7]="Image viewer & basic editor"
LongGraph[8]="A simple scanner GUI"
LongGraph[9]="Full-featured GTK-based sane frontend"
# Internet
Internet="chromium epiphany filezilla firefox midori qbittorrent thunderbird transmission-gtk"
LongNet[1]="Open source web browser from Google     "
LongNet[2]="Gnome WebKitGTK+ browser (aka Web)"
LongNet[3]="Fast & reliable FTP, FTPS & SFTP client"
LongNet[4]="Extensible browser from Mozilla"
LongNet[5]="Light web browser"
LongNet[6]="Open source BitTorrent client"
LongNet[7]="Feature-rich email client from Mozilla"
LongNet[8]="Easy-to-use BitTorrent client"
# Multimedia
Multimedia="avidemux-gtk banshee handbrake openshot vlc xfburn"
LongMulti[1]="Easy-to-use video editor            "
LongMulti[2]="Feature-rich audio player"
LongMulti[3]="Simple yet powerful video transcoder"
LongMulti[4]="Easy-to-use non-linear video editor"
LongMulti[5]="Middleweight video player"
LongMulti[6]="GUI CD burner"
# Office
Office="abiword calibre evince gnumeric libreoffice orage scribus"
LongOffice[1]="Full-featured word processor            "
LongOffice[2]="E-book library management application"
LongOffice[3]="Reader for PDF & other document formats"
LongOffice[4]="Spreadsheet program from GNOME"
LongOffice[5]="Open-source office software suite"
LongOffice[6]="Calendar & task manager (incl with Xfce)"
LongOffice[7]="Desktop publishing program"
# Programming
Programming="bluefish codeblocks diffuse emacs geany git lazarus netbeans"
LongProg[1]="GTK+ IDE with support for Python plugins      "
LongProg[2]="Open source & cross-platform C/C++ IDE"
LongProg[3]="Small and simple text merge tool"
LongProg[4]="Extensible, customizable text editor"
LongProg[5]="Advanced text editor & IDE"
LongProg[6]="Open source distributed version control system"
LongProg[7]="Cross-platform IDE for Object Pascal"
LongProg[8]="Integrated development environment (IDE)"
# WindowManagers
WindowManagers="Enlightenment Fluxbox Openbox FelizOB cairo-dock docky fbpanel tint2"
LongWMs[1]="Window manager and toolkit                       "
LongWMs[2]="Light, fast and versatile WM"
LongWMs[3]="Lightweight, powerful & configurable stacking WM"
LongWMs[4]="Feliz customized Openbox with basic desktop tools"
LongWMs[5]="Customizable dock & launcher application"
LongWMs[6]="For opening applications & managing windows"
LongWMs[7]="Desktop panel"
LongWMs[8]="Desktop panel"
