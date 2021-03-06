#!/bin/bash

# The Feliz2 installation scripts for Arch Linux
# Developed by Elizabeth Mills
# With grateful acknowlegements to Helmuthdu, Carl Duff and Dylan Schacht
# Revision date: 8th January 2018

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

# In this module: functions used during installation
# ---------------------------    ---------------------------
# Functions             Line     Functions              Line
# --------------------------    ---------------------------
# arch_chroot             43    install_kernel          332
# parted_script           47    add_codecs              370
# install_message         51    mirror_list             405
# action_MBR              59    install_display_manager 459
# action_EFI             102    install_extras          473
# root_partition         165    install_yaourt          567
# swap_partition         182    user_add                589
# home_partition         199    check_existing          652
# remove_partitions      208    set_root_password       659
# autopart               231    set_user_password       714
# partition_maker        779    
# mount_partitions       261    finish                  760
# --------------------------    ---------------------------

function arch_chroot { # From Lution AIS - calls arch-chroot with options
  arch-chroot /mnt /bin/bash -c "${1}" 2>> feliz.log
}

function parted_script { # Calls GNU parted tool with options
  parted --script "/dev/${UseDisk}" "$1" 2>> feliz.log
}

function install_message { # For displaying status while running on auto
  echo
  tput bold
  print_first_line "$1" "$2" "$3"
  tput sgr0
  echo
}

function action_MBR { # GUIDED BIOS/MBR (if AutoPartition flag is "GUIDED")
                      # Called by feliz.sh before other partitioning actions
                      # Uses variables set by user to create partition
                      # table & all partitions
                      # Called without arguments
  local Unit
  local EndPoint
  declare -i Chars
  declare -i Var
  declare -i EndPart
  declare -i NextStart

  remove_partitions                     # Delete existing partitions for AUTO & GUIDED
  
  # Root partition
    root_partition                      # Calculate endpoint for this partition
    parted_script "mkpart primary ${RootType} 1MiB ${EndPoint}" # Make the partition
    parted_script "set 1 boot on"
    RootPartition="${RootDevice}1"      # "/dev/sda1"
    local NextStart=${EndPart}          # Save for next partition. Numerical only (has no unit)
  # Swap partition
    if [ -n "$SwapSize" ]; then
      swap_partition                    # Calculate endpoint for this partition
      parted_script "mkpart primary linux-swap ${NextStart}MiB ${EndPoint}" # Make the partition
      SwapPartition="${RootDevice}2"    # "/dev/sda2"
      MakeSwap="Y"
      NextStart=${EndPart}              # Save for next partition. Numerical only (has no unit)
    fi
  # Home partition
    if [ -n "$HomeSize" ]; then
      home_partition                    # Calculate endpoint for this partition
      parted_script "mkpart primary ${HomeType} ${NextStart}MiB ${EndPoint}" # Make the partition
      HomePartition="${RootDevice}3"    # "/dev/sda4"
      Home="Y"
      AddPartList[0]="${RootDevice}3"   # /dev/sda3     | add to
      AddPartMount[0]="/home"           # Mountpoint    | array of
      AddPartType[0]="${HomeType}"      # Filesystem    | additional partitions
    fi
}

