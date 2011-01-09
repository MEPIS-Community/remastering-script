#!/bin/bash

# -------------------------------------------------------------------------------------- #
# Script:    remaster.sh                                                                 #
# Details:   remasters MEPIS 8.5 and possible other Live CDs created with SquashFS       #
# Requirements: squashfs-tools, squashfs-modules, aufs, mkisofs                          #
#                                                                                        #
# This program is distributed in the hope that it will be useful, but WITHOUT            #
# ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS          #
# -------------------------------------------------------------------------------------- #

# Provides a synopsis:
function usage {
	echo "$0 [-b|--build-iso] [-c|--chroot] [-d|--from-hdd] [old-iso]"
	echo "$0 {-h|--help}"
}

# Offers help:
function help {
	usage
	echo "    old-iso            the path to the original ISO image"
	echo
	echo "    -b|--build-iso     skip creating the chroot environment"
	echo "    -c|--chroot        logs into already created chroot environment"
	echo "    -d|--from-hdd      remasters from harddisk installation (experimental feature)"
	echo "    -h|--help          display this help"
	echo
	exit
}

# Checks whether a given file system is configured.
function fs_configured {
	grep -q $1 /proc/filesystems
}

# Checks whether squshfs-tools is installed
# (modify this for distros that are not based on Debian)
function check_squashfs-tools {
	dpkg -s squashfs-tools | grep -q "ok installed" || {
		echo -n "This script needs to use squashfs-tools, can I install it"
		Y_or_n || {
			echo -e "Squshfs-tools is a required package. Script aborted.\n"
			exit 2
		}
		install_squashfs-tools
	}
}

# Installs squashfs-tools (modify this for distros that don't use apt-get)
# (modify this for distros that are not based on Debian)
function install_squashfs-tools {
	apt-get update
	apt-get install squashfs-tools || {
		echo -e "Error installing required package. Script aborted.\n"
		exit 2
	}
}

# Installs or build squashfs-modules
# (modify this for distros that are not based on Debian)
function install_squashfs-modules {
	apt-get update
	apt-get install squashfs-modules-$(uname -r) || {
		echo
		echo -n "Package \"squashfs-modules-$(uname -r)\" didn't install successfully, should I build it"
		Y_or_n || {
			echo -e "\"squashfs-modules-$(uname -r)\" is required. Script aborted.\n"
			exit 2
		}
		apt-get install module-assistant
		m-a update
		m-a a-i squashfs || {
			echo
			echo -e "Error building \"squshfs-module\". Script aborted.\n"
			exit 2
		}
	}
}

function check_aufs {
	lsmod | grep -q aufs || modprobe aufs || {
		echo -e "This script requires AUFS. Script aborted.\n"
		exit 2
	}
}

function check_mkisofs {
	dpkg -s mkisofs | grep -q "ok installed" || {
		echo -n "This script needs to use mkisofs, can I install it"
		Y_or_n || {
			echo -e "mksiofs is a required package. Script aborted.\n"
			exit 2
		}
		install_mkisofs
	}
}

function install_mkisofs {
	apt-get update
	apt-get install mkisofs || {
		echo -e "Error installing required package. Script aborted.\n"
		exit 2
	}
}

# Utility function: asks yes/no question and return true for "y" and false for "n"; default is "yes"
function Y_or_n {
	read -p " (Y/n)? "
	echo
	case $REPLY in
		no|n) 	return 1;;
		*)	return 0;;
	esac
}

# Utility function: asks yes/no question and return true for "y" and false for "n"; default is "no"
function y_or_N {
	read -p " (y/N)? "
	echo
	case $REPLY in
		yes|y)	return 0;;
		*)	return 1;;
	esac
}

# Utility function: asks if ready, if "no" exits, continue otherwise
function user_ready {
	echo -n "Are you ready to start building the ISO"
	Y_or_n || {
		echo -e "OK, to remaster later on, run this script with \"build-iso\" argument, like this \"$0 --build-iso\" or \"$0 -b\" "
		echo
		return 1
	}
	return 0
}

