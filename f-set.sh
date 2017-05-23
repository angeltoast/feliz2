#!/bin/bash

# The Feliz2 installation scripts for Arch Linux
# Developed by Elizabeth Mills
# Revision date: 23rd May 2017

# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation - either version 2 of the License, or
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

# In this module: functions for setting variables used during installation
# --------------------   ------------------------
# Function        Line   Function            Line
# --------------------   ------------------------
# not_found         44    Username             558
# Echo              50    SetHostname          574
# TPread            55    Options              591
# SetKernel         72    PickLuxuries         614
# ConfirmVbox       84    KeepOrDelete         654
# SetTimeZone      108    ShoppingList         686
# SetSubZone       140    ChooseDM             846
# SelectSubzone    169    SetGrubDevice        907
# America          189      --- Review stage ---
# FindCity         224    FinalCheck           931
# DoCities         276    ManualSettings      1001
# setlocale        302    ChangeRootPartition 1030
# AllLanguages     447    ChangeSwapPartition 1038
# getkeymap        464    ChangePartitions    1046
# SearchKeyboards  522    AddExtras           1058
# --------------------    -----------------------

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

SetKernel() {
  print_heading
  Echo
  PrintOne "Choose your kernel"
  PrintOne "The Long-Term-Support kernel (LTS) offers stabilty"
  PrintOne "while the Latest kernel has all the new features"
  PrintOne "If in doubt, choose LTS"
  Echo
  listgen1 "LTS Latest" "" "$_Ok"
  Kernel=${Response} # Set the Kernel variable (1 = LTS; 2 = Latest)
}

ConfirmVbox() {
  while :
  do
    print_heading
    PrintOne "It appears that feliz is running in Virtualbox"
    PrintOne "If it is, feliz can install Virtualbox guest"
    PrintOne "utilities and make appropriate settings for you"
    Echo
    PrintOne "Install Virtualbox guest utilities?"
    Echo
    Buttons "Yes/No" "$_Yes $_No" ""
    Echo
    case $Response in
      1) IsInVbox="VirtualBox"
      ;;
      "") not_found
        continue
      ;;
      *) IsInVbox=""
    esac
    return 0
  done
}

SetTimeZone() {
  SUBZONE=""
  until [ $SUBZONE ]
  do
    print_heading
    PrintOne "To set the system clock, please first"
    PrintOne "choose the World Zone of your location"
    Zones=$(timedatectl list-timezones | cut -d'/' -f1 | uniq) # Ten world zones
    Echo
    zones=""
    for x in ${Zones}                      # Convert to space-separated list
    do
      Translate "$x"                          # Translate
      zones="$zones $Result"
    done
    listgen1 "${zones}" "" "$_Ok"         # Allow user to select one
    # Because the list is translated, we need to get the system version of the selected item
    ZONE=$(echo "$Zones" | head -n $Response | tail -n 1)
    Echo
    case $Result in
      "") continue
      ;;
      *) SetSubZone                           # Call subzone function
        case $Result in                       # If user quits
        "$_Exit" | "") SUBZONE=
        ;;
        *) SUBZONE="$Result"
        esac
    esac
  done
}

SetSubZone() {  # Use ZONE set in SetTimeZone to list available subzones
  SubZones=$(timedatectl list-timezones | grep ${ZONE}/ | sed 's/^.*\///')
  Ocean=0
  SUBZONE=""
  while [ -z $SUBZONE ]
  do
    case $ZONE in
    "Antarctica") SelectSubzone
    ;;
    "Arctic") SUBZONE="Longyearbyen"
    ;;
    "Atlantic") Ocean=1
      SelectSubzone
    ;;
    "Australia") SelectSubzone
    ;;
    "Indian") Ocean=1
      SelectSubzone
    ;;
    "Pacific") Ocean=1
      SelectSubzone
    ;;
    "America") America
     ;;
    *)  SelectSubzone
    esac
  done
}

SelectSubzone() {
  print_heading
  Translate "Now we need to find your location in"
  _P1="$Result"
  Translate "Please enter the first letter of"
  _P2="$Result"
  case $Ocean in
  1) Translate "the island or group where you are located"
    _P3="$Result"
    ;;
  *) Translate "your nearest major city"
    _P3="$Result"
  esac
  PrintOne "$_P1" "$ZONE"
  PrintOne "" "$_P2"
  PrintOne "" "$_P3"
  Echo
  FindCity
}

