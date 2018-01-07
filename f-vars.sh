#!/bin/bash

# The Feliz2 installation scripts for Arch Linux
# Developed by Elizabeth Mills  liz@feliz.one
# With grateful acknowlegements to Helmuthdu, Carl Duff and Dylan Schacht
# Revision date: 29th December 2017

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
# ----------------------    ------------------------
# Function          Line    Function            Line
# ----------------------    ------------------------
# set_language        38    print_subsequent     127
# not_found           97    common_translations  197
# dialog_inputbox    107    translate            246
# message_first_line 127    
# message_subsequent 148    Arrays & Variables   266
# print_first_line   127       ... and onwards
# ----------------------    ------------------------

function set_language
{
  setfont LatGrkCyr-8x16 -m 8859-2    # To display wide range of characters
  
  # First load English file
  if [ ! -f English.lan ]; then
    wget https://raw.githubusercontent.com/angeltoast/feliz-language-files/master/English.lan 2>> feliz.log
  fi
  
  dialog --backtitle "$Backtitle" \
    --title " Idioma/Język/Language/Langue/Limba/Língua/Sprache " --no-tags --menu \
    "\n       You can use the UP/DOWN arrow keys, or\n \
    the first letter of your choice as a hot key.\n \
           Please choose your language" 21 60 11 \
      en "English" \
      de "Deutsche" \
      el "Ελληνικά" \
      es "Español" \
      fr "Français" \
      it "Italiano" \
      nl "Nederlands" \
      pl "Polski" \
      pt-BR "Português" \
      vi "Vietnamese" 2>output.file
    retval=$?
    if [ $retval -ne 0 ]; then exit; fi
    InstalLanguage=$(cat output.file)

  case "$InstalLanguage" in
    de) LanguageFile="German.lan"
    ;;
    el) setfont LatGrkCyr-8x16 -m 8859-2
      LanguageFile="Greek.lan"
    ;;
    es) LanguageFile="Spanish.lan"
    ;;
    fr) LanguageFile="French.lan"
    ;;
    it) LanguageFile="Italian.lan"
    ;;
    nl) LanguageFile="Dutch.lan"
    ;;
    pl) LanguageFile="Polish.lan"
    ;;
    pt-PT) LanguageFile="Portuguese-PT.lan"
    ;;
    pt-BR) LanguageFile="Portuguese-BR.lan"
    ;;
    vi) LanguageFile="Vietnamese.lan"
      setfont viscii10-8x16 -m 8859-2
    ;;
    *) LanguageFile="English.lan"
      InstalLanguage="en"
  esac
  
  # Get the required language files
  if [ $LanguageFile != "English.lan" ]; then   # If English is not the user language, get the translation file
    if [ ! -f ${LanguageFile} ]; then
      wget https://raw.githubusercontent.com/angeltoast/feliz-language-files/master/${LanguageFile} 2>> feliz.log
    fi

    if [ ! -f trans ]; then               # If Google translate hasn't already been installed, get it
      wget -q git.io/trans 2>> feliz.log  # (for situations where no translation is found in language files)
      chmod +x ./trans
    fi
  fi

  translate "Back"
  Back="$Result"
  translate "Cancel"
  Cancel="$Result"
  translate "Done"
  Done="$Result"
  translate "Exit"
  Exit="$Result"
  translate "No"
  No="$Result"
  translate "Ok"
  Ok="$Result"
  translate "Yes"
  Yes="$Result"
}

function not_found                # Optional arguments $1 & $2 for box size
{
  if [ $1 ] && [ -n $1 ]; then
    Height="$1"
  else
    Height=7
  fi
  if [ $2 ] && [ -n $2 ]; then
    Length="$2"
  else
    Length=25
  fi
  dialog --backtitle "$Backtitle" --title " Not Found " --ok-label "$Ok" --msgbox "\n$Message $3" $Height $Length
}

function dialog_inputbox          # General-purpose input box ... $1 & $2 are box size
{
  dialog --backtitle "$Backtitle" --title " $title " --ok-label "$Ok" \
    --inputbox "\n$Message\n" $1 $2 2>output.file
  retval=$?
  Result=$(cat output.file)
}

function message_first_line       # translates $1 and starts a Message with it
{
  translate "$1"
  Message="$Result"
}

function message_subsequent       # translates $1 and continues a Message with it
{
  translate "$1"
  Message="${Message}\n${Result}"
}

function print_first_line         # Called by FinalCheck to display all user-defined variables
{                                 # Prints argument(s) centred according to content and screen size
  text="$1 $2 $3"
  local width=$(tput cols)
  EMPTY=" "
  stpt=0
  local lov=${#text}
  if [ ${lov} -lt ${width} ]; then
    stpt=$(( (width - lov) / 2 ))
    EMPTY="$(printf '%*s' $stpt)"
  fi
  echo "$EMPTY $text"
}

function print_subsequent() # Called by FinalCheck to display all user-defined variables
{ # Prints argument(s) aligned to print_first_line according to content and screen size
  text="$1 $2 $3"
  echo "$EMPTY $text"
}

function translate()  # Called by message_first_line & message_subsequent and by other functions as required
{                     # $1 is text to be translated
  text="${1%% }"      # Remove any trailing spaces
  if [ $LanguageFile = "English.lan" ] || [ $translate = "N" ]; then
    Result="$text"
    return 0
  fi
  # Get line number of "$text" in English.lan
  #                      exact match only | restrict to first find | display only number
  RecordNumber=$(grep -n "^${text}$" English.lan | head -n 1 | cut -d':' -f1)
  case ${RecordNumber} in
  "" | 0) # No match found in English.lan, so use Google translate
     ./trans -b en:${InstalLanguage} "$text" > output.file 2>/dev/null
     Result=$(cat output.file)
  ;;
  *) Result="$(head -n ${RecordNumber} ${LanguageFile} | tail -n 1)" # Read item from target language file
  esac
}

# Partition variables and arrays
declare -a AddPartList    # Array of additional partitions eg: /dev/sda5
declare -a AddPartMount   # Array of mountpoints for the same partitions eg: /home
declare -a AddPartType    # Array of format type for the same partitions eg: ext4
declare -A PartitionArray # Associative array of partition details
declare -a NewArray       # For copying any array
declare -A Labelled       # Associative array of labelled partitions
BootSize=""               # Boot variable
RootSize=""               # Root variable
SwapSize=""               # Swap variable
HomeSize=""               # Home variable
HomeType=""               # Home variable
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
AutoPart="NONE"           # Flag - MANUAL/AUTO/GUIDED/NONE
UseDisk="sda"             # Used if more than one disk
DiskDetails=0             # Size of selected disk

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
user_name=""              # eg: archie
Scope=""                  # Installation scope ... 'Full' or 'Basic'

# Miscellaneous
declare -a BeenThere      # Restrict translations to first pass
PrimaryFile=""
translate="Y"             # May be set to N to stifle translation

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
Office="abiword calibre evince gnumeric libreoffice-fresh orage scribus"
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