# Set working path where everything is copied
function set_host_path {
	# Execute this section if script was NOT executed with --from-hdd option
	# Sets the current directory as working path, if "remaster" directory already exists prompt for another path
	$HD || {
		if [[ -e $STARTPATH/remaster ]]; then
			echo "Enter the host path (i.e. /home/username) in which you want to remaster your project: "
			read -e HOSTPATH
			echo
			create_host_dir $HOSTPATH || set_host_path
		else
			HOSTPATH=$STARTPATH
			create_host_dir $HOSTPATH || {
				echo -e "Error creating \"remaster\" directory. Script aborted. \n"
				exit
			}
		fi
		cd $REM
	}
	# Set target path where the remastered ISO will be placed when running the script with --from-hdd option
	$HD && {
		echo -e "Enter the host path (i.e. /mnt/hda5/home/username) in which you want to remaster your project."
		echo "When remastering from harddisk you need to specify a different partition than the one you remaster: "
		read -e HOSTPATH
		echo
		if [[ $HOSTPATH =~ $ROOTPART ]]; then
			set_host_path
		else
			PART=$(echo $HOSTPATH | cut -d "/" -f 3)
			HOSTPART=/mnt/$PART
			grep -q "$HOSTPART " /etc/mtab || {
				mkdir -p $HOSTPART
				mount /dev/$PART $HOSTPART || {
					echo "Could not mount \"$HOSTPART\""
					set_host_path
				}
			}
		fi
		create_host_dir $HOSTPATH || set_host_path
		cd $REM
	}
}

function create_host_dir {
	if [[ -e $1/remaster ]]; then
		echo -e "Error: the $1/remaster directory already exists, please use another path.\n"
		return 1
	fi
	mkdir -p $1/remaster
	if [[ $? -ne 0 ]]; then
		echo -e "Error: the directory was not created, please try again \n"
		return 1
	else
		echo -e "The project will be created in \"$1/remaster\" directory \n"
		REM=$1/remaster
		echo -e "Okay, we have added a \"remaster\" subdirectory to your host path.\n"
	fi
}

# Sets the path to iso or cdrom
function get_iso_path {
	if [[ -e $1 ]]; then
		CD=$1
		echo -e  "This script will remaster \"$CD\"  \n"
	else
		echo -e "Enter the path of your optical drive with the MEPIS CD (i.e. /dev/hdc)" 
		echo "Or enter the complete path to a MEPIS iso on your hard disk (i.e. /path_to_iso/mepis.iso): "
		read -e CD
		echo
		if [[ ! -e $CD ]]; then
			echo -e "Path or file doesn't exist, please try again \n" 
			get_iso_path
		fi
	fi
	# Add full path to CD name
	if [[ $(dirname $CD) == "." ]]; then
		CD=$PWD/$CD
	fi
}

function create_remaster_env {
	if [[ ! -d iso   &&  ! -d squshfs  &&  ! -d newiso &&  ! -d newsquash ]]; then
		echo "Creating directory structure for this operation"
		mkdir iso squash newiso newsquash
		echo "($REM/iso) directory to mount CD on"
		echo "($REM/squash) directory for old squashfs"
		echo "($REM/newsquash) directory for new squashfs"
		echo -e "($REM/newiso) directory for new iso \n"
		echo -e "Mounting original CD to $REM/iso"
	fi
	mount_iso $CD
	mount -t aufs -o br:newiso:iso none newiso
	find_squashfs iso
	mount_compressed_fs $SQUASH squashfs
	mount -t aufs -o br:newsquash:squash none newsquash
}

# Mounts ISO named $1 to $REM/iso
function mount_iso {
	cd $STARTPATH
	mount -o loop $1 $REM/iso || {
		echo -n "Could not mount the CD image, do you want to try again"
		Y_or_n || exit 3
		$0
		exit
	}
	cd $REM
}

function find_squashfs {
	# Finds the biggest file in ISO, which is most likely the squash file
	SQUASH=$(find $1 -type f -printf "%s %p\n" | sort -rn | head -n1 | cut -d " " -f 2)
}

# Function mounts file $1 of type $2
function mount_compressed_fs {
	echo "Mounting original squashfs to $REM/squash"
	mount -t $2 -o loop $1 squash || {
		umount -ld newiso
		umount -ld iso
		echo "Error mounting squashfs file. \"$1\" is probable not a $2 file."
		exit 4
	}
}

# Find the "remaster" directory when script launched with --chroot or --build-iso
function get_remaster_dir {
	HOSTPATH=$PWD
	if [[ ! -d $HOSTPATH/remaster ]]; then
		echo -e "Enter the path to the remaster directory (e.g., /home/username): "
		read -e HOSTPATH
		echo
		[[ ! -d $HOSTPATH/remaster ]] && {
			echo -e "\"remaster\" directory not found in that path, please try again:\n"
			get_remaster_dir
		}
	fi
	REM=$HOSTPATH/remaster
	cd $REM
}