America() {
  SUBZONE=""      # Make sure this variable is empty
  print_heading
  PrintOne "Are you in any of these states?"
  SubList=""      # Start an empty list
  Previous=""     # Prepare to save previous record
  local Toggle="First"
  for i in $(timedatectl list-timezones | grep "$ZONE/" | awk 'BEGIN { FS = "/"; OFS = "/" } {print $2}')
  do
    if [ $Previous ] && [ $i = $Previous ] && [ $Toggle = "First" ]; then # First reccurance
      SubList="$SubList $i"
      Toggle="Second"
    elif [ $Previous ] && [ $i != $Previous ] && [ $Toggle = "Second" ]; then # 1st occ after prev group
      Toggle="First"
      Previous=$i
    else                                                                  # Subsequent occurances
      Previous=$i
    fi
  done
  SubGroup=""
  Translate "None_of_these"
  _None="$Result"
  SubList="$SubList $_None"        # Add a decline option
  listgen1 "$SubList" "" "$_Ok"
  case $Result in
  "$_None") SelectSubzone          # No subgroup, call general city function
  ;;
  "$_Exit") SetTimeZone
  ;;
  *) SubGroup=$Result                     # Save subgroup for next function
    ZONE="${ZONE}/$SubGroup"              # Add subgroup to ZONE
    DoCities                              # City function for subgroups
  esac
}

FindCity() {  # Called by SelectSubzone
  Translate "enter ' ' to see a list"
  TPread "$_or $Result: "
  Echo
  if [ -z ${Response} ]               # User has entered ' '
  then
    # Prepare file to use listgenx
    timedatectl list-timezones | grep ${ZONE}/ | cut -d'/' -f2 > temp.file
    Translate "Please choose your nearest location"
    listgenx "$Result" "$_xNumber" "$_xExit" "$_xLeft" "$_xRight"
    if [ $Result = "$_Exit" ] || [ $Result = "" ]; then
      SetTimeZone
    fi
    SUBZONE="$Result" 
    return
  else
    Response="${Response:0:1}"        # In case user enters more than one letter
    Zone2="${Response^^}"             # Convert the first letter to upper case
  fi
  subzones=""
  local Rows=$(tput lines)            # Used to allow for longer (numbered) lists
  Rows=$((Rows-6))                    # Available (printable) rows
  local Counter=0
  for x in ${SubZones[@]}             # Search long list of subzones that match ZONE
  do                                  # to find those that start with user's letter
    if [ ${x:0:1} = ${Zone2} ]; then  # If first character in subzone matches ...
      subzones="$subzones $x"         # Save to list
      Counter=$((Counter+1))
    fi
  done
  if [ ${Counter} -eq 0 ]; then       # None found
    not_found
    return
  fi
  if [ $Counter -ge $Rows ]; then
    echo "$subzones" > temp.file
    Translate "Please choose your nearest location"
    listgenx "$Result" "" ""
  else
    print_heading
    PrintOne "Please choose your nearest location"
    PrintOne "Choose one or Exit to search for alternatives"
    listgen1 "$subzones" "" "$_Ok $_Exit"
  fi
  case $Result in
    "$_Exit") SUBZONE=""
    ;;
    *) SUBZONE=$Result
  esac
}

DoCities() { # Specifically for America, which has subgroups
  print_heading
  Cities=""
  case $SubGroup in
  "") # No subgroup selected. Here we are working on the second field - cities without a subgroup
      for i in $(timedatectl list-timezones | grep "$ZONE/" | awk 'BEGIN { FS = "/"; OFS = "/" } {print $2}')
      do
        Cities="$Cities $i"
      done
  ;;
  *) # Here we are working on the third field - cities within the chosen subgroup
      for i in $(timedatectl list-timezones | grep "$ZONE/" | awk 'BEGIN { FS = "/"; OFS = "/" } {print $3}')
      do
        Cities="$Cities $i"
      done
  esac
  PrintOne "Please select a city from this list"
  Translate "or Exit to try again"
  listgen1 "$Cities" "$Result" "$_Ok $_Exit"
  case $Result in
  "$_Exit") SetTimeZone
  ;;
  *) SUBZONE=$Result
  esac
}

