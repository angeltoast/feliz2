#!/bin/bash

# The Feliz2 installation scripts for Arch Linux
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
#                 The Free Software Foundation, Inc.
#                  51 Franklin Street, Fifth Floor
#                    Boston, MA 02110-1301 USA

# In this module: Some global functions, and declaration of various arrays and variables
# --------------------   ----------------------
# Function        Line   Function          Line
# --------------------   ----------------------
# not_found         33   read_timed         109
# Echo              39   CompareLength      128
# TPread            44   PaddLength         136
# print_heading     62   SetLanguage        145
# PrintOne          74   Translate          226
# PrintMany         96   Arrays & Variables 247
# --------------------   ----------------------

# read -p "DEBUG: ${BASH_SOURCE[0]}/${FUNCNAME[0]}/${LINENO} called from ${BASH_SOURCE[1]}/${FUNCNAME[1]}/${BASH_LINENO[0]}"

not_found() {
  Echo
  PrintOne "Please try again"
  Buttons "Yes/No" "$_Ok"
}

Echo() { # Use in place of 'echo' for basic text print
  printf "%-s\n" "$1"
  cursor_row=$((cursor_row+1))
}

TPread() { # Aligned prompt for user-entry
  # $1 = prompt ... Returns result through $Response
  local T_COLS=$(tput cols)
  local lov=${#1}
  local stpt=0
  if [ ${lov} -lt ${T_COLS} ]; then
    stpt=$(( (T_COLS - lov) / 2 ))
  elif [ ${lov} -gt ${T_COLS} ]; then
    stpt=0
  else
    stpt=$(( (T_COLS - 10) / 2 ))
  fi
  EMPTY="$(printf '%*s' $stpt)"
  read -p "$EMPTY $1" Response
  cursor_row=$((cursor_row+1))
}

print_heading() {   # Always use this function to clear the screen
  tput sgr0         # Make sure colour inversion is reset
  clear
  T_COLS=$(tput cols)                   # Get width of terminal
  LenBT=${#_Backtitle}
  HalfBT=$((LenBT/2))
  tput cup 0 $(((T_COLS/2)-HalfBT))     # Move the cursor to left of center
  printf "%-s\n" "$_Backtitle"          # Display backtitle
  printf "%$(tput cols)s\n"|tr ' ' '-'  # Draw a line across width of terminal
  cursor_row=3                          # Save cursor row after heading
}

PrintOne() {  # Receives up to 2 arguments. Translates and prints text
              # centred according to content and screen size
  if [ ! "$2" ]; then  # If $2 is missing or empty, translate $1
    Translate "$1"
    Text="$Result"
  elif [ $Translate = "N" ]; then  # If Translate variable unset, don't translate any
    Text="$1 $2 $3"
  else                             # If $2 contains text, don't translate any
    Text="$1 $2 $3"
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
  elif [ $Translate = "N" ]; then  # If Translate variable unset, don't translate any
    Text="$1 $2 $3"
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

CompareLength() {
  # If length of translation is greater than previous, save it
  Text="$1"
    if [ ${#Text} -gt $MaxLen ]; then
      MaxLen=${#Text}
    fi
}

PaddLength() {  # If $1 is shorter than MaxLen, padd with spaces
  Text="$1"
  until [ ${#Text} -eq $MaxLen ]
  do
    Text="$Text "
  done
  Result="$Text"
}

SetLanguage() {
  _Backtitle="Feliz2 - Arch Linux installation script"
  print_heading
  setfont LatGrkCyr-8x16 -m 8859-2                         # To display wide range of characters
  PrintOne "" "Idioma/Język/Language/Langue/Limba/Língua/Sprache"
  Echo
  listgen1 "English Deutsche Ελληνικά Español Français Italiano Nederlands Polski Português-PT Português-BR" "" "Ok"  # Available languages
  case $Response in
    2) InstalLanguage="de"
      LanguageFile="German.lan"
    ;;
    3) InstalLanguage="el"
      LanguageFile="Greek.lan"
    ;;
    4) InstalLanguage="es"
      LanguageFile="Spanish.lan"
    ;;
    5) InstalLanguage="fr"
      LanguageFile="French.lan"
    ;;
    6) InstalLanguage="it"
      LanguageFile="Italian.lan"
    ;;
    7) InstalLanguage="nl"
      LanguageFile="Dutch.lan"
    ;;
    8) InstalLanguage="pl"
      LanguageFile="Polish.lan"
    ;;
    9) InstalLanguage="pt-PT"
      LanguageFile="Portuguese-PT.lan"
    ;;
    10) InstalLanguage="pt-BR"
      LanguageFile="Portuguese-BR.lan"
    ;;
    *) InstalLanguage="en"
      LanguageFile="English.lan"
  esac

  # Get the required language files
  # PrintOne "Loading translator"
  tput setf 0             # Change foreground colour to black temporarily to hide error message
  wget https://raw.githubusercontent.com/angeltoast/feliz-language-files/master/English.lan 2>> feliz.log
  if [ $LanguageFile != "English.lan" ]; then   # Only if not English
    wget https://raw.githubusercontent.com/angeltoast/feliz-language-files/master/${LanguageFile} 2>> feliz.log
    # Install the translator for situations where no translation is found on file
    # wget -q git.io/trans 2>> feliz.log
    # chmod +x ./trans
    tput sgr0               # Reset colour
  fi

  # Some common translations
  if [ -f "TESTING" ]; then
    Translate "Feliz - Testing"
  else
    Translate "Feliz - Arch Linux installation script"
  fi
  _Backtitle="$Result"
  Translate "Loading"
  _Loading="$Result"
  Translate "Installing"
  _Installing="$Result"
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
  Text="${1%% }"   # Ensure no trailing spaces
  if [ $LanguageFile = "English.lan" ] || [ $Translate = "N" ]; then
    Result="$Text"
    return
  fi
  # Get line number of "$Text" in English.lan
  #                      exact match only | restrict to first find | display only number
  RecordNumber=$(grep -n "^${Text}$" English.lan | head -n 1 | cut -d':' -f1)
  case $RecordNumber in
  "" | 0) # No match found in English.lan, so translate using Google Translate to temporary file:
    # ./trans -b en:${InstalLanguage} "$Text" > Result.file 2>/dev/null
    # Result=$(cat Result.file)
      Result="$Text"
  ;;
  *) Result="$(head -n ${RecordNumber} ${LanguageFile} | tail -n 1)" # Read item from target language file
  esac
}

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
declare -a CountryLong    # Array of selected countries to be added to mirrorlist

