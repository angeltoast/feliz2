#!/bin/bash

# The Feliz2 installation scripts for Arch Linux
# Developed by Elizabeth Mills  liz@feliz.one
# With grateful acknowlegements to Helmuthdu, Carl Duff and Dylan Schacht
# Revision date: 9th January 2018

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
# --------------------------  ---------------------------
# Function             Line   Function               Line
# --------------------------  ---------------------------
# menu_dialog            44   pick_category           554
# set_timezone          102   choose_extras           633
# set_subzone           154   display_extras          692
# america               199   choose_display_manager  752
# america_subgroups     250   select_grub_device      776
# setlocale             273   enter_grub_path         804
# edit_locale           349   select_kernel           828
# get_keymap            369   choose_mirrors          852
# search_keyboards      431   edit_mirrors            923
# set_username          477   confirm_virtualbox      949
# set_hostname          496   final_check             968
# type_of_installation  515   manual_settings        1098
#                             wireless_option        1115
# -------------------------   ---------------------------

function menu_dialog {  # Display a simple menu from $menu_dialog_variable and return selection as $Result
                        # $1 and $2 are dialog box size;
                        # $3 is optional: can be the text for --cancel-label
  if [ "$3" ]; then
    cancel="$3"
  else
    cancel="Cancel"
  fi
  
  # Prepare array for display
  declare -a ItemList=()                                      # Array will hold entire list
  Items=0
  for Item in $menu_dialog_variable; do                       # Read items from the variable
    Items=$((Items+1))                                        # and copy each one to the array
    ItemList[${Items}]="${Item}"                              # First element is tag
    Items=$((Items+1))
    ItemList[${Items}]="${Item}"                              # Second element is required
  done
   
  # Display the list for user-selection
  dialog --backtitle "$Backtitle" --title " $title " \
    --no-tags --ok-label "$Ok" --cancel-label "$Cancel" --menu "$Message" \
      "$1" "$2" ${Items} "${ItemList[@]}" 2>output.file
  retval=$?
  Result=$(cat output.file)
}

function set_timezone {
  SUBZONE=""
  while true; do
    message_first_line "To set the system clock, please first"
    message_subsequent "choose the World Zone of your location"
    timedatectl list-timezones | cut -d'/' -f1 | uniq > zones.file # Ten world zones

    declare -a ItemList=()                                    # Array will hold entire menu list
    Items=0
    Counter=0
    while read -r Item; do                                    # Read items from the zones file
      Counter=$((Counter+1))                                  # for display in menu
      translate "$Item"                                       # Translate each one for display
      Item="$Result"
      Items=$((Items+1))
      ItemList[${Items}]="${Counter}"                         # First column (tag) is the item number
      Items=$((Items+1))
      ItemList[${Items}]="${Item}"                            # Second column is the item
    done < zones.file

    dialog --backtitle "$Backtitle" --no-tags \
        --ok-label "$Ok" --cancel-label "$Cancel" \
        --menu "\n      $Message\n" \
        20 55 $Counter "${ItemList[@]}" 2>output.file
    if [ $? -ne 0 ]; then return 1; fi
    Response=$(cat output.file)
    Item=$((Response*2))
    NativeZONE="${ItemList[${Item}]}"                        # Recover item from list (in user's language)  

    ZONE=$(head -n "$Response" zones.file | tail -n 1)     # Recover English version of Item

    # We now have a zone! eg: Europe
    set_subzone                             # Call subzone function
    if [ "$SUBZONE" != "" ]; then           # If non-empty, Check "${ZONE}/$SUBZONE" against 
                                            # "timedatectl list-timezones"
      timedatectl list-timezones | grep "${ZONE}/$SUBZONE" > /dev/null
      if [ $? -eq 0 ]; then return 0; fi    # If "${ZONE}/$SUBZONE" found, return to caller
    fi
  done
  return 0
}

function set_subzone {  # Called from set_timezone
                        # Use ZONE set in set_timezone to prepare list of available subzones
  while true; do
    SubZones=$(timedatectl list-timezones | grep "${ZONE}"/ | sed 's/^.*\///')
    Ocean=0
    SUBZONE=""
  
    case $ZONE in
    "Arctic") SUBZONE="Longyearbyen"
      return ;;
    "Atlantic"|"Indian"|"Pacific") Ocean=1 ;;
    "america") america
      return
    esac
  
    # User-selection of subzone starts here:
    menu_dialog_variable=$(timedatectl list-timezones | grep "${ZONE}"/ | cut -d'/' -f2)
  
    translate "Now select your location in"
    Message="$Result $NativeZONE"
    Cancel="$Back"
    title="Subzone"
    
    menu_dialog  30 60 # Function (arguments are dialog size) displays a menu and return selection as $Result
    if [ $retval -eq 0 ]; then
      SUBZONE="$Result"
    else
      SUBZONE=""
      return 1
    fi
    return 0
  done
  return 0
}