setlocale() { # Uses country-code in cities.list to match ZONE/SUBZONE to country-code,
                        # ... and hence to the list of languages generated from /etc/locale.gen
  ZoneID="${ZONE}/${SUBZONE}"         # Use a copy of zones set in SetTimeZone (eg: Europe/London)
  CountryLocale=""
  while [ -z "$CountryLocale" ]
  do
    # Find in cities.list (field $2 is the country code, eg: GB)
    SEARCHTERM=$(grep "$ZoneID" cities.list | cut -d':' -f2)
    SEARCHTERM=${SEARCHTERM// }            # Ensure no leading spaces
    SEARCHTERM=${SEARCHTERM%% }            # Ensure no trailing spaces
    print_heading
    # Find all matching entries in locale.gen - This will be a table of locales in the form: en_GB
    LocaleList=$(grep "#" /etc/locale.gen | grep ${SEARCHTERM}.UTF-8 | cut -d'.' -f1 | cut -d'#' -f2)
    HowMany=$(echo $LocaleList | wc -w)   # Count them
    Rows=$(tput lines)                    # to ensure menu doesn't over-run
    Rows=$((Rows-4))                      # Available (printable) rows
    case $HowMany in                      # Offer language options for the selected country
    0) print_heading
      Echo                                # If none found, offer main languages
      PrintOne "No language has been found for your location"
      PrintOne "Would you like to use one of the following?"
      Translate "Choose one or Exit to search for alternatives"
      listgen1 "English French Spanish" "$Result" "$_Ok $_Exit"
      case $Response in
      1) Item="en"
      ;;
      2) Item="fr"
      ;;
      3) Item="es"
      ;;
      *) City=""
        AllLanguages
        if [ -z "$Result" ] || [ $Result = "$_Exit" ]; then
          SetTimeZone
        else
          Item=$(grep "${Language}:" languages.list)
          Item=${Item: -2:2}                      # Last two characters
          CountryLocale="${Item}_${SEARCHTERM}.UTF-8"
          CountryCode=${CountryLocale:3:2}        # 2 characters from position 3
        fi
      esac
      CountryLocale="${Item}_${SEARCHTERM}.UTF-8"
      CountryCode=${CountryLocale:3:2}            # 2 characters from position 3
    ;;
    1) Item=$(echo $LocaleList | cut -d'_' -f1)     # First field of the record in locale.gen (eg: en)
      Language="$(grep :$Item languages.list | cut -d':' -f1)"  # Find long name eg: English
      if [ -z "$Language" ]; then                               # If not found in languages.list
        Language=$Item                                          # Use the abbreviation
      fi
      Echo
      Translate "Only one language found for your location"
      PrintOne "$Result" ": $Language"
      PrintOne "Shall we use this as your language?"    # Allow user to confirm
      Buttons "Yes/No" "$_Yes $_No" ""
      if [ $Result = "$N" ]; then                       # User declines offered language
        City=""
        AllLanguages                                    # Call function to display all languages
        if [ $Result = "$_Exit" ] || [ $Result = "" ]; then
          SetTimeZone
        else
          Item=$(grep "${Language}:" languages.list)    # eg: Abkhazian:ab
          Item=${Item: -2:2}                            # Last 2 characters
          CountryLocale="${Item}_${SEARCHTERM}.UTF-8"   # Set locale
          CountryCode=${CountryLocale:3:2}              # Extract 2 characters from position 3 (eg: GB)
        fi
      else                                              # User accepts offered language
        Item=$(grep "${Language}:" languages.list)      # eg: Abkhazian:ab
        Item=${Item: -2:2}                              # Last 2 characters
        CountryLocale="${Item}_${SEARCHTERM}.UTF-8"     # Set locale
        CountryCode=${CountryLocale:3:2}                # Extract 2 characters from position 3 (eg: GB)
      fi
    ;;
    *) # Check the short code for each language against long names in language.list
      if [ $HowMany -ge $Rows ]; then                 # Too many to display in menu, so use listgenx
        # Make a shortlist of relevant language codes
        ShortList=$(grep ${SEARCHTERM}.UTF-8 /etc/locale.gen | cut -d'_' -f1| uniq)
        for l in ${ShortList}
        do
          grep "$l$" languages.list >> temp.file        # listgenx checks temp.file then renames it
        done
        Translate "Now please choose your language from this list"
        listgenx "$Result" "$_xNumber" "$_xExit" "$_xLeft" "$_xRight"
      else                                              # List is short enough for listgen1
        local Counter=0
        localelist=""
        for l in ${LocaleList[@]}                       # Convert to space-separated list
        do
          localelist="${localelist} $l"                 # Add each item to text list for handling
          Counter=$((Counter+1))
        done
        if [ $Counter -eq 0 ]; then                     # If none found, try again
          not_found
          SetTimeZone
        fi
        Counted=$(echo $localelist | wc -w)             # Count number of words in $localelist
        Newlist=""                                      # Prepare to make list of language names from codes
        for (( i=1; i <= Counted; ++i ))
        do                                              # For each item in localelist (eg: en_GB)
          loc=$(echo $localelist | cut -d' ' -f$i)      # Save the $i-th item from localelist
          Newlist="$Newlist ${loc:0:2}"                 # Add first two characters (language code) to list
        done
        # If more than one language found
        localelist="${Newlist}"                         # Save the list to continue
        Newlist=""                                      # Prepare new empty list
        Prev="xyz"                                      # Arbitrary comparison
        for l in $localelist                            # Remove any duplicates
        do
          if [ $l != $Prev ]; then
            Newlist="$Newlist $l"
            Prev=$l
          fi
        done
        localelist="${Newlist}"                               # Copy to working variable
        choosefrom=""
        Newlist=""                                            # Empty new list again
        for l in ${localelist}
        do                                                    # Find the language in languages.list
          Item="$(grep $l\$ languages.list | cut -d':' -f1)"  # First field eg: English
          if [ $Item ]; then                                  # If found
            choosefrom="$choosefrom $Item"                    # Add to list of languages for user
            Newlist="$Newlist $l"                             # ... and a matching list of codes
          fi
        done
        localelist="${Newlist}"                         # Ensure that localelist matches choosefrom
        print_heading
        PrintOne "Now please choose your language from this list"
        Translate "Choose one or Exit to search for alternatives"
        listgen1 "${choosefrom}" "$Result" "$_Ok $_Exit"       # Menu if less than one screenful
      fi
      case $Result in
      "$_Exit" | "") SetTimeZone
      ;;
      *) Language=$(grep $Result languages.list)        # Lookup the result in languages file
        if [ -n "$Language" ]; then
          loc=${Language: -2:2}                         # Just the last two characters
          CountryLocale="${loc}_${SEARCHTERM}.UTF-8"
          CountryCode=${CountryLocale:3:2}              # 2 characters from position 3
        else
          SetTimeZone
        fi
      esac
    esac
  done
}