# Desktop environment, display manager and greeter variables
DesktopEnvironment=""     # eg: xfce or FelizOB
DisplayManager=""         # eg: lightdm

# Root and user variables
HostName=""               # eg: arch-linux
UserName=""               # eg: archie
Scope=""                  # Installation scope ... 'Full' or 'Basic'

# Miscellaneous
declare -a BeenThere      # Restrict translations to first pass
PrimaryFile=""
Translate="Y"             # May be set to N to stifle translation

# ---- Partitioning ----
PartitioningOptions="leave cfdisk guided auto"
LongPart[1]="Choose from existing partitions"
LongPart[2]="Open cfdisk so I can partition manually"
LongPart[3]="Guided manual partitioning tool"
LongPart[4]="Allow feliz to partition the whole device"
# EFI
EFIPartitioningOptions="leave guided auto"
LongPartE[1]="Choose from existing partitions"
LongPartE[2]="Guided manual partitioning tool"
LongPartE[3]="Allow feliz to partition the whole device"

# ---- Arrays for extra Applications ----
CategoriesList="Accessories Desktop_Environments Graphical Internet Multimedia Office Programming Window_Managers Taskbars"
Categories[1]="Accessories"
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
LongAccs[1]="Disc burning application from Gnome"
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
Graphical="blender gimp imagemagick inkscape gthumb simple-scan xsane"
LongGraph[1]="3D graphics creation suite"
LongGraph[2]="Advanced image editing suite"
LongGraph[3]="Command-line image manipulation"
LongGraph[4]="Vector graphics editor"
LongGraph[5]="Image viewer & basic editor"
LongGraph[6]="A simple scanner GUI"
LongGraph[7]="GTK-based sane frontend"
# Internet
Internet="chromium epiphany filezilla firefox midori qbittorrent thunderbird transmission-gtk"
LongNet[1]="Open source web browser from Google"
LongNet[2]="Gnome WebKitGTK+ browser (aka Web)"
LongNet[3]="Fast & reliable FTP, FTPS & SFTP client"
LongNet[4]="Extensible browser from Mozilla"
LongNet[5]="Light web browser"
LongNet[6]="Open source BitTorrent client"
LongNet[7]="Feature-rich email client from Mozilla"
LongNet[8]="Easy-to-use BitTorrent client"
# Multimedia
Multimedia="avidemux-gtk banshee handbrake openshot vlc xfburn"
LongMulti[1]="Easy-to-use video editor"
LongMulti[2]="Feature-rich audio player"
LongMulti[3]="Simple yet powerful video transcoder"
LongMulti[4]="Easy-to-use non-linear video editor"
LongMulti[5]="Middleweight video player"
LongMulti[6]="GUI CD burner"
# Office
Office="abiword calibre evince gnumeric libreoffice orage scribus"
LongOffice[1]="Full-featured word processor"
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
WindowManagers="Awesome Enlightenment Fluxbox i3 IceWM JWM Openbox Windowmaker Xmonad"
LongWMs[1]="Highly configurable, dynamic window manager"
LongWMs[2]="Stacking window manager & libraries to manage desktop"
LongWMs[3]="Light, fast and versatile WM"
LongWMs[4]="Tiling window manager, completely written from scratch"
LongWMs[5]="Stacking window manager for the X Window System"
LongWMs[6]="Joe's Window Manager - featherweight window manager"
LongWMs[7]="Lightweight & configurable stacking WM"
LongWMs[8]="Window manager that emulates the NeXT user interface"
LongWMs[9]="Dynamic tiling window manager (requires Haskell compiler)"
# Taskbars (Docks & Panels)
Taskbars="cairo-dock docky dmenu fbpanel lxpanel plank tint2"
LongBars[1]="Customizable dock & launcher application"
LongBars[2]="Fully fledged dock application"
LongBars[3]="Fast and lightweight dynamic menu for X"
LongBars[4]="Lightweight, NETWM compliant desktop panel"
LongBars[5]="Lightweight X11 desktop panel (part of the LXDE desktop)"
LongBars[6]="Simple, clean dock from the Pantheon desktop environment"
LongBars[7]="Simple panel/taskbar developed specifically for Openbox"