function action_EFI { # GUIDED EFI/GPT (if AutoPartition flag is "GUIDED")
                      # Called by feliz.sh before other partitioning actions
                      # Uses variables set by user to create partition
                      # table & all partitions
                      # Called without arguments

  if [ "$UEFI" -eq 1 ]; then return 0; fi # Option disabled
                      
  local Unit
  local EndPoint
  declare -i Chars
  declare -i Var
  declare -i EndPart
  declare -i NextStart

  remove_partitions                     # Delete existing partitions for AUTO & GUIDED

  # Boot partition - calculate end-point, then create the partition as #1
    Unit=${BootSize: -1}                # Save last character of boot (eg: M)
    Chars=${#BootSize}                  # Count characters in boot variable
    Var=${BootSize:0:Chars-1}           # Remove unit character from boot variable
    if [ "$Unit" = "G" ]; then
      Var=$((Var*1024))                 # Convert to MiB
    fi
    EndPoint=$((Var+1))                 # Add start and finish. Result is MiBs, numerical only (has no unit)
    parted_script "mkpart primary fat32 1MiB ${EndPoint}MiB"
    parted_script "set 1 boot on"
    EFIPartition="${RootDevice}1"       # "/dev/sda1"
    NextStart=${EndPoint}               # Save for next partition. Numerical only (has no unit)

  # Root partition
    root_partition                      # Calculates end point
    parted_script "mkpart primary ${RootType} ${NextStart}MiB ${EndPoint}" # Make the partition
    RootPartition="${RootDevice}2"      # "/dev/sda2"
    NextStart=${EndPart}                # Save for next partition. Numerical only (has no unit)

  # Swap partition
    if [ -n "$SwapSize" ]; then
      swap_partition                    # Calculates end point
      parted_script "mkpart primary linux-swap ${NextStart}MiB ${EndPoint}" # Make the partition
      SwapPartition="${RootDevice}3"    # "/dev/sda3"
      MakeSwap="Y"
      NextStart=${EndPart}              # Save for next partition. Numerical only (has no unit)
    fi

  # Home partition
    if [ -n "$HomeSize" ]; then
      home_partition                    # Calculates end point
      parted_script "mkpart primary ${HomeType} ${NextStart}MiB ${EndPoint}" # Make the partition
      HomePartition="${RootDevice}4"    # "/dev/sda4"
      Home="Y"
      AddPartList[0]="${RootDevice}4"   # /dev/sda4     | add to
      AddPartMount[0]="/home"           # Mountpoint    | array of
      AddPartType[0]="${HomeType}"      # Filesystem    | additional partitions
    fi
}

function root_partition { # Called by action_EFI and action_MBR
                          # Calculate end-point based on size set by user
  Unit=${RootSize: -1}                # Save last character of root (eg: G)
  Chars=${#RootSize}                  # Count characters in root variable
  Var=${RootSize:0:Chars-1}           # Remove unit character from root variable
  if [ "$Unit" = "G" ]; then
    Var=$((Var*1024))                 # Convert to MiB
    EndPart=$((NextStart+Var))        # Add to previous end
    EndPoint="${EndPart}MiB"          # Add unit
  elif [ "$Unit" = "M" ]; then
    EndPart=$((NextStart+Var))        # Add to previous end
    EndPoint="${EndPart}MiB"          # Add unit
  elif [ "$Unit" = "%" ]; then
    EndPoint="${Var}%"
  fi
}
  
function swap_partition { # Calculate end-point
  Unit=${SwapSize: -1}              # Save last character of swap (eg: G)
  Chars=${#SwapSize}                # Count characters in swap variable
  Var=${SwapSize:0:Chars-1}         # Remove unit character from swap variable
  if [ "$Unit" = "G" ]; then
    Var=$((Var*1024))               # Convert to MiB
    EndPart=$((NextStart+Var))      # Add to previous end
    EndPoint="${EndPart}MiB"        # Add unit
  elif [ "$Unit" = "M" ]; then
    EndPart=$((NextStart+Var))      # Add to previous end
    EndPoint="${EndPart}MiB"        # Add unit
  elif [ "$Unit" = "%" ]; then
    EndPoint="${Var}%"
  fi
}

function home_partition { # Calculate end-point
  Unit=${HomeSize: -1}              # Save last character of home (eg: G)
  Chars=${#HomeSize}                # Count characters in home variable
  Var=${HomeSize:0:Chars-1}         # Remove unit character from home variable
  if [ "$Unit" = "G" ]; then
    Var=$((Var*1024))               # Convert to MiB
    EndPart=$((NextStart+Var))      # Add to previous end
    EndPoint="${EndPart}MiB"        # Add unit
  elif [ "$Unit" = "M" ]; then
    EndPart=$((NextStart+Var))      # Add to previous end
    EndPoint="${EndPart}MiB"        # Add unit
  elif [ "$Unit" = "%" ]; then
    EndPoint="${Var}%"
  fi
}

function remove_partitions { # Delete existing partitions for AUTO & GUIDED
                                                                  
  table=$(parted "/dev/${UseDisk}" print | grep 'Partition Table' | grep unknown) # Test if partition table exists
                                                                          # eg: "Partition Table: unknown"
  if [ -n "$table" ] ; then                                               # If device has no table, make one
    if [ "$UEFI" -eq 1 ]; then
      parted_script "mklabel gpt"                                         # On EFI
    else
      parted_script "mklabel msdos"                                       # On BIOS
    fi
  else
    HowMany=$(lsblk -l | grep "$UseDisk" | grep -v "${UseDisk} " | wc -l)	# Count existing partitions (eg: 6 or 0)
    if [ "$HowMany" -gt 0 ]; then                                         # If more than one existing partition

      for p in $(lsblk -l | grep sda | grep -v "sda " | cut -c1-5)
      do
        umount "/dev/${p}"                                                # Try to unmount any mounted partitions
      done

      for i in $(seq 1 $HowMany)
      do
        parted_script "rm $i"                                             # Use parted to remove each one
      done
    else
      return 1                                                            # Unlikely event that there is no device
    fi
  fi
}

function autopart { # Called by feliz.sh/preparation during installation phase
                    # if AutoPartition flag is AUTO.
                    # Consolidated automatic partitioning for BIOS

  if [ "$UEFI" -eq 1 ]; then return 0; fi # Option disabled
                    
  Root="${RootDevice}"
  Home="N"                                            # No /home partition at this point
  DiskSize=$(lsblk -l | grep "${UseDisk}\ " | awk '{print $4}' | sed "s/G\|M\|K//g") # Get disk size

  remove_partitions                                   # Delete existing partitions for AUTO & GUIDED

  if [ "$UEFI" -eq 1 ]; then                          # If installing on EFI
    parted_script "mkpart primary fat32 1MiB 513MiB"  # Create EFI boot partition
    StartPoint="513MiB"                               # Start point for next GPT partition
  else
    StartPoint="1MiB"                                 # Start point for next MBR partition
  fi
                    # Decide partition sizes then make each partition
                    # startpoint : rootsize : homesize : swapsize
  if [ "$DiskSize" -ge 40 ]; then                     # ------ /root /home /swap partitions ------ #
    HomeSize=$((DiskSize-15-4))                       # /root 15 GiB, /swap 4GiB, /home from 18GiB
    partition_maker "${StartPoint}" "15GiB" "${HomeSize}GiB" "100%"
  elif [ "$DiskSize" -ge 30 ]; then                   # ------ /root /home /swap partitions ------ #
    HomeSize=$((DiskSize-15-3))                       # /root 15 GiB, /swap 3GiB, /home 12 to 22GiB
    partition_maker "${StartPoint}" "15GiB" "${HomeSize}GiB" "100%"
  elif [ "$DiskSize" -ge 18 ]; then                   # ----- /root & /swap partitions only ------ #
    RootSize=$((DiskSize-2))                          # /root 16 to 28GiB, /swap 2GiB
    partition_maker "${StartPoint}" "${RootSize}GiB" "" "100%"
  elif [ "$DiskSize" -gt 10 ]; then                   # ----- /root & /swap partitions only ------ #
    RootSize=$((DiskSize-1))                          # /root 9 to 17GiB, /swap 1GiB
    partition_maker "${StartPoint}" "${RootSize}GiB" "" "100%"
  else                                                # --- Swap file and /root partition only --- #
    partition_maker "${StartPoint}" "100%" "" ""
    SwapFile="2G"                                     # Swap file
    SwapPartition=""                                  # Clear swap partition variable
  fi
  partprobe 2>> feliz.log                             # Inform kernel of changes to partitions
}

function partition_maker {  # Called from autopart for and BIOS systems
                            # Uses GNU Parted to create partitions as defined by autopart
                            # Receives up to 4 arguments
  local StartPoint=$1       #   $1 is the starting point of the first partition
                            #   $2 is size of root partition
                            #   $3 if passed is size of home partition
                            #   $4 if passed is size of swap partition
                            # Appropriate partition table has already been created in remove_partitions
                            # If EFI the /boot partition has also been created at /dev/sda1
                            # and the startpoint has been set to follow /boot

  if [ "$UEFI" -eq 1 ]; then return 0; fi                 # Option disabled for UEFI
                            
                                                          # Set the device to be used to 'set x boot on'    
  MountDevice=1                                           # $MountDevice is numerical - eg: 1 is sda1
                                                          # Start with first partition = [sda]1
  parted_script "mkpart primary ext4 ${StartPoint} ${2}"  # Make / at startpoint
                                                          # eg: parted /dev/sda mkpart primary ext4 1MiB 12GiB
  parted_script "set 1 boot on"                           # For autopart, /boot is always 1
                                                          # eg: parted /dev/sda set 1 boot on
                                                          
  if [ "$UEFI" -eq 1 ]; then                              # In EFI environment
    MountDevice=2                                         # Next partition after /boot = [sda]2
  fi
  RootPartition="${RootDevice}${MountDevice}"             # eg: /dev/sda1
  RootType="ext4"
  StartPoint=$2                                           # Increment startpoint for /home or /swap
  MountDevice=$((MountDevice+1))                          # Advance partition numbering for next step

  if [ -n "$3" ]; then
    parted_script "mkpart primary ext4 ${StartPoint} ${3}" # eg: parted /dev/sda mkpart primary ext4 12GiB 19GiB
    AddPartList[0]="${RootDevice}${MountDevice}"          # eg: /dev/sda3  | add to
    AddPartMount[0]="/home"                               # Mountpoint     | array of
    AddPartType[0]="ext4"                                 # Filesystem     | additional partitions
    Home="Y"
    StartPoint=$3                                         # Reset startpoint for /swap
    MountDevice=$((MountDevice+1))                        # Advance partition numbering
  fi

  if [ -n "$4" ]; then
    parted_script "mkpart primary linux-swap ${StartPoint} ${4}" # eg: parted /dev/sda mkpart primary linux-swap 31GiB 100%
    SwapPartition="${RootDevice}${MountDevice}"
    MakeSwap="Y"
  fi
}

function mount_partitions { # Format and mount each partition as defined by MANUAL, AUTO or GUIDED
                            # Called without arguments by feliz.sh after autopart, action_MBR or action_EFI
  
  install_message "Preparing and mounting partitions"

  # 1) Root partition
    umount "$RootPartition"
    mount "$RootPartition" /mnt 2>> feliz.log                         # eg: mount /dev/sda1 /mnt

  # 2) EFI (if required)
    if [ "$UEFI" -eq 1 ] && [ "$DualBoot" = "N" ]; then               # Check if /boot partition required
      umount "$EFIPartition"
    #  mkfs.vfat -F32 "$EFIPartition" # 2>> feliz.log                 # Format EFI boot partition ... disabled
      mkdir -p /mnt/boot                                              # Make mountpoint
      mount -t efivarfs efivarfs /sys/firmware/efi/efivars 2> feliz.log
      mount "$EFIPartition" /mnt/boot                                 # eg: mount /dev/sda2 /mnt/boot
    fi
  # 3) Swap
    if [ -n "$SwapPartition" ]; then
      swapoff -a 2>> feliz.log                                        # Make sure any existing swap cleared
      if [ "$MakeSwap" = "Y" ] && [ "$UEFI" -ne 1 ]; then
        Partition=${SwapPartition: -4}                                # Last 4 characters (eg: sda2)
        Label="${Labelled[${Partition}]}"                             # Check for label
        if [ -n "$Label" ]; then
          Label="-L ${Label}"                                         # Prepare label
        fi
        mkswap "$Label" "$SwapPartition" # 2>> feliz.log              # eg: mkswap -L Arch-Swap /dev/sda2
      fi
      swapon "$SwapPartition" # 2>> feliz.log                         # eg: swapon /dev/sda2
    fi
  # 4) Any additional partitions (from the related arrays AddPartList, AddPartMount & AddPartType)
    local Counter=0
    for id in "${AddPartList[@]}"; do                                 # $id will be in the form /dev/sda2
      umount "$id"
      mkdir -p /mnt${AddPartMount[$Counter]} 2>> feliz.log            # eg: mkdir -p /mnt/home

      mount "$id" /mnt${AddPartMount[$Counter]} &>> feliz.log         # eg: mount /dev/sda3 /mnt/home
      Counter=$((Counter+1))
    done
}

function install_kernel { # Called without arguments by feliz.sh
                          # Installs selected kernel and some other core systems
  LANG=C                  # Set the locale for all processes run from the current shell 

  # Solve pacman keys issue if an older Feliz or Arch iso is running after keyring changes
  # Passes test if the date of the running iso is more recent than the date of the latest Arch
  # trust update. Next trust update due 2018:06:25
  # Use blkid to get details of the Feliz or Arch iso that is running, in the form yyyymm
  isodate=$(blkid | grep "feliz\|arch" | cut -d'=' -f3 | cut -d'-' -f2 | cut -b-6)
  TrustDate=201710                                                # Date of latest Arch Linux trust update
  # Next trustdb check 2018-10-20
  if [ "$isodate" -ge "$TrustDate" ]; then                        # If the running iso is more recent than
    echo "pacman-key trust check passed" >> feliz.log             # the last trust update, no action is taken
  else                                                            # But if the iso is older than the last trust
    install_message "Updating keys"                               # update then the keys are updated
    pacman-db-upgrade
    pacman-key --init
    pacman-key --populate archlinux
    pacman-key --refresh-keys
    pacman -Sy --noconfirm archlinux-keyring
  fi
  translate "Installing"
  Message="$Result"
  translate "kernel and core systems"
  install_message "$Message $Result"
  case "$Kernel" in
  1) # This is the full linux group list at 1st August 2017 with linux-lts in place of linux
      # Use the script ArchBaseGroup.sh in FelizWorkshop to regenerate the list periodically
    pacstrap /mnt autoconf automake bash binutils bison bzip2 coreutils cryptsetup device-mapper dhcpcd diffutils e2fsprogs fakeroot file filesystem findutils flex gawk gcc gcc-libs gettext glibc grep groff gzip inetutils iproute2 iputils jfsutils less libtool licenses linux-lts logrotate lvm2 m4 make man-db man-pages mdadm nano netctl pacman patch pciutils pcmciautils perl pkg-config procps-ng psmisc reiserfsprogs sed shadow s-nail sudo sysfsutils systemd-sysvcompat tar texinfo usbutils util-linux vi which xfsprogs 2>> feliz.log ;;
  *) pacstrap /mnt base base-devel 2>> feliz.log
  esac
  translate "cli tools"
  install_message "$Message $Result"
  pacstrap /mnt btrfs-progs gamin gksu gvfs ntp wget openssh os-prober screenfetch unrar unzip vim xarchiver xorg-xedit xterm 2>> feliz.log
  arch_chroot "systemctl enable sshd.service" >> feliz.log
}

function add_codecs { # Called without arguments by feliz.sh
  translate "Installing"
  install_message "$Result codecs"
  pacstrap /mnt a52dec autofs faac faad2 flac lame libdca libdv libmad libmpeg2 libtheora 2>> feliz.log
  pacstrap /mnt libvorbis libxv wavpack x264 gstreamer gst-plugins-base gst-plugins-good 2>> feliz.log
  pacstrap /mnt pavucontrol pulseaudio pulseaudio-alsa libdvdcss dvd+rw-tools dvdauthor dvgrab 2>> feliz.log
  if [ "$WirelessTools" = "Y" ]; then
    translate "Wireless Tools"
    Message="$Result"
    translate "Installing"
    install_message "$Result $Message"
    pacstrap /mnt b43-fwcutter ipw2100-fw ipw2200-fw zd1211-firmware 2>> feliz.log
    pacstrap /mnt iw wireless_tools wpa_supplicant 2>> feliz.log
  fi
  # Note that networkmanager and network-manager-applet are installed separately by feliz.sh
  translate "Graphics tools"
  Message="$Result"
  translate "Installing"
  install_message "$Result $Message"
  pacstrap /mnt xorg xorg-xinit xorg-twm 2>> feliz.log
  translate "opensource video drivers"
  Message="$Result"
  translate "Installing"
  install_message "$Result $Message"
  pacstrap /mnt xf86-video-vesa xf86-video-nouveau xf86-input-synaptics 2>> feliz.log
  translate "fonts"
  Message="$Result"
  translate "Installing"
  install_message "$Result $Message"
  pacstrap /mnt ttf-liberation 2>> feliz.log

  # install_message "Installing  CUPS printer services"
  # pacstrap /mnt -S system-config-printer cups
  # arch_chroot "systemctl enable org.cups.cupsd.service"
}

function mirror_list {  # Use rankmirrors (script in /usr/bin/ from Arch) to generate fast mirror list
                        # User has selected one or more countries with Arch Linux mirrors
                        # These have been stored in the array CountryLong
                        # Now the mirrors associated with each of those countries must be extracted from the array
  install_message "Generating mirrorlist"
  cp /etc/pacman.d/mirrorlist /etc/pacman.d/mirrorlist.safe 2>> feliz.log

  if [ -f mirrors.list ] && [ "$(wc mirrors.list)" -gt 1 ]; then  # If user has entered a manual list of >0 mirrors
    install_message "Ranking mirrors - please wait ..."
    Date=$(date)
    echo -e "# Ranked mirrors /etc/pacman.d/mirrorlist \n# $Date \n# Generated by ${user_name} and rankmirrors\n#" > /etc/pacman.d/mirrorlist
    rankmirrors -n 5 mirrors.list | grep '^Server' >> /etc/pacman.d/mirrorlist
  elif [ ${#CountryLong[@]} -eq 0 ]; then  # If no mirrors were cosen by user ...
    install_message "Ranking mirrors - please wait ..."
    # generate and save a shortened mirrorlist of only the mirrors defined in the CountryCode variable.
    URL="https://www.archlinux.org/mirrorlist/?country=${CountryCode}&use_mirror_status=on"
    MirrorTemp=$(mktemp --suffix=-mirrorlist) 2>> feliz.log
    # Use curl to get list of mirrors from the Arch mirrorlist ${URL} to ${MirrorTemp}
    curl -so "$MirrorTemp" "$URL" 2>> feliz.log
    # Use sed to filter entries
    sed -i 's/^#Server/Server/g' "$MirrorTemp" 2>> feliz.log
    # Make a safe copy of existing mirrorlist
    mv -f /etc/pacman.d/mirrorlist /etc/pacman.d/mirrorlist.orig 2>> feliz.log
    # Replace existing mirrorlist with new local mirrorlist
    mv -f "$MirrorTemp" /etc/pacman.d/mirrorlist 2>> feliz.log
    chmod +r /etc/pacman.d/mirrorlist 2>> feliz.log
  else # Get addresses of mirrors in the country selected by the user
    if [ -f usemirrors.list ]; then rm usemirrors.list; fi
    for Country in "${CountryLong[@]}"; do    # Prepare file of mirrors to be used
        # Get the line number of $Country in $CountryLong in allmirrors.list
        #                      exact match only | restrict to first find | display only number
      CountryLine=$(grep -n "${Country}" allmirrors.list | head -n 1 | cut -d':' -f1)
      # Read each line from that line onwards until an empty line is encountered (end of country)
      while true; do
        CountryLine=$((CountryLine+1))                                                    # Next line
        MirrorURL="$(head -n ${CountryLine} allmirrors.list | tail -n 1 | cut -d'#' -f2)" # Read next item in source file
        echo "$MirrorURL" >> usemirrors.list                                              # Save it to usemirrors.list file
        if [ -z "$MirrorURL" ]; then
          break
        else
          translate "Loading"
          echo "$Result $Country $MirrorURL"
        fi
      done
    done
    translate "Ranking mirrors - please wait"
    install_message "$Result ..."
    Date=$(date)
    echo -e "# Ranked mirrors /etc/pacman.d/mirrorlist \n# $Date \n# Generated by Feliz and rankmirrors\n#" > /etc/pacman.d/mirrorlist
    rankmirrors -n 5 usemirrors.list | grep '^Server' >> /etc/pacman.d/mirrorlist
  fi
}

function install_display_manager { # Disable any existing display manager
  # Then install selected display manager
  translate "Installing"
  install_message "$Result " "${DisplayManager}"
  case ${DisplayManager} in
  "lightdm") pacstrap /mnt lightdm lightdm-gtk-greeter 2>> feliz.log
    arch_chroot "systemctl -f enable lightdm.service" >> feliz.log ;;
  *) pacstrap /mnt "${DisplayManager}" 2>> feliz.log
    arch_chroot "systemctl -f enable ${DisplayManager}.service" >> feliz.log
  esac
}

function install_extras { # Install desktops and other extras for FelizOB (note that $LuxuriesList 
                          # and $DisplayManager are empty, so their routines will not be called)
  if [ "$DesktopEnvironment" = "FelizOB" ]; then
    translate "Installing"
    install_message "$Result FelizOB"
    # arch_chroot "systemctl disable display-manager.service" 2>> feliz.log
    pacstrap /mnt lxdm 2>> feliz.log
    arch_chroot "systemctl -f enable lxdm.service" >> feliz.log
    pacstrap /mnt openbox 2>> feliz.log                                               # First ensure that Openbox gets installed
    pacstrap /mnt obmenu obconf 2>> feliz.log                                         # Then Openbox tools
    pacstrap /mnt lxde-icon-theme leafpad lxappearance lxinput lxpanel 2>> feliz.log  # Then LXDE tools
    pacstrap /mnt lxrandr lxsession lxtask lxterminal pcmanfm 2>> feliz.log           # more LXDE tools
    pacstrap /mnt compton conky gpicview midori xscreensaver 2>> feliz.log            # Add some extras
    cp lxdm.conf /mnt/etc/lxdm/                                                       # Copy the LXDM config file
    install_yaourt                                                                    # And install Yaourt
  fi
  # Display manager - runs only once
  if [ -n "${DisplayManager}" ]; then             # Not triggered by FelizOB or Gnome ... or Deepin
    install_display_manager                       # Clear any pre-existing DM and install this one
  fi
  # First parse through LuxuriesList checking for DEs and Window Managers (not used by FelizOB)
  if [ -n "${LuxuriesList}" ]; then
    for i in ${LuxuriesList}; do
      translate "Installing"
      case $i in
      "Awesome") install_message "$Result Awesome"
          pacstrap /mnt awesome 2>> feliz.log ;;
      "Budgie") install_message "$Result Budgie"
          pacstrap /mnt budgie-desktop 2>> feliz.log ;;
      "Cinnamon") install_message "$Result Cinnamon"
          pacstrap /mnt cinnamon 2>> feliz.log ;;
      "Deepin") install_message "$Result Deepin"
          pacstrap /mnt deepin 2>> feliz.log
          pacstrap /mnt deepin-extra 2>> feliz.log
          sed -i 's/#greeter-session=example-gtk-gnome/greeter-session=lightdm-deepin-greeter/' /mnt/etc/lightdm/lightdm.conf
          arch_chroot "systemctl -f enable lightdm.service" >> feliz.log ;;
      "Enlightenment") install_message "$Result Enlightenment"
          pacstrap /mnt enlightenment connman terminology 2>> feliz.log ;;
      "Fluxbox") install_message "$Result Fluxbox"
          pacstrap /mnt fluxbox 2>> feliz.log ;;
      "Gnome") install_message "$Result Gnome"
          pacstrap /mnt gnome 2>> feliz.log
          pacstrap /mnt gnome-extra 2>> feliz.log
          arch_chroot "systemctl -f enable gdm.service" >> feliz.log ;;
      "i3") install_message "$Result i3 window manager"
          pacstrap /mnt i3 2>> feliz.log ;;                           # i3 group includes i3-wm
      "Icewm") install_message "$Result Icewm"
          pacstrap /mnt icewm 2>> feliz.log ;;
      "JWM") install_message "$Result JWM"
          pacstrap /mnt jwm 2>> feliz.log ;;
      "KDE") install_message "$Result KDE Plasma"
          pacstrap /mnt plasma-meta 2>> feliz.log
          pacstrap /mnt kde-applications 2>> feliz.log ;;
      "LXDE") install_message "$Result LXDE"
          pacstrap /mnt lxde leafpad 2>> feliz.log
          if [ -d /mnt/etc/lxdm ]; then
            echo "session=/usr/bin/startlxde" >> /mnt/etc/lxdm/lxdm.conf 2>> feliz.log
          fi ;;
      "LXQt") install_message "$Result LXQt"
          pacstrap /mnt lxqt 2>> feliz.log
          pacstrap /mnt oxygen-icons connman lxappearance xscreensaver 2>> feliz.log ;;
      "Mate") install_message "$Result Mate"
        pacstrap /mnt mate mate-extra 2>> feliz.log
        pacstrap /mnt mate-applet-dock mate-applet-streamer mate-menu 2>> feliz.log ;;
      "Openbox") install_message "$Result Openbox"
        pacstrap /mnt openbox 2>> feliz.log ;;
      "Windowmaker") install_message "$Result Windowmaker"
        pacstrap /mnt windowmaker 2>> feliz.log
        pacstrap /mnt windowmaker-extra 2>> feliz.log ;;
      "Xfce") install_message "$Result Xfce"
        pacstrap /mnt xfce4 2>> feliz.log
        pacstrap /mnt xfce4-goodies 2>> feliz.log ;;
      "Xmonad") install_message "$Result Xmonad"
        pacstrap /mnt xmonad 2>> feliz.log
        pacstrap /mnt xmonad-contrib 2>> feliz.log ;;
      *) continue                                                     # Ignore all others on this pass
      esac
    done
    install_yaourt
    # Second parse through LuxuriesList for any extras (not triggered by FelizOB)
    for i in ${LuxuriesList}; do
        translate "Installing"
      case $i in
      "Awesome"|"Budgie"|"Cinnamon"|"Deepin"|"Enlightenment"|"Fluxbox"|"Gnome"|"i3"|"Icewm"|"JWM"|"KDE"|"LXDE"|"LXQt"|"Mate"|"Openbox"|"Windowmaker"|"Xfce"|"Xmonad") continue ;; # Ignore DEs & WMs on this pass
      "cairo-dock") install_message "$Result Cairo Dock"
        pacstrap /mnt cairo-dock cairo-dock-plug-ins 2>> feliz.log ;;
      "conky") install_message "$Result Conky"
        pacstrap /mnt conky 2>> feliz.log ;;
      *) install_message "$Result $i"
        pacstrap /mnt "$i" 2>> feliz.log
      esac
    done
  fi
}