AllLanguages() {
  while :
  do
    print_heading
    Echo
    cat languages.list > temp.file         # Prepare file for listgenx to display all languages
    Translate "Now please choose your language from this list"
    listgenx "$Result" "$_xNumber" "$_xExit" "$_xLeft" "$_xRight"
    if [ $Result = "" ] || [ $Result = "$_Exit" ]; then
      SetTimeZone                                   # Start again from time zone
    else
      Result="${Result: -2:2}"                      # Pass short code back to caller
      break
    fi
  done
}

getkeymap() {
  Countrykbd=""
  country="${CountryLocale,,}"
  case ${country:3:2} in
  "gb") Term="uk"
  ;;
  *) Term="${country:3:2}"
  esac
  ListKbs=$(grep ${Term} keymaps.list)
  Found=$(grep -c ${Term} keymaps.list)  # Count records
  if [ ! $Found ]; then
    Found=0
  fi
  while [ -z "$Countrykbd" ]
  do
    print_heading
    Echo
    case $Found in
    0)  # If the search found no matches
      Translate "Sorry, no keyboards found based on your location"
      read_timed "$Result" 2
      SearchKeyboards
    ;;
    1)  # If the search found one match
      PrintOne "Only one keyboard found based on your location"
      PrintOne "Do you wish to accept this? Select No to search for alternatives"
      Buttons "Yes/No" "$_Yes $_No" "$_Instructions"
      case ${Result} in
      "$_No") SearchKeyboards
      ;;
      *) Countrykbd="${Result}"
      esac
      loadkeys ${Countrykbd} 2>> feliz.log
    ;;
    *) # If the search found multiple matches, check to ensure menu doesn't over-run
      Rows=$(tput lines)
      Rows=$((Rows-7))    # Available (printable) rows
      if [ $Found -ge $Rows ]; then
        for i in $ListKbs
        do
          echo $i >> temp.file
        done
        Translate "Choose one, or ' ' to search for alternatives"
        listgenx "$Result" "$_xNumber" "$_xExit" "$_xLeft" "$_xRight"
      else
        PrintOne "Select your keyboard, or Exit to try again"
        listgen1 "$ListKbs" "" "$_Ok $_Exit"
      fi
      case ${Result} in
      "$_Exit"|"") SearchKeyboards
      ;;
      *) Countrykbd="${Result}"
      esac
      loadkeys ${Countrykbd} 2>> feliz.log
    esac
  done
}

