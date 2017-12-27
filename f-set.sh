#!/bin/bash

# The Feliz2 installation scripts for Arch Linux
# Developed by Elizabeth Mills
# With grateful acknowlegements to Helmuthdu, Carl Duff and Dylan Schacht
# Revision date: 4th October 2017

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
# --------------------   -----------------------
# Function        Line   Function           Line
# --------------------   -----------------------
# SetKernel         43   SearchKeyboards     410
# ChooseMirrors     57   Username            447
# ConfirmVbox      108   SetHostname         464
# SetTimeZone      132   Options             482
# SetSubZone       166   PickLuxuries        460
# SelectSubzone    195   ShoppingList        505
# America          209   ChooseDM            805
# DoCities         244   SetGrubDevice       849
# setlocale        270   EnterGrubPath       882
# Mano             333     --- Review stage --- 
# getkeymap        351   FinalCheck          910
#                        ManualSettings     1037
# --------------------   -----------------------

SetKernel() {
  _Backtitle="https://wiki.archlinux.org/index.php/Kernels"
  print_heading
  Echo
  PrintOne "Choose your kernel"
  PrintOne "The Long-Term-Support kernel (LTS) offers stabilty"
  PrintOne "while the Latest kernel has all the new features"
  Translate "If in doubt, choose"
  PrintOne "$Result " "LTS"
  Echo
  listgen1 "LTS Latest" "" "$_Ok"
  Kernel=${Response} # Set the Kernel variable (1 = LTS; 2 = Latest)
}

ChooseMirrors() { # User selects one or more countries with Arch Linux mirrors
    _Backtitle="https://wiki.archlinux.org/index.php/Mirrors"
    # Prepare files of official Arch Linux mirrors
    # 1) Download latest list of Arch Mirrors to temporary file
    curl -s https://www.archlinux.org/mirrorlist/all/http/ > archmirrors.list
    # 2) Get line number of first country
    FirstLine=$(grep -n "Australia" archmirrors.list | head -n 1 | cut -d':' -f1)
    # 3) Remove header and save in new file
    tail -n +${FirstLine} archmirrors.list > allmirrors.list
    # 4) Delete temporary file
    rm archmirrors.list
    # 5) Create countries.list from allmirrors.list, using '##' to identify
    #                        then removing the '##' and leading spaces
    #                                       and finally save to new file for later reference
    grep "## " allmirrors.list | tr -d "##" | sed "s/^[ \t]*//" > countries.list
    # Shorten Bosnia and Herzegovina to BosniaHerzegov
    sed -i 's/Bosnia and Herzegovina/BosniaHerzegov/g' countries.list

  # Display instructions
  print_heading
  Echo
  PrintOne "Next we will select mirrors for downloading your system."
  PrintOne "You will be able to choose from a list of countries which"
  PrintOne "have Arch Linux mirrors. It is possible to select more than"
  PrintOne "one, but adding too many will slow down your installation"
  Echo
  PrintOne "Please press any key to continue"
  read -n1
  # User-selection of countries starts here:
  Counter=0
  Translate "Please choose a country"
  Instruction="$Result"
  while true
  do
    # Save a copy of the countries list without spaces to temp.file used (and deleted) by listgenx
    cat countries.list | tr ' ' '_' > temp.file 
    # Display the list for user-selection
    listgenx "$Instruction" "$_xNumber" "$_xExit" "$_xLeft" "$_xRight"
    if [ -z $Result ]; then       # User does not want to add any more mirrors
      break
    elif [ "$Result" = "BosniaHerzegov" ]; then # Previously shortened to fit screen
      Result="Bosnia_and_Herzegovina"
    fi
    # Replace any underscores in selection with spaces and add to array for use during installation
    CountryLong[${Counter}]="$(echo "$Result" | tr '_' ' ')"    # CountryLong is declared in f-vars.sh
    Counter=$((Counter+1))
    Chosen="$Result"
    Translate "added. Choose another country, or ' '"
    Instruction="$Chosen $Result"
  done
}