function america {  # Called from set_subzone
                    # Necessary because some zones in the americas have a
                    # middle zone (eg: america/Argentina/Buenes_Aries)
  SUBZONE=""        # Make sure this variable is empty
  SubList=""        # Start an empty list
  Previous=""       # Prepare to save previous record
  local toggle="First"
  for i in $(timedatectl list-timezones | grep "$ZONE/" | awk 'BEGIN { FS = "/"; OFS = "/" } {print $2}'); do
    if [ -n "$Previous" ] && [ "$i" = "$Previous" ] && [ "$toggle" = "First" ]; then # First reccurance
      SubList="$SubList $i"
      Toggle="Second"
    elif [ -n "$Previous" ] && [ "$i" != "$Previous" ] && [ "$toggle" = "Second" ]; then # 1st occ after prev group
      Toggle="First"
      Previous=$i
    else                                                                  # Subsequent occurances
      Previous=$i
    fi
  done
  
  SubGroup=""
  translate "Are you in any of these States?"
  title="$Result"
  translate "None_of_these"
  Cancel="$Result"
  menu_dialog_variable="$SubList"
  Message=" "
  
  menu_dialog  15 40 # (arguments are dialog size) displays a menu and returns $retval and $Result
  
  if [ $retval -eq 1 ]; then              # "None of These" - check normal subzones
    translate "Now select your location in"
    Message="$Result $NativeZONE"
    menu_dialog_variable=$(timedatectl list-timezones | grep "${ZONE}"/ | grep -v 'Argentina\|Indiana\|Kentucky\|North_Dakota' | cut -d'/' -f2)  # Prepare variable
    Cancel="$Back"
    title="Subzone"
    
    menu_dialog  25 50 # Display menu (arguments are dialog size) and return selection as $Result
    if [ $retval -eq 0 ]; then    
      SUBZONE="$Result"
      america_subgroups
    else
      SUBZONE=""
    fi
  else                                    # This is for 2-part zones
    SubGroup=$Result                      # Save subgroup for next function
    ZONE="${ZONE}/$SubGroup"              # Add subgroup to ZONE
    america_subgroups                     # City function for subgroups
  fi
  return 0
}

function america_subgroups { # Called from america
                             # Specifically for America, which has subgroups
                             # This function receives either 1-part or 2-part ZONE from america
  case $SubGroup in
  "") # No subgroup selected. Here we are working on the second field - cities without a subgroup
      menu_dialog_variable=$(timedatectl list-timezones | grep "$ZONE/" | awk 'BEGIN { FS = "/"; OFS = "/" } {print $2}') ;;
  *) # Here we are working on the third field - cities within the chosen subgroup
      menu_dialog_variable=$(timedatectl list-timezones | grep "$ZONE/" | awk 'BEGIN { FS = "/"; OFS = "/" } {print $3}')
   esac
  translate "Please select a city from this list"
  Message="$Result"
  Cancel="$Back"
  title="Subzone"
  
  menu_dialog  25 44 # New function (arguments are dialog size) to display a menu and return $Result
  if [ $retval -eq 0 ]; then
    SUBZONE="$Result"
  else
    SUBZONE=""
  fi
  return 0
}

