#!/bin/bash

# The Feliz2 installation scripts for Arch Linux
# Developed by Elizabeth Mills
# Revision date: 12th August 2017

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
  T_COLS=$(tput cols)                   # Get width of terminal
  tput cup 0 $(((T_COLS/2)-20))         # Move the cursor to left of center
  printf "%-s\n" "$_Backtitle"          # Display backtitle
  printf "%$(tput cols)s\n"|tr ' ' '-'  # Draw a line across width of terminal
  cursor_row=3                          # Save cursor row after heading
}

PrintOne() {  # Receives up to 2 arguments. Translates and prints text
              # centred according to content and screen size
  if [ ! "$2" ]; then  # If $2 is missing or empty, translate $1
    Translate "$1"
    Text="$Result"
  else        # If $2 contains text, don't translate $1 or $2
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

PrintMany() { # Receives up to 2 arguments. Translates and prints text
              # aligned to first row according to content and screen size
  if [ ! "$2" ]; then  # If $2 is missing
    Translate "$1"
    Text="$Result"
  else        # If $2 contains text, don't translate $1 or $2
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
              InstalLanguage="en"
  ;;
  *) LanguageFile="${Result}.lan"
    case $LanguageFile in
    "Deutsche.lan") InstalLanguage="de"
    ;;
    "Español.lan") InstalLanguage="es"
    ;;
    "Français.lan") InstalLanguage="fr"
    ;;
    "Italiana.lan") InstalLanguage="it"
    ;;
    "Polski.lan") InstalLanguage="pl"
    ;;
    "Português.lan") InstalLanguage="pt"
    ;;
    *) InstalLanguage="en"
      LanguageFile=English.lan
    esac
  esac

  # Install the translator for situations where no translation is found on file
  if [ $LanguageFile != "English.lan" ]; then   # Only if not English
    PrintOne "Loading translator"
    wget -q git.io/trans
    chmod +x ./trans
  fi

  # Some common translations
  if [ -f "TESTING" ]; then
    Translate "Feliz2 - Testing"
  else
    Translate "Feliz2 - Arch Linux installation script"
  fi
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
  Translate "None"
  _None="$Result"
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

Translate() { # Called by PrintOne & PrintMany and by other functions as required
              # $1 is text to be translated
  Text="$1"
  if [ $LanguageFile = "English.lan" ]; then
    Result="$Text"
    return
  fi
  # Get line number of "$Text" in English.lan
  #                      exact match only | restrict to first find | display only number
  RecordNumber=$(grep -n "^${Text}$" English.lan | head -n 1 | cut -d':' -f1)
  case $RecordNumber in
  "" | 0) # No translation found, so translate using Google Translate to temporary file:
     ./trans -b en:${InstalLanguage} "$Text" > Result.file 2>/dev/null
     Result=$(cat Result.file)
  ;;
  *) Result="$(head -n ${RecordNumber} ${LanguageFile} | tail -n 1)" # Read item from target language file
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
UEFI=0                    # 0 = BIOS; 1 = EFI
EFIPartition=""           # eg: /dev/sda1
RootPartition=""          # eg: /dev/sda2
RootType=""               # eg: ext4
Partition=""              # eg: sda1
Ignorelist=""             # Used in review process
AutoPart=0                # Flag - changes to 1 if auto-partition is chosen
UseDisk="sda"             # Used if more than one disk
DiskDetails=0             # Size of selected disk
TypeList="ext4 ext3 btrfs xfs" # Partition format types

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
DesktopEnvironment=""     # eg: xfce or FelizOB
DisplayManager=""         # eg: lightdm

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
CategoriesList="Accessories Desktop_Environments Graphical Internet Multimedia Office Programming Window_Managers Taskbars"
Categories[1]="Accessories         "
Categories[2]="Desktop_Environments"
Categories[3]="Graphical"
Categories[4]="Internet"
Categories[5]="Multimedia"
Categories[6]="Office"
Categories[7]="Programming"
Categories[8]="Window_Managers"
Categories[9]="Taskbars"
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
Desktops="Budgie Cinnamon Gnome KDE LXDE LXQt Mate Xfce"
LongDesk[1]="Budgie is the default desktop of Solus OS"
LongDesk[2]="Slick, modern desktop from the Mint team"
LongDesk[3]="Full-featured, modern DE"
LongDesk[4]="Plasma 5 and accessories pack"
LongDesk[5]="Traditional, lightweight desktop"
LongDesk[6]="Lightweight and modern Qt-based DE"
LongDesk[7]="Traditional desktop from the Mint team"
LongDesk[8]="Lightweight, highly configurable DE"
# Graphical
Graphical="avidemux blender gimp handbrake imagemagick inkscape gthumb simple-scan xsane"
LongGraph[1]="Simple video editor             "
LongGraph[2]="3D graphics creation suite"
LongGraph[3]="Advanced image editing suite"
LongGraph[4]="Simple yet powerful video ripper"
LongGraph[5]="Command-line image manipulation"
LongGraph[6]="Vector graphics editor"
LongGraph[7]="Image viewer & basic editor"
LongGraph[8]="A simple scanner GUI"
LongGraph[9]="GTK-based sane frontend"
# Internet
Internet="chromium epiphany filezilla firefox midori qbittorrent thunderbird transmission-gtk"
LongNet[1]="Open source web browser from Google    "
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
LongOffice[1]="Full-featured word processor           "
LongOffice[2]="E-book library management application"
LongOffice[3]="Reader for PDF & other document formats"
LongOffice[4]="Spreadsheet program from GNOME"
LongOffice[5]="Open-source office software suite"
LongOffice[6]="Calendar & task manager"
LongOffice[7]="Desktop publishing program"
# Programming
Programming="bluefish codeblocks diffuse emacs geany git lazarus netbeans"
LongProg[1]="GTK+ IDE with support for Python plugins"
LongProg[2]="Open source & cross-platform C/C++ IDE"
LongProg[3]="Small and simple text merge tool"
LongProg[4]="Extensible, customizable text editor"
LongProg[5]="Advanced text editor & IDE"
LongProg[6]="Open source version control system"
LongProg[7]="Cross-platform IDE for Object Pascal"
LongProg[8]="Integrated development environment (IDE)"
# WindowManagers
WindowManagers="Awesome Enlightenment Fluxbox i3 IceWM Openbox Windowmaker Xmonad"
LongWMs[1]="Highly configurable, dynamic window manager              "
LongWMs[2]="Stacking window manager & libraries to manage desktop"
LongWMs[3]="Light, fast and versatile WM"
LongWMs[4]="Tiling window manager, completely written from scratch"
LongWMs[5]="Stacking window manager for the X Window System"
LongWMs[6]="Lightweight & configurable stacking WM"
LongWMs[7]="Window manager that emulates the NeXT user interface"
LongWMs[8]="Dynamic tiling window manager (requires Haskell compiler)"
# Taskbars (Docks & Panels)
Taskbars="cairo-dock docky dmenu fbpanel lxpanel plank tint2"
LongBars[1]="Customizable dock & launcher application                "
LongBars[2]="Full fledged dock application"
LongBars[3]="Fast and lightweight dynamic menu for X"
LongBars[4]="Lightweight, NETWM compliant desktop panel"
LongBars[5]="Lightweight X11 desktop panel (part of the LXDE desktop)"
LongBars[6]="Simple, clean dock from the Pantheon desktop environment"
LongBars[7]="Simple panel/taskbar developed specifically for Openbox"