ConfirmVbox() {
  while true
  do
    print_heading
    Echo
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
    Echo
    PrintOne "To set the system clock, please first"
    PrintOne "choose the World Zone of your location"
    Zones=$(timedatectl list-timezones | cut -d'/' -f1 | uniq) # Ten world zones
    zones=""
    for x in ${Zones}                         # Convert to space-separated list
    do
      Translate "$x"                          # Translate
      zones="$zones $Result"
    done
    listgen1 "${zones}" "" "$_Ok"             # Allow user to select one
    CheckResult="$Result"
    ZONE=$(echo "$Zones" | head -n $Response | tail -n 1)   # System zone name of the selected item number
    Translate "$ZONE"
    NativeZONE="$Result"                      # Save ZONE in native language, for display  
    Echo
    case $CheckResult in
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
  Echo
  Translate "Now select your location in"
  _P1="$Result"
  timedatectl list-timezones | grep ${ZONE}/ | cut -d'/' -f2 > temp.file  # Prepare file to use listgenx
  listgenx "$_P1 $_P2 $NativeZONE" "$_xNumber" "$_xExit" "$_xLeft" "$_xRight"
  if [ $Result = "$_Exit" ] || [ $Result = "" ]; then
    SUBZONE=""
  else
    SUBZONE="$Result"
  fi
}

America() {
  SUBZONE=""      # Make sure this variable is empty
  print_heading
  PrintOne "Are you in any of these States?"
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

setlocale() { 
  CountryLocale=""
  while [ -z "$CountryLocale" ]
  do
    _Backtitle="https://wiki.archlinux.org/index.php/Time#Time_zone"
    SetTimeZone # First get ZONE/SUBZONE
    _Backtitle="https://wiki.archlinux.org/index.php/Locale"
    ZoneID="${ZONE}/${SUBZONE}"  # Use a copy (eg: Europe/London) to find in cities.list (field $2 is the country code, eg: GB)
    SEARCHTERM=$(grep "$ZoneID" cities.list | cut -d':' -f2)
    SEARCHTERM=${SEARCHTERM// }             # Ensure no leading spaces
    SEARCHTERM=${SEARCHTERM%% }             # Ensure no trailing spaces
    # Find all matching entries in locale.gen - This will be a table of valid locales in the form: en_GB.UTF-8
    EXTSEARCHTERM="${SEARCHTERM}.UTF-8"
    LocaleList=$(grep "${EXTSEARCHTERM}" /etc/locale.gen | cut -d'#' -f2 | cut -d' ' -f1)                # Arch
    # LocaleList=$(grep "${EXTSEARCHTERM}" /etc/locale.gen | cut -d'#' -f2 | cut -d' ' -f2 | grep -v '^UTF') # Debian
    HowMany=$(echo $LocaleList | wc -w)     # Count them
    Rows=$(tput lines)                      # to ensure menu doesn't over-run
    Rows=$((Rows-4))                        # Available (printable) rows
    choosefrom="" 
    for l in ${LocaleList[@]}               # Convert to space-separated list
    do
      choosefrom="$choosefrom $l"           # Add each item to file for handling
    done
    if [ -z "${choosefrom}" ]; then         # If none found, start again
      print_heading
      not_found
      Result=""
    else
      print_heading
      PrintOne "Choose the main locale for your system"
      Translate "Choose one or Exit to retry"
      choosefrom="$choosefrom Edit_locale.gen"                    # Add manual edit option to menu
      listgen1 "${choosefrom}" "$Result" "$_Ok $_Exit"            # Offer list of valid codes for location
      if [ $Response -eq 0 ]; then                                # If user rejects all options
        CountryLocale=""                                          # Start again
        continue
      elif [ "$Result" == "Edit_locale.gen" ]; then               # User chooses manual edit
        Mano                                                      # Use Nano to edit locale.gen
        clear
        if [ $Response -eq 1 ]; then                              # If Nano was used
          LocaleGen="$(grep -v '#' /etc/locale.gen | grep ' ' | cut -d' ' -f1)"  # Save list of entries that are
          HowMany=$(echo "$LocaleGen" | wc -l)                    # uncommented in locale.gen & count them
          case ${HowMany} in
          0) continue                                             # No uncommented lines found
          ;;                                                      # so restart
          1) Result="$(echo $LocaleGen | cut -d' ' -f1)"          # One uncommented line found
          ;;                                                      # so set it as locale
          *) print_heading                                        # Many uncommented lines found
            Translate "Choose the main locale for your system"    # Ask user to pick one as main locale
            listgen1 "${LocaleGen}" "$Result" "$_Ok"              # Display them for one to be selected
          esac
        else                                                      # Nano was not used
          continue                                                # Start again
        fi
      fi
    fi
    CountryLocale="$Result"                                       # Save selection
    CountryCode=${CountryLocale:3:2}
  done
}