function setlocale {
  CountryLocale=""
  while [ -z "$CountryLocale" ]; do
    set_timezone # First get a validated ZONE/SUBZONE
    if [ $? -ne 0 ]; then return 1; fi

    ZoneID="${ZONE}/${SUBZONE}"   # Use a copy (eg: Europe/London) to find in cities.list
                                  # (field 2 in cities.list is the country code (eg: GB)
    SEARCHTERM=$(grep "$ZoneID" cities.list | cut -d':' -f2)
    SEARCHTERM=${SEARCHTERM// }             # Ensure no leading spaces
    SEARCHTERM=${SEARCHTERM%% }             # Ensure no trailing spaces
    # Find all matching entries in locale.gen - This will be a table of valid locales in the form: en_GB.UTF-8
    EXTSEARCHTERM="${SEARCHTERM}.UTF-8"

    if [ $(grep "^NAME" /etc/*-release | cut -d'"' -f2 | cut -d' ' -f1) = "Debian" ]; then
      # In case testing in Debian
      LocaleList=$(grep "${EXTSEARCHTERM}" /etc/locale.gen | cut -d'#' -f2 | cut -d' ' -f2 | grep -v '^UTF')
    else
      # Normal Arch setting
      LocaleList=$(grep "${EXTSEARCHTERM}" /etc/locale.gen | cut -d'#' -f2 | cut -d' ' -f1)
    fi

    HowMany=$(echo "$LocaleList" | wc -w)     # Count them
    Rows=$(tput lines)                      # to ensure menu doesn't over-run
    Rows=$((Rows-4))                        # Available (printable) rows
    choosefrom="" 
    for l in "${LocaleList[@]}"; do           # Convert to space-separated list
      choosefrom="$choosefrom $l"           # Add each item to file for handling
    done
    if [ -z "${choosefrom}" ]; then         # If none found, start again
      not_found 10 30 "Locale not found"
      Result=""
    else
      title="Locale"
      message_first_line "Choose the main locale for your system"
      message_subsequent "Choose one or Exit to retry"
      menu_dialog_variable="$choosefrom Edit_locale.gen"             # Add manual edit option to menu
      Cancel="$Exit"

      menu_dialog 17 50 # Arguments are dialog size. To display a menu and return $Result & $retval
      if [ $retval -ne 0 ]; then return 1; fi
      Response="$retval"
      if [ $Response -eq 1 ]; then                                  # If user chooses <Exit>
        CountryLocale=""                                            # Start again
        continue
      elif [ "$Result" == "Edit_locale.gen" ]; then                 # User chooses manual edit
        edit_locale                                                 # Use Nano to edit locale.gen
        retval=$?
        if [ $retval -eq 0 ]; then  # If Nano was used, get list of uncommented entries
          grep -v '#' /etc/locale.gen | grep ' ' | cut -d' ' -f1 > list.file 
          HowMany=$(wc -l list.file | cut -d' ' -f1)                # Count them
          case ${HowMany} in
          0) continue ;;                                            # No uncommented lines found, so restart
          1) Result="$(cat list.file)" ;;                           # One uncommented line found, so set it as locale
          *) translate "Choose the main locale for your system"     # If many uncommented lines found
            Message="$Result"
            # Prepare list for display
            menu_dialog_variable="$(cat list.file)"

            menu_dialog 20 60                                       # Display in menu
          esac
        else                                                        # Nano was not used
          continue                                                  # Start again
        fi
      fi
    fi
    CountryLocale="$Result"                                         # Save selection eg: en_GB.UTF-8
    CountryCode=${CountryLocale:3:2}                                # eg: GB
  done
  return 0
}

function edit_locale {  # Use Nano to edit locale.gen
  
  while true; do
    translate "Start Nano so you can manually uncomment locales?" # New text for line 201 English.lan
    Message="$Result"
    title=""
    dialog --backtitle "$Backtitle" --title " $title " \
      --yes-label "$Yes" --no-label "$No" --yesno "\n$Message" 6 55 2>output.file
    retval=$?
    case $retval in
      0) nano /etc/locale.gen
        return 0 ;;
      1) return 1 ;;
      *) not_found 10 50 "Error reported at function ${FUNCNAME[0]} line ${LINENO[0]} in ${SOURCE[0]} called from ${SOURCE[1]}"
        return 2
    esac
  done
}

function get_keymap { # Display list of locale-appropriate keyboards for user to choose

  country="${CountryLocale,,}"                                          # From SetLocale - eg: en_gb.utf-8
  case ${country:3:2} in                                                # eg: gb
  "gb") Term="uk" ;;
  *) Term="${country:3:2}"
  esac
  
  ListKbs=$(grep "${Term}" keymaps.list)
  Found=$(grep -c "${Term}" keymaps.list)  # Count records
  if [ -z "$Found" ]; then
    Found=0
  fi

  title=$(echo "$Result" | cut -d' ' -f1)
  Countrykbd=""
  while [ -z "$Countrykbd" ]; do
    case $Found in
    0)  # If the search found no matches
      message_first_line "Sorry, no keyboards found based on your location"
      translate "Keyboard is"
      dialog --backtitle "$Backtitle" --ok-label "$Ok" --msgbox "$Message"
      search_keyboards ;;
    1)  # If the search found one match
      message_first_line "Only one keyboard found based on your location"
      message_subsequent "Do you wish to accept this? Select No to search for alternatives"
      
      dialog --backtitle "$Backtitle" --yes-label "$Yes" --no-label "$No" --yesno "\n$Message" 10 55 2>output.file
      retval=$?
      Result="$(cat output.file)"
      case ${retval} in
        0) Countrykbd="${Result}"
        ;;
        1) search_keyboards                   # User can enter search criteria to find a keyboard layout 
        ;;
        *) return 1
      esac
      loadkeys "${Countrykbd}" 2>> feliz.log ;;
    *) # If the search found multiple matches
      title="Keyboards"
      message_first_line "Select your keyboard, or Exit to try again"
      menu_dialog_variable="$ListKbs"
      message_first_line "Please choose one"
      translate "None_of_these"
      menu_dialog 15 40 "$Result"
      case ${retval} in
        0) Countrykbd="${Result}" ;;
        1) search_keyboards ;;                # User can enter search criteria to find a keyboard layout
        *) return 1
      esac
      loadkeys "${Countrykbd}" 2>> feliz.log
    esac
  done
  return 0
}

function search_keyboards { # Called by get_keymap when all other options failed 
                            # User can enter search criteria to find a keyboard layout 
  Countrykbd=""
  while [ -z "$Countrykbd" ]; do
    message_first_line "If you know the code for your keyboard layout, please enter"
    message_subsequent "it now. If not, try entering a two-letter abbreviation"
    message_subsequent "for your country or language and a list will be displayed"
    message_subsequent "eg: 'dvorak' or 'us'"
    
    dialog --backtitle "$Backtitle" --ok-label "$Ok" --inputbox "$Message" 14 70 2>output.file
    retval=$?
    Result="$(cat output.file)"
    if [ "$retval" -eq 1 ] || [ "$Result" = "" ]; then
      Countrykbd=""
      return 1
    fi
    local term="${Result,,}"
    ListKbs=$(grep "${Term}" keymaps.list)
    if [ -n "${ListKbs}" ]; then  # If a match or matches found
      menu_dialog_variable="$ListKbs"
      message_first_line "Please choose one"

      menu_dialog 15 40
      if [ ${retval} -eq 1 ]; then    # Try again
        Countrykbd=""
        continue
      else
        ListKbs=$(grep "$Result" keymaps.list)    # Check if valid
        if [ -n "${ListKbs}" ]; then  # If a match or matches found
          Countrykbd="${Result}"
        else
          translate "No keyboards found containing"
          not_found 8 40 "${Result}\n '$term'"
          continue
        fi
      fi
      loadkeys "$Countrykbd" 2>> feliz.log
      return 0
    else
      translate "No keyboards found containing"
      not_found 8 40 "${Result}\n '$term'"
    fi
  done
  return 0
}

function set_username {
   
  message_first_line "Enter a name for the primary user of the new system"
  message_subsequent "If you don't create a username here, a"
  message_subsequent "default user called 'archie' will be set up"
  translate "User Name"
  title="${Result}"
  
  dialog --backtitle "$Backtitle" --title " $title " --ok-label "$Ok" --inputbox "$Message" 12 70 2>output.file
  retval=$?
  Result="$(cat output.file)"

  if [ -z "$Result" ]; then
    user_name="archie"
  else
    user_name=${Result,,}
  fi
  return 0
}

function set_hostname {
  
  message_first_line "A hostname is needed. This will be a unique name to"
  message_subsequent "identify your device on a network. If you do not enter"
  message_subsequent "one, the default hostname of 'arch-linux' will be used"
  translate "Enter a hostname for your computer"
  title="${Result}: "

  dialog --backtitle "$Backtitle" --title " $title " --ok-label "$Ok" --inputbox "$Message" 15 75 2>output.file
  retval=$?
  Result="$(cat output.file)"

  if [ -z "$Result" ]; then
    HostName="arch-linux"
  else
    HostName=${Result,,}
  fi
  return 0
}

function type_of_installation { # User chooses between FelizOB, self-build or basic

  message_first_line "Feliz now offers you a choice. You can ..."
  translate "Build your own system, by picking the"
  Message="${Message}\n\n1) ${Result}"
  translate "software you wish to install"
  Message="${Message}\n${Result}\n\n               ... ${Tor} ...\n"
  translate "You can choose the new FelizOB desktop, a"
  Message="${Message}\n2) ${Result}"
  translate "complete lightweight system built on Openbox"
  Message="${Message}\n${Result}\n\n               ... ${Tor} ...\n"
  translate "Just install a basic Arch Linux"
  Message="${Message}\n3) ${Result}\n"
  
  translate "Build_My_Own"
  BMO="$Result"
  translate "FelizOB_desktop"
  FOB="$Result"
  translate "Basic_Arch_Linux"
  BAL="$Result"
  
  dialog --backtitle "$Backtitle" --title " type_of_installation " \
    --ok-label "$Ok" --cancel-label "$Cancel" --menu "$Message" \
      24 70 3 \
      1 "$BMO" \
      2 "$FOB" \
      3  "$BAL" 2>output.file
  if [ $? -ne 0 ]; then return 1; fi
  Result=$(cat output.file)

  case $Result in
    1) pick_category
      if [ $? -ne 0 ]; then return 1; fi ;;
    2) DesktopEnvironment="FelizOB"
      Scope="Full" ;;
    *) Scope="Basic"
  esac
  return 0
}

function pick_category { # menu_dialog of categories of selected items from the Arch repos

  translate "Added so far"
  AddedSoFar="$Result"
  translate "Done"
  Done="$Result"
  # translate the categories
  TransCatList=""
  for category in $CategoriesList; do
    translate "$category"
    TransCatList="$TransCatList $Result"
  done
  # Display categories, adding more items until user exits by <Done>
  LuxuriesList=""
  while true; do
    # Prepare information messages
    if [ -z "$LuxuriesList" ]; then
      message_first_line "Now you have the option to add extras, such as a web browser"
      Message="\n${Message}"
      message_subsequent "desktop environment, etc, from the following categories"
    fi
    # Display categories as numbered list
    title="Arch Linux"
    menu_dialog_variable="${TransCatList}"

    # Prepare array for display
    declare -a ItemList=()                                    # Array will hold entire list
    Items=0
    Counter=1
    for Item in $menu_dialog_variable; do                      # Read items from the variable
      Items=$((Items+1))
      ItemList[${Items}]="${Counter}"                         # and copy each one to the array
      Counter=$((Counter+1))
      Items=$((Items+1))
      ItemList[${Items}]="${Item}"                            # Second element is required
    done
     
    # Display the list for user-selection
    dialog --backtitle "$Backtitle" --title " $title " --no-tags --ok-label "$Ok" --cancel-label "$Done" --menu \
        "$Message" \
        20 70 ${Items} "${ItemList[@]}" 2>output.file
    retval=$?
    Result=$(cat output.file)
    
    # Process exit variables
    if [ $retval -ne 0 ]; then
      if [ -n "${LuxuriesList}" ]; then
        Scope="Full"
      else
        Scope="Basic"
      fi
      break
    else
      Category=$Result
      choose_extras                                   # Function to add items to LuxuriesList
      if [ -n "$LuxuriesList" ]; then
        translate "Added so far"
        Message="$Result: ${LuxuriesList}\n"
        message_subsequent "You can now choose from any of the other lists"
      fi
    fi
  done

  for i in $LuxuriesList; do                          # Run through list
    Check=$(echo "$Desktops" | grep $i)               # Test if a DE
    if [ -n "$Check" ]; then                          # This is just to set a primary DE variable
      DesktopEnvironment="$i"                         # Add as DE
      if [ "$DesktopEnvironment" = "Gnome" ]; then    # Gnome installs own DM, so break after adding
        DisplayManager=""
        break
      fi
    fi
  done
  return 0
}

function choose_extras { # Called by pick_category after a category has been chosen.
  # Prepares to call 'display_extras' function with copy data
  translate "Added so far"
  Message="$Result: ${LuxuriesList}\n"
  message_subsequent "You can add more items, or select items to delete"
  title="${Categories[$Category]}" # $Category is number of item in CategoriesList
  
  local Counter=1
  MaxLen=0
  case $Category in
  1) # Create a copy of the list of items in the category
      Copycat="${Accessories}"
      # Pass the name of the relevant array to the translate_category function
      display_extras "LongAccs" ;;
  2) # Create a copy of the list of items in the category
      Copycat="${Desktops}"
      # Pass the name of the relevant array to the translate_category function
      display_extras "LongDesk" ;;
  3) # Create a copy of the list of items in the category
      Copycat="${Graphical}"
      # Pass the name of the relevant array to the translate_category function
      display_extras "LongGraph" ;;
  4) # Create a copy of the list of items in the category
      Copycat="${Internet}"
      # Pass the name of the relevant array to the translate_category function
      display_extras "LongNet" ;;
  5) # Create a copy of the list of items in the category
      Copycat="${Multimedia}"
      # Pass the name of the relevant array to the translate_category function
      display_extras "LongMulti" ;;
  6) # Create a copy of the list of items in the category
      Copycat="${Office}"
      # Pass the name of the relevant array to the translate_category function
      display_extras "LongOffice" ;;
  7) # Create a copy of the list of items in the category
      Copycat="${Programming}"
      # Pass the name of the relevant array to the translate_category function
      display_extras "LongProg" ;;
  8) # Create a copy of the list of items in the category
      Copycat="${WindowManagers}"
      # Pass the name of the relevant array to the translate_category function
      display_extras "LongWMs" ;;
  9) # Create a copy of the list of items in the category
      Copycat="${Taskbars}"
      # Pass the name of the relevant array to the translate_category function
      display_extras "LongBars" ;;
  *) return 0
  esac
  return 0
}

function display_extras { # Called by choose_extras
  # translates descriptions of items in the selected category
  # Then displays them for user to select multiple items
  # Note1: The name of the array to be processed has been passed as $1
  # Note2: A copy of the list of items in the category has been created
  # by the calling function as 'Copycat'
  
  # Get the array passed by name ...
    local name=$1[@]
    local CopyArray=("${!name}")    # eg: LongAccs or LongDesk, etc
  # Prepare temporary array for translated item descriptions
    declare -a TempArray=()
  # translate all elements
    type_of_installationCounter=0
    for Option in "${CopyArray[@]}"; do
      (( type_of_installationCounter+=1 ))
      translate "$Option"
      CopyArray[${type_of_installationCounter}]="$Result" # Replace element with translation
    done
    # Then build the temporary array for the checklist dialog
    local Counter=0
    local CopyCounter=0
    for i in ${Copycat}; do
      (( Counter+=1 ))
      TempArray[${Counter}]="$i"
      (( Counter+=1 ))
      (( CopyCounter+=1 ))
      TempArray[${Counter}]="${CopyArray[${CopyCounter}]}"
      (( Counter+=1 ))
      TempArray[${Counter}]="OFF"
      for a in ${LuxuriesList}; do                        # Check against LuxuriesList
        if [ "$a" = "$i" ]; then                          # If on list, mark ON
          TempArray[${Counter}]="ON"
        fi
      done
    done
    # Remove all items in this group from LuxuriesList (selected items will be added back)
    if [ -n "$LuxuriesList" ]; then
      for i in ${Copycat}; do
        LuxuriesList="${LuxuriesList//${i} }"
      done
    fi
    # Display the contents of the temporary array in a Dialog menu
    Items=$(( Counter/3 ))
    
    dialog --backtitle "$Backtitle" --title " $title " --ok-label "$Ok" --no-cancel --checklist \
      "$Message" 20 79 $Items "${TempArray[@]}" 2>output.file
    retval=$?
    Result=$(cat output.file)
    # Add selected items to LuxuriesList
    LuxuriesList="$LuxuriesList $Result"
    LuxuriesList=$( echo "$LuxuriesList" | sed "s/^ *//")        # Remove any leading spaces caused by deletions
  return 0
}

function choose_display_manager {
  Counter=0
  translate "Display Manager"
  title="$Result"
  message_first_line "A display manager provides a graphical login screen."
  message_subsequent "If in doubt, choose"
  Message="$Message LightDM"
  message_subsequent "If you do not install a display manager, you will"
  message_subsequent "have to launch your desktop environment manually"
  
  dialog --backtitle "$Backtitle" --title " $title " \
    --ok-label "$Ok" --cancel-label "$Cancel" --no-tags --menu "\n$Message" 20 75 6 \
    "gdm" "GDM" \
    "lightdm" "LightDM" \
    "lxdm" "LXDM" \
    "sddm" "SDDM" \
    "slim" "SLIM" \
    "xdm" "XDM" 2> output.file
  if [ $? -ne 0 ]; then return; fi
  DisplayManager="$(cat output.file)"
}

function select_grub_device {
  
  GrubDevice=""
  while [ -z $GrubDevice ]; do
    DevicesList="$(lsblk -d | awk '{print "/dev/" $1}' | grep 'sd\|hd\|vd')"  # Preceed field 1 with '/dev/'
    # Add an option to enter grub device manually
    translate "Enter_Manually"
    Enter_Manually="$Result"
    menu_dialog_variable="$DevicesList $Result"
    title="Grub"
    local Counter=0
    message_first_line "Select the device where Grub is to be installed"
    message_subsequent "Note that if you do not select a device, Grub"
    message_subsequent "will not be installed, and you will have to make"
    message_subsequent "alternative arrangements for booting your new system"

    menu_dialog  20 60 # (arguments are dialog size) displays a menu and returns $retval and $Result
    if [ "$Result" = "$Enter_Manually" ]; then				# Call function to type in a path
      enter_grub_path
      GrubDevice="$Result"
    else
      GrubDevice="$Result"
    fi
  done
}

function enter_grub_path { # Manual input

  GrubDevice=""
  while [ -z "$GrubDevice" ]; do
    message_first_line "You have chosen to manually enter the path for Grub"
    message_subsequent "This should be in the form /dev/sdx or similar"
    message_subsequent "Only enter a device, do not include a partition number"
    message_subsequent "If in doubt, consult"
    message_subsequent "https://wiki.archlinux.org/index.php/GRUB"
    
    dialog_inputbox 15 65    # text input dialog
    if [ $retval -eq 0 ]; then return; fi
    Entered=${Result,,}
    # test input
    CheckGrubEntry="${Entered:0:5}"
    if [ -z "$Entered" ]; then
      return 1
    elif [ "$CheckGrubEntry" != "/dev/" ]; then
      not_found "$Entered is not in the correct format"
    else
      GrubDevice="${Entered}"
    fi
  done
  return 0
}

function select_kernel {
  
  Kernel=0
  until [ "$Kernel" -ne 0 ]
  do
    translate "Choose your kernel"
    title="$Result"
    translate "The Long-Term-Support kernel (LTS) offers stabilty"
    LTS="$Result"
    translate "The Latest kernel has all the new features"
    Latest="$Result"
    translate "If in doubt, choose"
    Default="${Result} LTS"
  
    dialog --backtitle "$Backtitle" --title "$title" \
      --ok-label "$Ok" --no-cancel --no-tags --menu "\n  $Default" 10 70 2 \
      "1" "$LTS" \
      "2" "$Latest" 2>output.file
    retval=$?
    Result=$(cat output.file)
    if [ $retval -ne 0 ] || [ -z "$Result" ] || ([ "$Result" -ne 1 ] && [ "$Result" -ne 2 ]); then
      Kernel=1  # Set the Kernel variable (1 = LTS; 2 = Latest)
    else
      Kernel="$Result"
    fi
  done
  return 0
}

function choose_mirrors { # Called without arguments by feliz.sh/the_start
                          # User selects a country with Arch Linux mirrors
  Country=""
  while [ -z "$Country" ]; do
  
    # 1) Prepare files of official Arch Linux mirrors
      # Download latest list of Arch Mirrors to temporary file
      title=" archmirrors.list "
      curl -s https://www.archlinux.org/mirrorlist/all/http/ > archmirrors.list
      if [ $? -ne 0 ]; then
        message_first_line "Unable to fetch list of mirrors from Arch Linux"
        message_subsequent "Using the list supplied with the Arch iso"
        dialog --backtitle "$Backtitle" --ok-label "$Ok" --msgbox "\n${Message}\n" 8 75
        cp /etc/pacman.d/mirrorlist > archmirrors.list
      fi
      # Get line number of first country
      FirstLine=$(grep -n "Australia" archmirrors.list | head -n 1 | cut -d':' -f1)
      # Remove text prior to FirstLine and save in new file
      tail -n +"$FirstLine" archmirrors.list > allmirrors.list
      rm archmirrors.list
      # Create list of countries from allmirrors.list, using '##' to identify
      #                        then removing the '##' and leading spaces
      #                                       and finally save to new file for reference by dialog
      grep "## " allmirrors.list | tr -d "##" | sed "s/^[ \t]*//" > list.file
      
    # 2) Display instructions and user selects from list of countries
      message_first_line "Next we will select mirrors for downloading your system."
      message_subsequent "You will be able to choose from a list of countries which"
      message_subsequent "have Arch Linux mirrors."
      
      dialog --backtitle "$Backtitle" --ok-label "$Ok" --msgbox "\n${Message}\n" 10 75
  
      message_first_line "Please choose a country"

      declare -a ItemList=()                                # Array will hold entire list
      Items=0
      while read -r Item; do                              # Read items from the file
                                                          # and copy each one to the array
        Items=$((Items+1))
        ItemList[${Items}]="${Item}"                      # First element is tag
        Items=$((Items+1))
        ItemList[${Items}]="${Item}"                      # Second element is required
      done < list.file

      dialog --backtitle "$Backtitle" --title " $title " \
        --ok-label "$Ok" --cancel-label "$Cancel" --no-tags --menu "$Message" \
        25 60 ${Items} "${ItemList[@]}" 2>output.file
      retval=$?
      Result=$(cat output.file)                                   # eg: United Kingdom
      rm list.file
      Country="$Result"
      if [ "$Country" = "" ]; then
        edit_mirrors
        retval=$?
        if [ $retval -eq 2 ]; then
          break
        else
          Country=""
        fi 
      else   
        # Add to array for use during installation
        Counter=0
        for Item in $(cat output.file); do                        # Read items from the output.file
          Counter=$((Counter+1))                                  # and copy each one to the array
          CountryLong[${Counter}]="$Item"                         # CountryLong is declared in f-vars.sh
        done
        if [ $Counter -lt 1 ]; then Country=""; fi
      fi
  done
  return 0
}

function edit_mirrors { # Called without arguments by choose_mirrors
                        # Use Nano to edit mirrors.list
                        # Returns 0 if completed, 1 if interrupted, 2 if worldwide mirror selected
  message_first_line "Feliz needs at least one mirror from which to"
  message_subsequent "download the Arch Linux system and applications"
  message_subsequent "If you do not wish to use one from the Arch list"
  message_subsequent "you can enter the address of a mirror manually, or"
  message_subsequent "you can use one of the worldwide Arch Linux mirrors"
  message_subsequent "although this may be slower than a local mirror"
  translate "Mirrors"
  title="$Result"
  translate "I want to type in an address"
  Menu1="$Result"
  translate "Use a worldwide mirror"
  Menu2="$Result"
  translate "Return to the list"
  Menu3="$Result"
  
  dialog --backtitle "$Backtitle" --title " $title " \
    --ok-label "$Ok" --cancel-label "$Cancel" --no-tags --no-cancel --menu "$Message" \
      18 65 ${Items} \
      "Manual" "$Menu1" \
      "Worldwide" "$Menu2" \
      "Standard" "$Menu3" 2>output.file
  retval=$?
  Result=$(cat output.file)
  case $Result in
  "Manual") echo "# eg: Server = http://mirror.transip.net/archlinux/" > mirrors.list
    #  nano mirrors.list
    dialog --exit-label "$Done" \
      --textbox "# eg: Server = http://mirror.transip.net/archlinux/" mirrors.list 18 65
      return 2 ;;
  "Worldwide") echo "# eg: Server = http://mirror.transip.net/archlinux/" > mirrors.list
      echo "Server = http://mirrors.evowise.com/archlinux/$repo/os/$arch" >> mirrors.list
      return 2 ;;
  *) return 1
  esac
  return 0
}