SearchKeyboards() {
  while [ -z "$Countrykbd" ]
  do
    print_heading
    PrintOne "If you know the code for your keyboard layout, please enter"
    PrintOne "it now. If not, try entering a two-letter abbreviation"
    PrintOne "for your country or language and a list will be displayed"
    PrintOne "Alternatively, enter ' ' to start again"
    Echo
    TPread "(eg: 'dvorak' or 'us'): "
    local Term="${Response,,}"
    if [ $Term = "exit" ]; then
      SetTimeZone
    fi
    Echo
    ListKbs=$(grep ${Term} keymaps.list)
    if [ -n "${ListKbs}" ]; then  # If a match or matches found
      print_heading
      PrintOne "Select your keyboard, or Exit to try again"
      listgen1 "$ListKbs" "" "$_Ok $_Exit"
      if [ "${Result}" = "$_Exit" ]; then
        continue
      else
        Countrykbd="${Result}"
      fi
      loadkeys ${Countrykbd} 2>> feliz.log
    else
      print_heading
      Echo
      Translate "No keyboards found containing"
      PrintOne "$Result" "'$Term'"
      not_found
    fi
  done
}

UserName() {
  print_heading
  PrintOne "Enter a name for the primary user of the new system"
  PrintOne "If you don't create a username here, a default user"
  PrintOne "called 'archie' will be set up"
  Echo
  Translate "User Name"
  TPread "${Result}: "
  Entered=${Response,,}
  case $Entered in
    "") UserName="archie"
    ;;
    *) UserName=${Entered}
  esac
}

SetHostname() {
  Entered="arch-linux"
  print_heading
  PrintOne "A hostname is needed. This will be a unique name to identify"
  PrintOne "your device on a network. If you do not enter one, the"
  PrintOne "default hostname of 'arch-linux' will be used"
  Echo
  Translate "Enter a hostname for your computer"
  TPread "${Result}: "
  Entered=${Response,,}
  case $Entered in
    "") HostName="arch-linux"
    ;;
    *) HostName=${Entered}
  esac
}

Options() { # Added 22 May 2017 - User chooses between FelizOB and self-build
  print_heading
  PrintOne "Feliz now offers you a choice. You can either ..."
  Echo
  PrintOne "Build your own system, by picking the"
  PrintOne " software you wish to install"
  PrintOne "... or ..."
  PrintOne "You can simply choose the new FelizOB desktop, a"
  PrintOne " complete lightweight system built on Openbox"
  Echo
  listgen1 "Build_My_Own FelizOB_desktop" "" "$_Ok"
  case $Response in
    1) PickLuxuries
    ;;
    2) LuxuriesList="FelizOB"
      DesktopEnvironment="FelizOB"
      Scope="Full"
      fob="Y"
    ;;
    *) Options
  esac
}

PickLuxuries() { # User selects any combination from a store of extras
  CategoriesList=""
  Translate "Added so far"
  AddedSoFar="$Result"
  for category in Accessories Desktop_Environments Graphical Internet Multimedia Office Programming Window_Managers
  do
    Translate "$category"
    CategoriesList="$CategoriesList $Result"
  done
  print_heading
  case "$LuxuriesList" in
  '') PrintOne "Now you have the option to add extras, such as a web browser"
    PrintOne "desktop environment, etc, from the following categories"
    PrintOne "If you want only a base Arch installation"
    PrintOne "exit without choosing any extras"
  ;;
  *) PrintOne "You can add more items, or select items to delete"
  esac
  Echo
  while :
  do
    listgen1 "${CategoriesList}" "$_Quit" "$_Ok $_Exit"
    Category=$Response
    if [ $Result = "$_Exit" ]; then
      break
    else
      ShoppingList
      print_heading
      PrintOne "$AddedSoFar" ": ${LuxuriesList}"
      PrintOne "You can now choose from any of the other lists"
      PrintOne "or choose Exit to finish this part of the setup"
    fi
  done
  if [ -n "${LuxuriesList}" ]; then
    Scope="Full"
  else
    Scope="Basic"
  fi
}