Mano() {  # Use Nano to edit locale.gen
  while true
  do
    print_heading
    Echo
    PrintOne "Start Nano so you can manually uncomment locales?" # New text for line 201 English.lan
    Buttons "Yes/No" "Yes No" "$_Instructions"
    case $Response in
      "1" | "Y" | "y") nano /etc/locale.gen
        return 1
        ;;
      "2" | "N" | "n") return
        ;;
      *) not_found
    esac
  done
}

getkeymap() {
  _Backtitle="https://wiki.archlinux.org/index.php/Keyboard_configuration_in_console"
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
    Echo
    PrintOne "If you know the code for your keyboard layout, please enter"
    PrintOne "it now. If not, try entering a two-letter abbreviation"
    PrintOne "for your country or language and a list will be displayed"
    PrintOne "Alternatively, enter ' ' to start again"
    Echo
    TPread "(eg: 'dvorak' or 'us'): "
    local Term="${Response,,}"
    if [ $Term = "" ] || [ $Term = " " ]; then
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
      continue
    fi
  done
}

UserName() {
  _Backtitle="https://wiki.archlinux.org/index.php/Users_and_groups"
  print_heading
  Echo
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
  _Backtitle="https://wiki.archlinux.org/index.php/Network_configuration#Set_the_hostname"
  Entered="arch-linux"
  print_heading
  Echo
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

Options() { # User chooses between FelizOB, self-build or basic
  _Backtitle="https://wiki.archlinux.org/index.php/List_of_applications"
  print_heading
  Echo
  PrintOne "Feliz now offers you a choice. You can ..."
  Echo
  PrintOne "Build your own system, by picking the"
  PrintOne "software you wish to install"
  PrintOne "..." "$_or ..."
  PrintOne "You can choose the new FelizOB desktop, a"
  PrintOne "complete lightweight system built on Openbox"
  PrintOne "..." "$_or ..."
  PrintOne "Just install a basic Arch Linux"
  Translate "Build_My_Own"
  BMO=$Result
  Translate "FelizOB_desktop"
  listgen1 "$BMO $Result $_None" "" "$_Ok"
  case $Response in
    1) PickLuxuries
    ;;
    2) DesktopEnvironment="FelizOB"
      Scope="Full"
    ;;
    *) Scope="Basic"
  esac
}

PickLuxuries() { # User selects any combination from a store of extras
  Translate "Added so far"
  AddedSoFar="$Result"
  TransCatList=""
  
  for x in {1..9}         # Prepare array that records if a category
  do                      # has already been translated
    BeenThere[${x}]="N"   # Set each element to 'N'
  done
  
  for category in $CategoriesList
  do
    Translate "$category"
    TransCatList="$TransCatList $Result"
  done
  print_heading
  case "$LuxuriesList" in
  '') Echo
      PrintOne "Now you have the option to add extras, such as a web browser"
    PrintOne "desktop environment, etc, from the following categories"
  ;;
  *) PrintOne "You can add more items, or select items to delete"
  esac
  #
  while true
  do
    listgen1 "${TransCatList}" "$_Quit" "$_Ok $_Exit"
    Category=$Response
    if [ $Result = "$_Exit" ]; then
      break
    else
      ShoppingList
      print_heading
      Echo
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