function confirm_virtualbox { # Called without arguments by feliz.sh/the_start
  message_first_line "Install Virtualbox guest utilities?"
  title="Virtualbox"
    
  dialog --backtitle "$Backtitle" --title " $title " \
    --yes-label "$Yes" --no-label "$No" --yesno "\n$Message" 7 60

  if [ $? -eq 0 ]; then  # Yes
    IsInVbox="VirtualBox"
  else                   # No
    IsInVbox=""
  fi
  return 0
}

function final_check {  # Called without arguments by feliz.sh/the_start
                        # Display all user settings before starting installation
                        # Returns 0 if completed or 1 if cancelled
  while true; do
    clear
    echo
    translate "These are the settings you have entered."
    print_first_line "$Result"
    translate "Please check them before Feliz begins the installation"
    print_first_line "$Result"
    echo
    translate "Zone/subZone will be"
    print_subsequent "1) $Result $ZONE/$SUBZONE"
    translate "Locale will be set to"
    print_subsequent "2) $Result $CountryLocale"
    translate "Keyboard is"
    print_subsequent "3) $Result $Countrykbd"
    case ${IsInVbox} in
    "VirtualBox") translate "Yes"
      print_subsequent "4) Virtualbox Guest Modules: $Result" ;;
    *) translate "No"
      print_subsequent "4) Virtualbox Guest Modules: $Result"
    esac
    if [ -n "$DesktopEnvironment" ] && [ "$DesktopEnvironment" = "FelizOB" ]; then
      translate "Display Manager"
      print_subsequent "5) $Result = FelizOB"
    elif [ -z "$DisplayManager" ]; then
      translate "No Display Manager selected"
      print_subsequent "5) $Result"
    else
      translate "Display Manager"
      print_subsequent "5) $Result = $DisplayManager"
    fi
    translate "Root and user settings"
    print_subsequent "6) $Result ..."
    translate "Hostname"
    print_subsequent "      $Result = $HostName"
    translate "User Name"
    print_subsequent "      $Result = $user_name"
    translate "The following extras have been selected"
    print_subsequent "7) $Result ..."
    SaveStartPoint="$EMPTY" # Save cursor start point
    if [ "$Scope" = "Basic" ]; then
      translate "None"
      print_first_line "$Result"
    elif [ -n "$DesktopEnvironment" ] && [ "$DesktopEnvironment" = "FelizOB" ]; then
      print_first_line "FelizOB"
    elif [ -z "$LuxuriesList" ]; then
      translate "None"
      print_first_line "$Result "
    else
      translate="N"
      print_first_line "${LuxuriesList}"
      translate="Y"
    fi
    EMPTY="$SaveStartPoint" # Reset cursor start point
    # 8) Kernel
    translate "Kernel"
    if [ -n "$Kernel" ] && [ "$Kernel" -eq 1 ]; then
      print_subsequent "8) $Result = 'LTS'"
    else
      print_subsequent "8) $Result = 'Latest'"
    fi
    # 9) Grub
    translate "Grub will be installed on"
    print_subsequent "9) $Result : '$GrubDevice'"
    # 10) Cancel
    translate "Cancel installation"
    print_subsequent "10) $Result"
    # 11) Partitions
    translate "The following partitions have been selected"
    print_subsequent "11) $Result ..."
    translate "partition"
    translate="N"
    print_first_line "${RootPartition} /root ${RootType}"
    print_subsequent "${HomePartition} /home ${HomeType}"
    print_subsequent "${SwapPartition} /swap"
    echo
    # Prompt user for a number
    translate="Y"
    Response=20
    translate "Press Enter to install with these settings, or"
    print_first_line "$Result"
    translate "Enter number for data to change"

    local T_COLS=$(tput cols)
    local lov=${#Result}
    stpt=0
    if [ "$lov" -lt "$T_COLS" ]; then
      stpt=$(( (T_COLS - lov) / 2 ))
    elif [ "$lov" -gt "$T_COLS" ]; then
      stpt=0
    else
      stpt=$(( (T_COLS - 10) / 2 ))
    fi
    EMPTY="$(printf '%*s' $stpt)"
    read -p "$EMPTY $Result : " Change
    case $Change in
      1) set_timezone ;;
      2) setlocale ;;
      3) get_keymap ;;
      4) confirm_virtualbox ;;
      5) DisplayManager=""
         choose_display_manager ;;
      6) manual_settings ;;
      7) pick_category ;;
      8) select_kernel
         if [ $? -ne 0 ]; then return $?; fi ;;
      9) if [ "$GrubDevice" != "EFI" ]; then  # Can't be changed if EFI
          select_grub_device
          if [ $? -ne 0 ]; then return $?; fi
         fi ;;
      10) return 1 ;;                         # Low-level backout
      11) AddPartList=""                      # Empty the lists of extra partitions
        AddPartMount=""
        AddPartType=""
        autopart="MANUAL"
        check_parts                           # Update lists
        if [ $? -ne 0 ]; then return $?; fi
        allocate_partitions
        if [ $? -ne 0 ]; then return $?; fi ;;
      *) break
    esac
  done
  return 0
}