function install_yaourt {
  translate "Installing"
  install_message "$Result Yaourt"
  arch=$(uname -m)
  if [ "$arch" = "x86_64" ]; then                                     # Identify 64 bit architecture
    # For installed system
    echo -e "\n[multilib]\nInclude = /etc/pacman.d/mirrorlist" >> /mnt/etc/pacman.conf 2>> feliz.log
    # For installer
    echo -e "\n[multilib]\nInclude = /etc/pacman.d/mirrorlist" >> /etc/pacman.conf 2>> feliz.log
  fi
  # For installed system
  echo -e "\n[archlinuxfr]\nSigLevel = Never\nServer = http://repo.archlinux.fr/$arch" >> /mnt/etc/pacman.conf 2>> feliz.log
  # For installer
  echo -e "\n[archlinuxfr]\nSigLevel = Never\nServer = http://repo.archlinux.fr/$arch" >> /etc/pacman.conf 2>> feliz.log
  # Update, then install yaourt to /mnt
  pacman-key --init 2>> feliz.log
  pacman-key --populate archlinux 2>> feliz.log
  pacman -Sy 2>> feliz.log
  pacstrap /mnt yaourt 2>> feliz.log
}

function user_add { # Adds user and copies FelizOB configurations
  CheckUsers=$(grep "$user_name" /mnt/etc/passwd)
  # If not already exist, create user
  if [ -z "${CheckUsers}" ]; then
    translate "Adding user and setting up groups"
    install_message "$Result"
    arch_chroot "useradd ${user_name} -m -g users -G wheel,storage,power,network,video,audio,lp -s /bin/bash"
    # Set up basic configuration files and permissions for user
    arch_chroot "cp /etc/skel/.bashrc /home/${user_name}"
    arch_chroot "chown -R ${user_name}:users /home/${user_name}"
    sed -i '/%wheel ALL=(ALL) ALL/s/^#//' /mnt/etc/sudoers 2>> feliz.log
  fi
  # Create main user folders
  translate "Desktop Documents Downloads Music Pictures Public Templates Videos"
  for i in ${Result}; do
    arch_chroot "mkdir /home/${user_name}/${i}"
    arch_chroot "chown -R ${user_name}: /home/${user_name}/${i}"
  done
  # FelizOB
  if [ "$DesktopEnvironment" = "FelizOB" ]; then
    # Set up directories
    arch_chroot "mkdir -p /home/${user_name}/.config/openbox/"
    arch_chroot "mkdir -p /home/${user_name}/.config/pcmanfm/default/"
    arch_chroot "mkdir -p /home/${user_name}/.config/lxpanel/default/panels/"
    arch_chroot "mkdir /home/${user_name}/Pictures/"
    arch_chroot "mkdir /home/${user_name}/.config/libfm/"
    # Copy FelizOB files
    cp -r themes /mnt/home/"$user_name"/.themes 2>> feliz.log          # Copy egtk theme
    check_existing "/mnt/home/${user_name}/" ".conkyrc"
    cp conkyrc /mnt/home/"$user_name"/.conkyrc 2>> feliz.log           # Conky config file
    check_existing "/mnt/home/${user_name}/" ".compton.conf"
    cp compton.conf /mnt/home/"$user_name"/.compton.conf 2>> feliz.log # Compton config file
    check_existing "/mnt/home/${user_name}/" ".face"
    cp face.png /mnt/home/"$user_name"/.face 2>> feliz.log             # Image for greeter
    check_existing "/mnt/home/${user_name}/.config/openbox/" "autostart"
    cp autostart /mnt/home/"$user_name"/.config/openbox/ 2>> feliz.log # Autostart config file
    check_existing "/mnt/home/${user_name}/.config/openbox/" "menu.xml"
    cp menu.xml /mnt/home/"$user_name"/.config/openbox/ 2>> feliz.log  # Openbox menu config file
    check_existing "/mnt/home/${user_name}/.config/openbox/" "rc.xml"
    cp rc.xml /mnt/home/"$user_name"/.config/openbox/ 2>> feliz.log    # Openbox config file
    check_existing "/mnt/home/${user_name}/.config/lxpanel/default/panels/" "panel"
    cp panel /mnt/home/"$user_name"/.config/lxpanel/default/panels/ 2>> feliz.log  # Panel config file
    cp feliz.png /mnt/usr/share/icons/ 2>> feliz.log                   # Icon for panel menu
    cp wallpaper.jpg /mnt/home/"$user_name"/Pictures/ 2>> feliz.log    # Wallpaper for user
    check_existing "/mnt/home/${user_name}/.config/libfm/" "libfm.conf"
    cp libfm.conf /mnt/home/"$user_name"/.config/libfm/ 2>> feliz.log  # Configs for pcmanfm
    check_existing "/mnt/home/${user_name}/.config/lxpanel/default/" "config"
    cp config /mnt/home/"$user_name"/.config/lxpanel/default/ 2>> feliz.log # Desktop configs for pcmanfm
    check_existing "/mnt/home/${user_name}/.config/pcmanfm/default/" "desktop-items-0.conf"
    cp desktop-items /mnt/home/"$user_name"/.config/pcmanfm/default/desktop-items-0.conf 2>> feliz.log # Desktop configurations for pcmanfm
    cp wallpaper.jpg /mnt/usr/share/ 2>> feliz.log
    # Set owner
    arch_chroot "chown -R ${user_name}:users /home/${user_name}/"
  fi
  # Set keyboard at login for user
  arch_chroot "localectl set-x11-keymap $Countrykbd"
  case $Countrykbd in
  "uk") echo "setxkbmap -layout gb" >> /mnt/home/"$user_name"/.bashrc 2>> feliz.log ;;
  *) echo "setxkbmap -layout $Countrykbd" >> /mnt/home/"$user_name"/.bashrc 2>> feliz.log
  esac
}