KeepOrDelete() {
  Bagged="$1"
  while :
  do
    print_heading
    Translate "is already in your shopping list"
    Message="$Bagged $Result"
    Translate "Keep"
    K="$Result"
    Translate "Delete"
    D="$Result"
    Buttons "Yes/No" "$K $D" "$Message"
    case $Response in
      1) Temp="$LuxuriesList"
        break
      ;;
      2) Validated="Y"
        Temp=""
        for lux in $LuxuriesList
        do
          if [ ${lux} != ${Bagged} ]; then
            Temp="$Temp $lux"
          fi
        done
        break
      ;;
      *) not_found
    esac
  done
  LuxuriesList="$Temp"
}

ShoppingList() { # Called by PickLuxuries after a category has been chosen.
  Translate "Choose an item"
  while :
  do
    print_heading
    PrintOne "$AddedSoFar" ": ${LuxuriesList}"
    Echo
    PrintOne "${Categories[$Category]}" # $Category is number of item in CategoriesList
    # Pass category to listgen2 for user to choose one item;
    local Counter=1
    case $Category in
       1) OptionsCounter=1
          for Option in "${LongAccs[@]}"  # Translate all elements
          do
            Translate "$Option"
            LongAccs[${OptionsCounter}]="$Result"
            (( OptionsCounter+=1 ))
          done
        for i in ${Accessories}
        do
          LongAccs1[${Counter}]="$i - ${LongAccs[${Counter}]}"
          (( Counter+=1 ))
        done
        listgen2 "$Accessories" "$_Quit" "$_Ok $_Exit" "LongAccs1"
       ;;
       2) OptionsCounter=1
          for Option in "${LongDesk[@]}"  # Translate all elements
          do
            Translate "$Option"
            LongDesk[${OptionsCounter}]="$Result"
            (( OptionsCounter+=1 ))
          done
        for i in ${Desktops}
        do
          LongDesk1[${Counter}]="$i - ${LongDesk[${Counter}]}"
          (( Counter+=1 ))
        done
        listgen2 "$Desktops" "$_Quit" "$_Ok $_Exit" "LongDesk1"
       ;;
       3) OptionsCounter=1
          for Option in "${LongGraph[@]}"  # Translate all elements
          do
            Translate "$Option"
            LongGraph[${OptionsCounter}]="$Result"
            (( OptionsCounter+=1 ))
          done
        for i in ${Graphical}
        do
          LongGraph1[${Counter}]="$i - ${LongGraph[${Counter}]}"
          (( Counter+=1 ))
        done
        listgen2 "$Graphical" "$_Quit" "$_Ok $_Exit" "LongGraph1"
       ;;
       4) OptionsCounter=1
          for Option in "${LongNet[@]}"  # Translate all elements
          do
            Translate "$Option"
            LongNet[${OptionsCounter}]="$Result"
            (( OptionsCounter+=1 ))
          done
        for i in ${Internet}
        do
          LongNet1[${Counter}]="$i - ${LongNet[${Counter}]}"
          (( Counter+=1 ))
        done
        listgen2 "$Internet" "$_Quit" "$_Ok $_Exit" "LongNet1"
       ;;
       5) OptionsCounter=1
          for Option in "${LongMulti[@]}"  # Translate all elements
          do
            Translate "$Option"
            LongMulti[${OptionsCounter}]="$Result"
            (( OptionsCounter+=1 ))
          done
        for i in ${Multimedia}
        do
          LongMulti1[${Counter}]="$i - ${LongMulti[${Counter}]}"
          (( Counter+=1 ))
        done
        listgen2 "$Multimedia" "$_Quit" "$_Ok $_Exit" "LongMulti1"
       ;;
       6) OptionsCounter=1
          for Option in "${LongOffice[@]}"  # Translate all elements
          do
            Translate "$Option"
            LongOffice[${OptionsCounter}]="$Result"
            (( OptionsCounter+=1 ))
          done
        for i in ${Office}
        do
          LongOffice1[${Counter}]="$i - ${LongOffice[${Counter}]}"
          (( Counter+=1 ))
        done
        listgen2 "$Office" "$_Quit" "$_Ok $_Exit" "LongOffice1"
       ;;
       7) OptionsCounter=1
          for Option in "${LongProg[@]}"  # Translate all elements
          do
            Translate "$Option"
            LongProg[${OptionsCounter}]="$Result"
            (( OptionsCounter+=1 ))
          done
        for i in ${Programming}
        do
          LongProg1[${Counter}]="$i - ${LongProg[${Counter}]}"
          (( Counter+=1 ))
        done
        listgen2 "$Programming" "$_Quit" "$_Ok $_Exit" "LongProg1"
       ;;
       8) OptionsCounter=1
          for Option in "${LongWMs[@]}"  # Translate all elements
          do
            Translate "$Option"
            LongWMs[${OptionsCounter}]="$Result"
            (( OptionsCounter+=1 ))
          done
        for i in ${WindowManagers}
        do
          LongWMs1[${Counter}]="$i - ${LongWMs[${Counter}]}"
          (( Counter+=1 ))
        done
        listgen2 "$WindowManagers" "$_Quit" "$_Ok $_Exit" "LongWMs1"
      ;;
      *) break
    esac
    SaveResult=$Result                  # Because other subroutines return $Result
    if [ $SaveResult = "$_Exit" ]; then # Loop until user selects "Exit"
      break
    fi
    for lux in $LuxuriesList            # Check that chosen item is not already on the list
    do
      if [ ${lux} = ${SaveResult} ]; then
        KeepOrDelete "$SaveResult"
        Result=""
        continue
      fi
    done
    case $SaveResult in                 # Check all DE & WM entries
      "Budgie" | "Cinnamon" | "Deepin" | "Enlightenment" | "Fluxbox" | "Gnome" | "KDE" | "LXDE" | "LXQt" |  "Mate" |  "MateGTK3" | "Openbox" | "Xfce") DesktopEnvironment=$SaveResult
        for lux in $LuxuriesList
        do
          if [ ${lux} = "FelizOB" ]; then
            DesktopEnvironment="FelizOB"      # FelizOB is  prioritised over any added DE/WM
          fi
        done
       ;;
      "FelizOB") DesktopEnvironment="FelizOB" # FelizOB is  prioritised over any added DE/WM
       ;;
      "") continue
       ;;
      *) Echo
    esac
    if [ ${SaveResult} = "libreoffice" ]; then
      LuxuriesList="${LuxuriesList} libreoffice-fresh"
    else
      LuxuriesList="${LuxuriesList} ${SaveResult}"
    fi
  done
}