# Mounts all needed directories for chroot environment
function mount_bind {
	# Mount /proc and /sys and set up networking (I prefer to mount temporarily resolv.conf instead of copying it)
	mount --bind /proc $1/proc
	mount --bind /sys $1/sys
	mount --bind /dev $1/dev
	mount --bind /dev/pts $1/dev/pts
	mount --bind /tmp $1/tmp
#        mount --bind /var $1/var
	touch $1/etc/resolv.conf
	mount --bind /etc/resolv.conf $1/etc/resolv.conf
}

# Unmounts all mounted directories/files
function umount_bind {
	grep -q "$1/proc" /etc/mtab && {
		umount -l $1/tmp
		umount -l $1/dev/pts
		umount -l $1/dev
		umount -l $1/sys
		umount -l $1/proc
#		 umount -l $1/var
		umount -l $1/etc/resolv.conf
	}
	grep -q "gshadow" /etc/mtab && {
		cd /
		umount -l $1/etc/group
		umount -l $1/etc/gshadow
		umount -l $1/etc/hostname
		umount -l $1/etc/hosts
		umount -l $1/etc/passwd
		umount -l $1/etc/shadow
		umount -l $1/etc/sudoers
		umount -l $1/home
		cd $REM
	}
}

function umount_loop {
	umount -ld $1/newsquash
	umount -ld $1/squash
	umount -ld $1/newiso
	umount -ld $1/iso
}