function check_existing {     # Test if $1 (path) + $2 (file) already exists
  if [ -f "$1$2" ]; then      # If path+file already exists
      mv "$1$2" "$1saved$2"   # Rename it
  fi
}

function set_root_password {
  translate "Success!"
  title="$Result"
  translate "minutes"
  mins="$Result"
  translate "seconds"
  secs="$Result"
  message_first_line "Finished installing in"
  Message="$Message ${DIFFMIN} $mins ${DIFFSEC} ${secs}\n"
  message_subsequent "Finally we need to set passwords"
  Message="${Message}\n"
  message_subsequent "Note that you will not be able to"
  message_subsequent "see passwords as you enter them"
  Message="${Message}\n"
  Repeat="Y"
  while [ $Repeat = "Y" ]; do
    message_subsequent "Enter a password for"
    Message="${Message} root\n"
    dialog --backtitle "$Backtitle" --title " $title " --insecure --nocancel \
      --ok-label "$Ok" --passwordbox "$Message" 16 60 2>output.file
    Pass1=$(cat output.file)
    rm output.file
    translate "Re-enter the password for"
    Message="${Message} root\n"
    dialog --backtitle "$Backtitle" --insecure --title " Root " --ok-label "$Ok" --nocancel --passwordbox "$Result root\n" 10 50 2>output.file
    Pass2=$(cat output.file)
    rm output.file
    if [ -z "$Pass1" ] || [ -z "$Pass2" ]; then
      title="Error"
      message_first_line "Passwords cannot be blank"
      message_subsequent "Please try again"
      Message="${Message}\n"
      message_subsequent "Note that you will not be able to"
      message_subsequent "see passwords as you enter them"
      Message="${Message}\n"
      continue
    fi
    if [ "$Pass1" = "$Pass2" ]; then
     echo -e "${Pass1}\n${Pass2}" > /tmp/.passwd
     arch_chroot "passwd root" < /tmp/.passwd >> feliz.log
     rm /tmp/.passwd 2>> feliz.log
     Repeat="N"
    else
      title="Error"
      message_first_line "Passwords don't match"
      message_subsequent "Please try again"
      Message="${Message}\n"
      message_subsequent "Note that you will not be able to"
      message_subsequent "see passwords as you enter them"
      Message="${Message}\n"
    fi
  done
}