ChooseDM() { # Choose a display manager
  if [ $DesktopEnvironment = "FelizOB" ]; then
    DisplayManager="lxdm"
    return
  fi
  case $DisplayManager in
  "") # Only offered if no other display manager has been set
      Counter=0
      Greeter=""
      DMList="GDM LightDM LXDM sddm SLIM XDM"
      print_heading
      PrintOne "A display manager provides a graphical login screen"
      PrintOne "If in doubt, choose LightDM"
      PrintOne "If you do not install a display manager, you will have"
      PrintOne "to launch your desktop environment manually"
      Echo
      listgen1 "${DMList}" "" "$_Ok $_None"
      Reply=$Response
      for item in ${DMList}
      do
        Counter=$((Counter+1))
        if [ $Counter -eq $Reply ]
        then
          SelectedDM=$item
          case $SelectedDM in
            "GDM") DisplayManager="gdm"
              ;;
            "LightDM") DisplayManager="lightdm"
                  Greeter="lightdm-gtk-greeter"
              ;;
            "LXDM") DisplayManager="lxdm"
              ;;
            "sddm") DisplayManager="sddm"
              ;;
            "SLIM") DisplayManager="slim"
              ;;
            "XDM") DisplayManager="xdm"
              ;;
            *) DisplayManager=""
          esac
          break
        fi
      done
    ;;
  *) # Warn that DM already set, and offer option to change it
      print_heading
      PrintOne "Display manager is already set as" ":" "" "$DisplayManager."
      PrintOne "Only one display manager can be active"
      Echo
      PrintOne "Do you wish to change it?"
      Echo
      Buttons "Yes/No" "$_Yes $_No" "$_Instructions"
      Echo
      if [ $Response -eq 1 ]; then    # User wishes to change DM
        DisplayManager=""             # Clear DM variable
        Greeter=""                    # and greeter
        ChooseDM                      # Call this function again
      fi
  esac
}