ShoppingList() { # Called by PickLuxuries after a category has been chosen.
  Translate "Choose an item"
  while true
  do
    print_heading
    Echo
    PrintOne "$AddedSoFar" ": ${LuxuriesList}"
    PrintOne "You can add more items, or select items to delete"
    Echo
    PrintOne "${Categories[$Category]}" # $Category is number of item in CategoriesList
    # Translate items in selected category and pass to listgen2 for user to choose one item;
    local Counter=1
    MaxLen=0
    case $Category in
     1) if [ ${BeenThere[${Category}]} = "N" ]; then  # Do not translate if already done
          OptionsCounter=1
          for Option in "${LongAccs[@]}"              # First translate all elements
          do
            Translate "$Option"
            LongAccs[${OptionsCounter}]="$Result"     # Replace element with translation
            (( OptionsCounter+=1 ))
          done

          for i in ${Accessories}
          do
            CompareLength "$i - ${LongAccs[${Counter}]}"  # If total length is greater than previous, save it
            LongAccs1[${Counter}]="$i - ${LongAccs[${Counter}]}"
            (( Counter+=1 ))
          done

          # Compare length of first item in array with length of longest item
          FirstElement="${LongAccs1[1]}"
          if [ ${#FirstElement} -lt $MaxLen ]; then # If shorter
            PaddLength "$FirstElement"              # Use PaddLength function to extend with spaces
            LongAccs1[1]="$Result"                  # and add result as first element in LongAccs
          fi
        fi
        listgen2 "$Accessories" "$_Quit" "$_Ok $_Exit" "LongAccs1"
        BeenThere[${Category}]="Y"                  # Prevent retranslation
       ;;
       2) if [ ${BeenThere[${Category}]} = "N" ]; then   # Do not translate if already done
            OptionsCounter=1
            for Option in "${LongDesk[@]}"          # Translate all elements
            do
              Translate "$Option"
              LongDesk[${OptionsCounter}]="$Result"
              (( OptionsCounter+=1 ))
            done
          
            for i in ${Desktops}
            do
              CompareLength "$i - ${LongAccs[${Counter}]}"  # If total length is greater than previous, save it
              LongDesk1[${Counter}]="$i - ${LongDesk[${Counter}]}"
              (( Counter+=1 ))
            done

            # Compare length of first item in array with length of longest item
            FirstElement="${LongDesk1[1]}"
            if [ ${#FirstElement} -lt $MaxLen ]; then # If shorter
              PaddLength "$FirstElement"              # Use PaddLength function to extend with spaces
              LongDesk1[1]="$Result"                  # and add result as first element in LongAccs
            fi
          fi
          listgen2 "$Desktops" "$_Quit" "$_Ok $_Exit" "LongDesk1"
          BeenThere[${Category}]="Y"                  # Prevent retranslation
       ;;
       3) if [ ${BeenThere[${Category}]} = "N" ]; then  # Do not translate if already done
            OptionsCounter=1
            for Option in "${LongGraph[@]}"           # Translate all elements
            do
              Translate "$Option"
              LongGraph[${OptionsCounter}]="$Result"
              (( OptionsCounter+=1 ))
            done
  
            for i in ${Graphical}
            do
              CompareLength "$i - ${LongAccs[${Counter}]}"  # If total length is greater than previous, save it
              LongGraph1[${Counter}]="$i - ${LongGraph[${Counter}]}"
              (( Counter+=1 ))
            done

            # Compare length of first item in array with length of longest item
            FirstElement="${LongGraph1[1]}"
            if [ ${#FirstElement} -lt $MaxLen ]; then # If shorter
              PaddLength "$FirstElement"              # Use PaddLength function to extend with spaces
              LongGraph1[1]="$Result"                 # and add result as first element in LongAccs
            fi
          fi
          listgen2 "$Graphical" "$_Quit" "$_Ok $_Exit" "LongGraph1"
          BeenThere[${Category}]="Y"                  # Prevent retranslation
       ;;
       4) if [ ${BeenThere[${Category}]} = "N" ]; then   # Do not translate if already done
            OptionsCounter=1
            for Option in "${LongNet[@]}"             # Translate all elements
            do
              Translate "$Option"
              LongNet[${OptionsCounter}]="$Result"
              (( OptionsCounter+=1 ))
            done
  
            for i in ${Internet}
            do
              CompareLength "$i - ${LongAccs[${Counter}]}"  # If total length is greater than previous, save it
              LongNet1[${Counter}]="$i - ${LongNet[${Counter}]}"
              (( Counter+=1 ))
            done

            # Compare length of first item in array with length of longest item
            FirstElement="${LongNet1[1]}"
            if [ ${#FirstElement} -lt $MaxLen ]; then # If shorter
              PaddLength "$FirstElement"              # Use PaddLength function to extend with spaces
              LongNet1[1]="$Result"                   # and add result as first element in LongAccs
            fi
          fi
          listgen2 "$Internet" "$_Quit" "$_Ok $_Exit" "LongNet1"
          BeenThere[${Category}]="Y"                  # Prevent retranslation
       ;;
       5) if [ ${BeenThere[${Category}]} = "N" ]; then  # Do not translate if already done
            OptionsCounter=1
            for Option in "${LongMulti[@]}"           # Translate all elements
            do
              Translate "$Option"
              LongMulti[${OptionsCounter}]="$Result"
              (( OptionsCounter+=1 ))
            done
  
            for i in ${Multimedia}
            do
              CompareLength "$i - ${LongAccs[${Counter}]}"  # If total length is greater than previous, save it
              LongMulti1[${Counter}]="$i - ${LongMulti[${Counter}]}"
              (( Counter+=1 ))
            done
  
            # Compare length of first item in array with length of longest item
            FirstElement="${LongMulti1[1]}"
            if [ ${#FirstElement} -lt $MaxLen ]; then # If shorter
              PaddLength "$FirstElement"              # Use PaddLength function to extend with spaces
              LongMulti1[1]="$Result"                 # and add result as first element in LongAccs
            fi
          fi
          listgen2 "$Multimedia" "$_Quit" "$_Ok $_Exit" "LongMulti1"
          BeenThere[${Category}]="Y"                  # Prevent retranslation
       ;;
       6) if [ ${BeenThere[${Category}]} = "N" ]; then   # Do not translate if already done
            OptionsCounter=1
            for Option in "${LongOffice[@]}"          # Translate all elements
            do
              Translate "$Option"
              LongOffice[${OptionsCounter}]="$Result"
              (( OptionsCounter+=1 ))
            done
  
            for i in ${Office}
            do
              CompareLength "$i - ${LongAccs[${Counter}]}"  # If total length is greater than previous, save it
              LongOffice1[${Counter}]="$i - ${LongOffice[${Counter}]}"
              (( Counter+=1 ))
            done
  
            # Compare length of first item in array with length of longest item
            FirstElement="${LongOffice1[1]}"
            if [ ${#FirstElement} -lt $MaxLen ]; then # If shorter
              PaddLength "$FirstElement"              # Use PaddLength function to extend with spaces
              LongOffice1[1]="$Result"                # and add result as first element in LongAccs
            fi
          fi
          listgen2 "$Office" "$_Quit" "$_Ok $_Exit" "LongOffice1"
          BeenThere[${Category}]="Y"                  # Prevent retranslation
       ;;
       7) if [ ${BeenThere[${Category}]} = "N" ]; then  # Do not translate if already done
            OptionsCounter=1
            for Option in "${LongProg[@]}"            # Translate all elements
            do
              Translate "$Option"
              LongProg[${OptionsCounter}]="$Result"
              (( OptionsCounter+=1 ))
            done

            for i in ${Programming}
            do
              CompareLength "$i - ${LongAccs[${Counter}]}"  # If total length is greater than previous, save it
              LongProg1[${Counter}]="$i - ${LongProg[${Counter}]}"
              (( Counter+=1 ))
            done

            # Compare length of first item in array with length of longest item
            FirstElement="${LongProg1[1]}"
            if [ ${#FirstElement} -lt $MaxLen ]; then # If shorter
              PaddLength "$FirstElement"              # Use PaddLength function to extend with spaces
              LongProg1[1]="$Result"                  # and add result as first element in LongAccs
            fi
          fi
          listgen2 "$Programming" "$_Quit" "$_Ok $_Exit" "LongProg1"
          BeenThere[${Category}]="Y"                  # Prevent retranslation
       ;;
       8) if [ ${BeenThere[${Category}]} = "N" ]; then  # Do not translate if already done
            OptionsCounter=1
            for Option in "${LongWMs[@]}"             # Translate all elements
            do
              Translate "$Option"
              LongWMs[${OptionsCounter}]="$Result"
              (( OptionsCounter+=1 ))
            done
  
            for i in ${WindowManagers}
            do
              CompareLength "$i - ${LongAccs[${Counter}]}"  # If total length is greater than previous, save it
              LongWMs1[${Counter}]="$i - ${LongWMs[${Counter}]}"
              (( Counter+=1 ))
            done
  
          # Compare length of first item in array with length of longest item
          FirstElement="${LongWMs1[1]}"
          if [ ${#FirstElement} -lt $MaxLen ]; then # If shorter
            PaddLength "$FirstElement"              # Use PaddLength function to extend with spaces
            LongWMs1[1]="$Result"                   # and add result as first element in LongAccs
          fi
        fi
        listgen2 "$WindowManagers" "$_Quit" "$_Ok $_Exit" "LongWMs1"
        BeenThere[${Category}]="Y"                  # Prevent retranslation
      ;;
      9) if [ ${BeenThere[${Category}]} = "N" ]; then  # Do not translate if already done
          OptionsCounter=1
          for Option in "${LongBars[@]}"            # Translate all elements
          do
            Translate "$Option"
            LongBars[${OptionsCounter}]="$Result"
            (( OptionsCounter+=1 ))
          done

          for i in ${Taskbars}
          do
            CompareLength "$i - ${LongAccs[${Counter}]}"  # If total length is greater than previous, save it
            LongBars1[${Counter}]="$i - ${LongBars[${Counter}]}"
            (( Counter+=1 ))
          done
 
          # Compare length of first item in array with length of longest item
          FirstElement="${LongBars1[1]}"
          if [ ${#FirstElement} -lt $MaxLen ]; then # If shorter
            PaddLength "$FirstElement"              # Use PaddLength function to extend with spaces
            LongBars1[1]="$Result"                  # and add result as first element in LongAccs
          fi
        fi
        listgen2 "$Taskbars" "$_Quit" "$_Ok $_Exit" "LongBars1"
        BeenThere[${Category}]="Y"                  # Prevent retranslation
      ;;
      *) break
    esac
    SaveResult=$Result                  # Because other subroutines return $Result
    if [ $SaveResult = "$_Exit" ]; then # Loop until user selects "Exit"
      break
    fi
    Removed="N"                         # Prepare temporary variables
    TempList=""
    for lux in $LuxuriesList            # Check LuxuriesList
    do
      if [ ${lux} = ${SaveResult} ]; then # If already on list, it will be removed
        Removed="Y"
      else
        TempList="$TempList ${lux}"       # If not already on LuxuriesList, add to TempList
      fi
    done
    LuxuriesList="$TempList"
    if [ $Removed = "Y" ]; then        # If selected item was removed
      continue                         # Don't process it any further
    fi
    case $SaveResult in                # Check all DE & WM entries
      "Awesome" | "Budgie" | "Cinnamon" | "Enlightenment" | "Fluxbox" | "Gnome" | "i3" | "Icewm" | "JWM" | "KDE" | "LXDE" | "LXQt" |  "Mate" | "Openbox" | "Windowmaker" | "Xfce" | "Xmonad") DesktopEnvironment=$SaveResult
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
  _Backtitle="https://wiki.archlinux.org/index.php/Display_manager"
  case "$DisplayManager" in
  "") # Only offered if no other display manager has been set
      Counter=0
      DMList="GDM LightDM LXDM sddm SLIM XDM"
      print_heading
      Echo
      PrintOne "A display manager provides a graphical login screen"
      Translate "If in doubt, choose"
      PrintOne "$Result " "LightDM"
      PrintOne "If you do not install a display manager, you will have"
      PrintOne "to launch your desktop environment manually"
      listgen1 "${DMList}" "" "$_Ok $_None"
      Reply=$Response
      for item in ${DMList}
      do
        Counter=$((Counter+1))
        if [ $Counter -eq $Reply ]; then
          SelectedDM=$item
          case $SelectedDM in
            "GDM") DisplayManager="gdm"
              ;;
            "LightDM") DisplayManager="lightdm"
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
        ChooseDM                      # Call this function again
      fi
  esac
}

SetGrubDevice() {
  DEVICE=""
  DevicesList="$(lsblk -d | awk '{print "/dev/" $1}' | grep 'sd\|hd\|vd')"  # Preceed field 1 with '/dev/'
  _Backtitle="https://wiki.archlinux.org/index.php/GRUB"
  # Add an option to enter grub device manually
  Translate "Enter_Manually"
  DevicesList="$DevicesList $Result"
  print_heading
  Echo
  GrubDevice=""
  local Counter=0
  PrintOne "Select the device where Grub is to be installed"
  PrintOne "Note that if you do not select a device, Grub"
  PrintOne "will not be installed, and you will have to make"
  PrintOne "alternative arrangements for booting your new system"
  Echo
  listgen1 "${DevicesList}" "" "$_Ok $_None"
  Reply=$Response

  if [ $Result = "Enter_Manually" ]; then				# Call function to type in a path
    EnterGrubPath
  else
    for i in ${DevicesList}
    do
      Item=$i
      Counter=$((Counter+1))
      if [ $Counter -eq $Reply ]; then
        GrubDevice=$Item
        break
      fi
    done
  fi
}

EnterGrubPath() {
  Entered=""
  print_heading
  Echo
  PrintOne "You have chosen to manually enter the path for Grub"
  PrintOne "This should be in the form /dev/sdx or similar"
  PrintOne "Only enter a device, do not include a partition number"
  PrintOne "If in doubt, consult https://wiki.archlinux.org/index.php/GRUB"
  PrintOne "To go back, leave blank"
  Echo
  Translate "Enter the path where Grub is to be installed"
  TPread "${Result}: "
  Entered=${Response,,}
  # test input
  CheckGrubEntry="${Entered:0:5}"
  if [ -z $Entered ]; then
    SetGrubDevice
  elif [ $CheckGrubEntry != "/dev/" ]; then
    Echo
    TPecho "$Entered is not in the correct format"
    not_found
    EnterGrubPath
  else
    GrubDevice="${Entered}"
    read -t "$GrubDevice"
  fi
}

FinalCheck() {
  while true
  do
    print_heading
    PrintOne "These are the settings you have entered."
    PrintOne "Please check them before Feliz begins the installation"
    Echo
    Translate "Zone/subZone will be"
    PrintMany "1) $Result" "$ZONE/$SUBZONE"
    Translate "Locale will be set to"
    PrintMany "2) $Result" "$CountryLocale"
    Translate "Keyboard is"
    PrintMany "3) $Result" "$Countrykbd"
    case ${IsInVbox} in
      "VirtualBox") Translate "virtualbox guest modules"
      PrintMany "4)" "$Result: $_Yes"
      ;;
      *) Translate "virtualbox guest modules"
      PrintMany "4)" "$Result: $_No"
    esac
    if [ -z "$DisplayManager" ]; then
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
    SaveStartPoint="$EMPTY" # Save cursor start point
    if [ $Scope = "Basic" ]; then
      PrintOne "$_None" ""
    elif [ $DesktopEnvironment ] && [ $DesktopEnvironment = "FelizOB" ]; then
      PrintOne "FelizOB" ""
    elif [ -z "$LuxuriesList" ]; then
      PrintOne "$_None" ""
    else
      Translate="N"
      PrintOne "${LuxuriesList}" ""
      Translate="Y"
    fi
    EMPTY="$SaveStartPoint" # Reset cursor start point
    # 8) Kernel
    Translate "Kernel"
    if [ $Kernel -eq 1 ]; then
      PrintMany "8) $Result" "= 'LTS'"
    else
      PrintMany "8) $Result" "= 'Latest'"
    fi
    # 9) Grub
    Translate "Grub will be installed on"
    PrintMany "9) $Result" "= '$GrubDevice'"
    # 10) Partitions 
    Translate "The following partitions have been selected"
    PrintMany "10) $Result" "..."
    Translate="N"
    PrintOne "${RootPartition} /root ${RootType}"
    PrintMany "${SwapPartition} /swap"
    if [ -n "${AddPartList}" ]; then
      local Counter=0
      for Part in ${AddPartList}                    # Iterate through the list of extra partitions
      do                                            # Display each partition, mountpoint & format type
        if [ $Counter -ge 1 ]; then                 # Only display the first one
          PrintMany "Too many to display all"
          break
        fi
        PrintMany "${Part} ${AddPartMount[${Counter}]} ${AddPartType[${Counter}]}"
        Counter=$((Counter+1))

      done
    fi
    Translate="Y"
    Response=20
    Echo
    PrintOne "Press Enter to install with these settings, or"
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
      8) SetKernel
        continue
      ;;
      9) if [ $GrubDevice != "EFI" ]; then  # Can't be changed if EFI
          SetGrubDevice
        fi
        continue
      ;;
      10) AddPartList=""   # Empty the lists of extra partitions
        AddPartMount=""
        AddPartType=""
        CheckParts         # Restart partitioning
        ChoosePartitions
        continue
      ;;
      *) break
    esac
  done
}

ManualSettings() {
  while true
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