function set_user_password {
  message_first_line "Enter a password for"
  Message="${Message} ${user_name}\n"
  Repeat="Y"
  while [ $Repeat = "Y" ]; do
    message_subsequent "Note that you will not be able to"
    message_subsequent "see passwords as you enter them"
    Message="${Message}\n"
    dialog --backtitle "$Backtitle" --title " $user_name " --insecure \
      --ok-label "$Ok" --nocancel --passwordbox "$Message" 15 50 2>output.file
    Pass1=$(cat output.file)
    rm output.file
    message_first_line "Re-enter the password for"
    Message="${Message} $user_name\n"
    dialog --backtitle "$Backtitle" --title " $user_name " --insecure \
      --ok-label "$Ok" --nocancel --passwordbox "$Message" 10 50 2>output.file
    Pass2=$(cat output.file)
    rm output.file
    if [ -z "$Pass1" ] || [ -z "$Pass2" ]; then
      title="Error"
      message_first_line "Passwords cannot be blank"
      message_subsequent "Please try again"
      Message="${Message}\n"
      message_subsequent "Note that you will not be able to"
      message_subsequent "see passwords as you enter them"
      Message="${Message}\n"
      continue
    fi
    if [ "$Pass1" = "$Pass2" ]; then
     echo -e "${Pass1}\n${Pass2}" > /tmp/.passwd
     arch_chroot "passwd ${user_name}" < /tmp/.passwd >> feliz.log
     rm /tmp/.passwd 2>> feliz.log
     Repeat="N"
    else
      title="Error"
      message_first_line "Passwords don't match"
      message_subsequent "Please try again"
      Message="${Message}\n"
      message_subsequent "Note that you will not be able to"
      message_subsequent "see passwords as you enter them"
      Message="${Message}\n"
    fi
  done
}

function finish {
  translate "Shutdown Reboot"
  Item1=$(echo "$Result" | cut -d' ' -f1)
  Item2=$(echo "$Result" | cut -d' ' -f2)
  dialog --backtitle "$Backtitle" --title " Finish "  --ok-label "$Ok" \
    --cancel-label "$Cancel" --menu "$Backtitle" 12 30 2 \
      1 "$Item1" \
      2 "$Item2" 2>output.file
  retval=$?
  Result="$(cat output.file)"
  rm output.file
  case $Result in
  1) shutdown -h now ;;
  2) reboot ;;
  *) exit
  esac
}