SetGrubDevice() {
  DEVICE=""
  DevicesList="$(lsblk -d | awk '{print "/dev/" $1}' | grep 'sd\|hd\|vd')"  # Preceed field 1 with '/dev/' # This is good use of awk
  print_heading
  GrubDevice=""
  local Counter=0
  PrintOne "Select the device where Grub is to be installed"
  PrintOne "Note that if you do not select a device, Grub"
  PrintOne "will not be installed, and you will have to make"
  PrintOne "alternative arrangements for booting your new system"
  Echo
  listgen1 "${DevicesList}" "" "$_Ok $_None"
  Reply=$Response
  for i in ${DevicesList}
  do
    Item=$i
    Counter=$((Counter+1))
    if [ $Counter -eq $Reply ]; then
      GrubDevice=$Item
      break
    fi
  done
}

FinalCheck() {
  while :
  do
    print_heading
    PrintOne "These are the settings you have entered. Please check them"
    PrintOne "before we move on to partitioning your device"
    Echo
    Translate "Zone/subZone will be"
    PrintMany "1) $Result" "$ZONE/$SUBZONE"
    Translate "Locale will be set to"
    PrintMany "2) $Result" "$CountryLocale"
    Translate "Keyboard is"
    PrintMany "3) $Result" "$Countrykbd"
    case ${IsInVbox} in
      "VirtualBox") Translate "Virtualbox guest utilities"
      PrintMany "4)" "$Result: $_Yes"
      ;;
      *) Translate "Virtualbox guest utilities"
      PrintMany "4)" "$Result: $_No"
    esac
    if [ -z $DisplayManager ]; then
      Translate "No Display Manager selected"
      PrintMany "5)" "$Result"
    else
      Translate "Display Manager"
      PrintMany "5) $Result" " = $DisplayManager"
    fi
    Translate "Root and user settings"
    PrintMany "6) $Result" "..."
    Translate "Hostname"
    PrintMany "      $Result" "= '$HostName'"
    Translate "User Name"
    PrintMany "      $Result" "= '$UserName'"
    Translate "The following extras have been selected"
    PrintMany "7) $Result" "..."
    PrintOne "${LuxuriesList}" ""
    Echo
    PrintOne "Press Enter to install with these settings, or"
    Response=20
    Translate "Enter number for data to change"
    TPread "${Result}: "
    Change=$Response
    case $Change in
      1) SetTimeZone
        continue
      ;;
      2) setlocale
        continue
      ;;
      3) getkeymap
        continue
      ;;
      4) ConfirmVbox
        continue
      ;;
      5) DisplayManager=""
        ChooseDM
        continue
      ;;
      6) ManualSettings
        continue
      ;;
      7) PickLuxuries
        continue
      ;;
      *) break
    esac
  done
}

ManualSettings() {
  while :
  do
    print_heading
    PrintOne "Enter number for data to change"
    PrintOne "or ' ' to exit"
    Echo
    Translate "Hostname (currently"
    PrintOne "1) $Result" "${HostName})"
    Translate "Username (currently"
    PrintMany "2) $Result" "${UserName})"
    Echo
    Translate "Please enter the number of your selection"
    TPread "${Result}: "
    Echo
    case $Response in
      1) Translate "Enter new Hostname (currently"
        TPread "${Result} ${HostName}): "
         HostName=$Response
        ;;
      2) Translate "Enter new username (currently"
      TPread "${Result} ${UserName}) : "
         UserName=$Response
        ;;
      *) return 0
    esac
  done
}

ChangeRootPartition() {
# Start array with SwapPartition
  Ignorelist[0]=${SwapPartition}
  local Counter=1
  AddExtras
  MakePartitionList
}

ChangeSwapPartition() {
# Start array with RootPartition
  Ignorelist[0]=${RootPartition}
  Counter=1
  AddExtras
  MakePartitionList
}

ChangePartitions() {
  # Copy RootPartition and SwapPartition into temporary array
  Ignorelist[0]=${RootPartition}
  local Counter=1
  if [ ${SwapPartition} ]; then
    Ignorelist[1]=${SwapPartition}
    Counter=2
  fi
  Ignores=${#Ignorelist[@]} # Save a count for later
  MakePartitionList
}

AddExtras() {
  # Ignorelist started and Counter set to next record number by the
  # calling function ChangeSwapPartition or ChangeRootPartition
  # Add each field (extra partition) from AddPartList into the array:
  for a in ${AddPartList[@]}; do
    Ignorelist[$Counter]=$a
    Counter=$((Counter+1))
  done
  Ignores=${#Ignorelist[@]} # Save a count for later
}