function manual_settings {  # Called without arguments by final_check if
                            # User elected to change hostname or username
                            # Sets $user_name and/or $HostName
  while true; do
    translate "Hostname"
    Hname="$Result"
    translate "User Name"
    Uname="$Result"
    message_first_line "Choose an item"
    dialog --backtitle "$Backtitle" --title " $Uname & $Hname "
      --ok-label "$Ok" --cancel-label "Done" --menu "\n$Message" 10 40 2 \
      "$Uname"  "$user_name" \
      "$Hname" 	"$HostName"   2> output.file
    retvar=$?
    if [ $retvar -ne 0 ]; then return; fi
    Result="$(cat output.file)"

    case $Result in
      "$Uname") translate "Enter new username (currently"
          Message="$Result ${user_name})"
          title="$Uname"
          dialog_inputbox 10 30
          if [ "$retvar" -ne 0 ]; then return; fi
          if [ -z "$Result" ]; then
           Result="$user_name"
          fi
          user_name=${Result,,}
          user_name=${user_name// }             # Ensure no spaces
          user_name=${user_name%% } ;;
      "$Hname") translate "Enter new hostname (currently"
          Message="$Result ${HostName})"
          title="$Uname"
          dialog_inputbox 10 30
          if [ $retvar -ne 0 ]; then return; fi
          if [ -z "$Result" ]; then
           Result="$HostName"
          fi
          HostName=${Result,,}
          HostName=${HostName// }             # Ensure no spaces
          HostName=${HostName%% } ;;
      *) return 0
    esac
  done
  return 0
}

function wireless_option { # Called without arguments by feliz.sh/the_start
  message_first_line  "Install wireless tools?"
  translate "Wifi Option"
  title="$Result"
    
  dialog --backtitle "$Backtitle" --title " $title " \
    --yes-label "$Yes" --no-label "$No" --yesno "\n$Message" 7 60

  if [ $? -eq 0 ]; then  # Yes
    WirelessTools="Y"
  else                   # No
    WirelessTools="N"
  fi
  return 0
}