# Commands that clean up the chroot environment at log out
function cleanup {
	echo -n "Do you want to remove \"/root/.bash_history\", \"/root/.synaptic/log/\", \"/var/lib/apt/lists/*\""
	Y_or_n && {
		rm -f $1/root/.synaptic/log/*
		rm -f $1/root/.bash_history
		rm -r $1/var/lib/apt/lists/*
		mkdir $1/var/lib/apt/lists/partial
	}
}

# Builds squashfs from $1 folder and then makes the new ISO
function build {
	edit_version_file
	set_iso_path
	set_iso_name
	make_squashfs $1
	make_iso $ISONAME
}

# Mounts filesystems and chroots to remastering environment, at exit unmounts all filesystems and perform cleanup for remastering environment
function chroot_env {
	mount_bind $1

	# Assume root in our new squashfs
	echo -e "Chrooting into your / \n"
	echo -e "You should now be in the environment you want to remaster. To check please type \"ls\" - you should see a root directory tree."
	echo -e "When done please type \"exit\" or press CTRL-D \n"
	set_chroot_commands $1
	chroot $1
	umount_bind $1
	cleanup $1
	sync
}

# Execute commands automatically after you enter the chroot environment and at log out.
function set_chroot_commands {
	# Backup original bash.bashrc
	cp -a $1/etc/bash.bashrc $1/etc/bash.bashrc_original
	echo '
		# Commands to be run automatically after entering chroot
		
		# Restore original file
		mv /etc/bash.bashrc_original /etc/bash.bashrc

		# Start a new session
		/bin/bash

		# Commands to run automatically when exiting from chroot environment (e.g., clean-up commands)
		echo
		echo -e "Cleaning chroot environment..."
		apt-get clean
		echo -e "Exiting chroot.\n"
		exit' >> $1/etc/bash.bashrc
}

function edit_version_file {
	echo -e "This is your current version file: \n"
	echo "----------------------------------------------------"
	cat newiso/version
	echo
	echo -e "----------------------------------------------------\n"
	echo -n "Would you like to amend your version file"
	y_or_N && {
		chmod +w newiso/version
		${EDITOR:-nano} newiso/version
		chmod -w newiso/version
	}
}

# Set ISO path
function set_iso_path {
	cd $STARTPATH
	echo -e "The ISO file will be placed by default in \"$REM\" directory. \n"
	echo -n "Is that OK"
	Y_or_n && ISOPATH=$REM || {
		while true; do
			echo "Enter the path (i.e. /home/username) in which you want to place your ISO file: "
			read -e ISOPATH
			echo
			if [[ -d $ISOPATH ]]; then
				break
			else
				echo -n "\"$ISOPATH\" doesn't exist, create"
				Y_or_n && {
					mkdir -p $ISOPATH
					if [[ $? -ne 0 ]]; then
						echo -e "Error: the directory was not created, please try again \n"
					else
						echo -e "The path will be \"$ISOPATH\" \n"
						break
					fi
				}
			fi
		done
	}
}

function set_iso_name {
	echo -e "Enter the name of the ISO file (default: remastered.iso) "
	read -e ISONAME
	ISONAME=$ISOPATH/${ISONAME:-remastered.iso}
	echo
	if [[ -e $ISONAME ]]; then
		echo -n "File exists, overwrite"
		Y_or_n || set_iso_name
	fi
}

# Create new squashfs in the newiso
function make_squashfs {
	cd $REM
	echo -e "Good. We are now creating your iso. Sit back and relax, this can take some time (~20 minutes on an AMD +2500 for a 680MB iso, ~4 minutes for an AMD 2.3Ghz Triple Core Phenom). \n"
	mksquashfs $1 newiso/mepis/mepis -noappend || {
		echo -e "Error making squashfs file. Script aborted.\n" 
		exit 5
	}
}

# makes iso named $1
function make_iso {
	cd $STARTPATH
	mkisofs -l -J -pad -no-emul-boot -boot-load-size 4 -boot-info-table -b boot/isolinux/isolinux.bin -c boot/isolinux/isolinux.cat -o $1 $REM/newiso
	if [[ $? -eq 0 ]]; then
		echo
		echo "Done. You will find your very own remastered home-made Linux here: $1"
		check_size $1
	else
		echo
		echo -e "ISO building failed.\n"
	fi
	cd $REM
}

# Displays size of created ISO file and recommends storage medium
function check_size {
	SIZE=$(ls -l $1 | cut -d " " -f 5)
	let SIZE=$SIZE/1048576 #convert in MB
	echo -n "File size = $SIZE MB, "
	if [[ $SIZE -lt 50 ]]; then
		echo -e "you can burn this file on a business-card CD, or a larger medium\n"
	else if [[ $SIZE -lt 180 ]]; then
		echo -e "you can burn this file on a Mini CD, or a larger medium\n"
	else if [[ $SIZE -lt 650 ]]; then
		echo -e "you can burn this file on a 650 MB / 74 Min. CD, or a larger medium\n"
	else if [[ $SIZE -lt 700 ]]; then
		echo -e "you can burn this file on a 700 MB / 80 Min. CD, or a larger medium\n"
	else if [[ $SIZE -lt 4812 ]]; then
		echo -e "this is too big for a CD, burn it on a DVD\n"
	else if [[ $SIZE -lt  8704 ]]; then
		echo -e "this is too big for a 4.7 GB DVD, burn it on a dual-layer DVD\n"
	else 
		echo -e "the file is probably too big to burn even on a dual-layer DVD\n"
		fi; fi; fi; fi; fi
	fi
}

# "--from-hdd" or "-d" mode can be run only from a Live CD
function check_installed {
	# Determine if running from HDD
	local INSTALLED=true
	if [[ -e /proc/sys/kernel/real-root-dev ]]; then
		case "$(cat /proc/sys/kernel/real-root-dev 2>/dev/null)" in
			256|0x100) INSTALLED="false";;
		esac
	fi
	if [[ $INSTALLED ]]; then
		echo
		echo -e "You started the script with \"--from-hdd\" option, you need to run the script from a Live CD\n"
		exit
	fi
}

# Chooses between two ways of creating a Live CD from hdd
function generic_or_custom {
	echo "You have two choices here:"
	echo "1. Remaster a generic Live CD -- you'll lose your user account(s), you have to use Live CD's default accounts and passwords, /home partition or directory will not be included in resulting ISO."
	echo -e "2. Remaster a custom Live CD -- you'll keep your own account(s) and paswords in the new Live CD\n WARNING! NOT WORKING YET! "
	echo "Please enter your choice: 1 or 2 "
	read -e ANSWER
	echo
	case $ANSWER in
		2)	CUSTOM="true"; custom_cd;;
		*)	GENERIC="true"; generic_cd;;
	esac
}

# Temporary mount files that need to be included in the new squashfs file
function generic_cd {
	mount --bind /etc/group $ROOTPART/etc/group
	mount --bind /etc/gshadow $ROOTPART/etc/gshadow
	mount --bind /etc/hostname $ROOTPART/etc/hostname
	mount --bind /etc/hosts $ROOTPART/etc/hosts
	mount --bind /etc/passwd $ROOTPART/etc/passwd
	mount --bind /etc/shadow $ROOTPART/etc/shadow
	mount --bind /etc/sudoers $ROOTPART/etc/sudoers
	mount --bind /home $ROOTPART/home
}

function custom_cd {
	echo "This option DOESN'T completely work yet. To log in in the resulting Live CD you need to:"
	echo " 1. boot the Live CD using \"aufs\" option"
	echo " 2. press CTRL-ALT-F1, log in as root and execute this command: \"mount --bind /aufs/home /home\""
	echo " 3. run: \"/etc/init.d/kdm restart\""
}

# Asks user to entry / and /home partition to remaster
function get_remaster_partition {
	echo "Enter the partition that you want to remaster (e.g., sda3) "
	read -e PART
	echo
	ROOTPART=/mnt/$PART
	if [[ ! -e $ROOTPART ]]; then
		mkdir $ROOTPART
	fi
	mount_partition /dev/$PART $ROOTPART
	$CUSTOM && {
		echo -n "Do you have /home on a different partition"
		y_or_N && {
			echo "Enter /home partition (e.g., sda4) "
			read -e HOMEPART
			echo
			mount_partition /dev/$HOMEPART $ROOTPART/home
		}
	}
}

function mount_partition {
	grep -q "$2 " /etc/mtab || {
		mount $1 $2 || {
			echo
			echo -n "Could not mount \"$2\" partition, retry"
			Y_or_n || exit
			get_remaster_partition
		}
	}
}

# Root check 
if [[ $UID != "0" ]]; then
	echo -e "You need to be root to execute this script.\n"
	exit 1
fi

# Check that we have a squashfs file system configured.
fs_configured squashfs || modprobe squashfs || {
	echo
	echo -n "This remastering process uses the \"squashfs\" file system which doesn't seem to be installed on your system. Without it we cannot proceed. Shell I install it"
	Y_or_n || {
		echo -e "\"squashfs\" is required. Script aborted.\n"
		exit 2
	}
	install_squashfs-modules
	fs_configured squashfs || modprobe squashfs || {
		echo -e "\"squashfs\" is required. Script aborted.\n"
		exit 2
	}
}

# Initializing variables
STARTPATH=$PWD
ERROR=false
BUILD=false
CHROOT=false
HD=false
GENERIC=false
CUSTOM=false

# Captures command line options:
for args; do
	case "$1" in
		-b|--build-iso) BUILD=true;;
		-c|--chroot) 	CHROOT=true;;
		-d|--from-hdd) 	HD=true;;
		-h|--help) 	help;;
		--) 		shift; break;;
		-*) 		echo "Unrecognized option: $1"; ERROR=true;;
		*) 		break;;
	esac
	shift
done

# Exits to help if not understood:
$ERROR && help

# This checks for script requirements (squashfs, aufs, mkisofs)
check_squashfs-tools
check_aufs
check_mkisofs

# Execute this section if script called with --from-hdd or -d
$HD && {
	check_installed  ## check if script runs from HDD
	get_remaster_partition
	generic_or_custom
	set_host_path
	mkdir newiso
	mount -t aufs -o br:$REM/newiso:/cdrom $REM/newiso
	echo
	echo -n "Do you want to chroot to $ROOTPART to add/remove programs"
	Y_or_n && {
		echo -e "WARNING!!! You are chrooting to $ROOTPART, any changes in the chroot environment will affect the actual hard disk installation. \n"
		chroot_env $ROOTPART
	}
	build $ROOTPART
	umount_bind $ROOTPART
	umount -ld $REM/newiso
	rm -r $REM/newiso
	exit
}

# Execute this section if script called with --chroot or -c
$CHROOT && {
	get_remaster_dir
	CD=$(cat .project.info)
	create_remaster_env
	chroot_env newsquash
	if (user_ready); then
		build newsquash
	fi
	umount_loop $REM
	exit
}

# Execute this section if script called with --build-iso or -b
$BUILD && {
	get_remaster_dir
	CD=$(cat .project.info)
	create_remaster_env
	build newsquash
	umount_loop $REM
	exit
}

# Execute if script is NOT called with --build-iso, --chroot, --from-hdd arguments
get_iso_path $1
set_host_path
# Write a .project.info file in remaster directory that contains the name of the ISO
# File will used to recreate the environment if script restarted with -b or -c options
echo $CD > $REM/.project.info
create_remaster_env
chroot_env newsquash
if (user_ready); then
	build newsquash
fi
umount_loop $REM

