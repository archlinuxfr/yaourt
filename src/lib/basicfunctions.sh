#!/bin/bash
#===============================================================================
#
#          FILE: basicfunctions.sh
# 
#   DESCRIPTION: yaourt's basic functions
# 
#       OPTIONS:  ---
#  REQUIREMENTS:  ---
#          BUGS:  ---
#         NOTES:  ---
#        AUTHOR:   Julien MISCHKOWITZ (wain@archlinux.fr) 
#       VERSION:  1.0
#===============================================================================


# set misc path
initpath(){
	LOCKFILE="/var/lib/pacman/db.lck"
	PACMANROOT=`LC_ALL=C pacman --verbose | grep 'DB Path' | awk '{print $4}'| sed "s/\/$//"`
	mkdir -p "$YAOURTTMPDIR"
}

# Load library but never reload twice the same lib
loadlibrary(){
	eval alreadyload=\$$1
	[ ! -z "$alreadyload" ] && return 0
	if [ ! -f "/usr/lib/yaourt/$1.sh" ]; then
		error "$1.sh file is missing"
		die 1
	fi
	source "/usr/lib/yaourt/$1.sh" || warning "problem in $1.sh library"
	eval $1=1
}

# ask 
userinput() 
{ 
	[ -z $1 ] && _key="YN" || _key=$1
	read -en $NOENTER
	echo $REPLY | tr '[[:lower:]]' '[[:upper:]]'  | tr "$(eval_gettext $_key)" "$_key"
}

_translate_me()
{
	# Used to detect string with poedit
	eval_gettext "YN"  # Yes, No
	eval_gettext "YAN" # Yes, All, No
	eval_gettext "YNA" # Yes, No, Abort
	eval_gettext "YNVC" # Yes, No, View package, Check package with namcap
	eval_gettext "YNVM" # Yes, No, View more infos, Manualy select packages
}

yes_no ()
{
	case $1 in
	  1) 
		  echo $(eval_gettext "[Y/n]")
			;;
	  2)
		  echo $(eval_gettext "[y/N]")
			;;
	  *)
		  echo $(eval_gettext "[y/n]")
			;;
	esac
}
		  
isnumeric(){
	if let $1 2>/dev/null; then return 0; else return 1; fi
}

is_x_gt_y(){
	local version=( $(echo $1 | tr "[:punct:]" "\ " | sed 's/[a-zA-Z]/ &/g') )
	local lversion=( $(echo $2 | tr "[:punct:]" "\ " | sed 's/[a-zA-Z]/ &/g') )
	if [ ${#version[@]} -gt ${#lversion[@]} ]; then 
		versionlength=${#version[@]}
	else
		versionlength=${#lversion[@]}
	fi
	
	for i_index in `seq 0 $((${versionlength}-1))`; do 
		if `isnumeric ${version[$i_index]}` && `isnumeric ${lversion[$i_index]}`;  then
			if [ ${version[$i_index]} -eq ${lversion[$i_index]} ]; then continue; fi
			if [ ${version[$i_index]} -gt ${lversion[$i_index]} ]; then return 0; else return 1; fi
			break
		elif [ `isnumeric ${version[$i_index]}` -ne  `isnumeric ${lversion[$i_index]}` ]; then
			if [ "${version[$i_index]}" = "${lversion[$i_index]}" ]; then continue;fi
			if [ "${version[$i_index]}" \> "${lversion[$i_index]}" ]; then return 0; else return 1; fi
			break
		fi
	done
	return 1
}

readconfigfile(){
# defautconfig
EDITPKGBUILD=1
DEVEL=0
EXPORTDIR=""
EXPORT=0
TERMINALTITLE=1
NOCONFIRM=0
FORCE=0
AURCOMMENT=1
AURUPGRADE=0
AURVOTE=1
AURSEARCH=1
AUTOSAVEBACKUPFILE=0
MAXCOMMENTS=5
NOENTER=1
ORDERBY="asc"
PACMANBIN="/usr/bin/pacman"
INENGLISH=""
sfmirror=""

while [ "$#" -ne "0" ]; do
	lowcasearg=`echo $2 | tr A-Z a-z`
	case $lowcasearg in
		yes) value=1
		;;
		no) value=0
		;;
		*)value=-1
		;;
	esac

	case "`echo $1 | tr A-Z a-z`" in
		noconfirm)
			if [ $value -gt -1 ]; then
				NOCONFIRM=$value; shift
				[ $NOCONFIRM -eq 1 ] && EDITPKGBUILD=0
			fi
			;;
		alwaysforce)
			if [ $value -gt -1 ]; then
				FORCE=$value; shift
			fi
	  		;;	
		autosavebackupfile)
			if [ $value -gt -1 ]; then
				AUTOSAVEBACKUPFILE=$value; shift
			fi
	  		;;	
		forceenglish)
			if [ $value -gt -1 ]; then
				shift
				if [ $value -eq 1 ]; then
					INENGLISH="LC_ALL=C"
				fi
			fi
	  		;;	
		editpkgbuild)
			if [ $value -gt -1 ]; then
				EDITPKGBUILD=$value; shift
			fi
	  		;;	
		showaurcomment)
			if [ $value -gt -1 ]; then
				AURCOMMENT=$value; shift
			fi
	  		;;	
		alwaysupgradedevel)
			if [ $value -gt -1 ]; then
				DEVEL=$value; shift
			fi
	  		;;	
		dontneedtopressenter)
			if [ $value -gt -1 ]; then
				NOENTER=$value; shift
			fi
	  		;;	
		alwaysupgradeaur)
			if [ $value -gt -1 ]; then
				AURUPGRADE=$value; shift
			fi
	  		;;	
		aurvotesupport)
			if [ $value -gt -1 ]; then
				AURVOTE=$value; shift
			fi
	  		;;	
		searchinaurunsupported)
			if [ $value -gt -1 ]; then
				AURSEARCH=$value; shift
			fi
	  		;;	
		updateterminaltitle)
			if [ $value -gt -1 ]; then
				TERMINALTITLE=$value; shift
			fi
	  		;;	
		exporttolocalrepository)
			if [ -d "$2" ]; then
				EXPORT=1; EXPORTDIR="$2"; shift
			else
				error "ExportToLocalRepository is not a directory"
			fi
	  		;;	
		tmpdirectory)
			if [ -d "$2" ]; then
				cd "$2"
				YAOURTTMPDIR="`pwd`/yaourt-tmp-`id -un`"
				cd - 1>/dev/null; shift
			else
				error "TmpDirectory is not a directory"
			fi
	  		;;	
		sourceforgemirror)
				sfmirror="$2"; shift
				;;
		lastcommentsnumber)
			if `isnumeric $2`; then
			       MAXCOMMENTS=$2; shift
		        else
				error "Wrong value for LastCommentsNumber"
		        fi
			;;	       
		lastcommentsorder)
			if [ "$lowcasearg" = "asc" -o "$lowcasearg" = "desc" ]; then
			       ORDERBY=$lowcasearg; shift
			else
				error "Wrong value for LastCommentsOrder"
		        fi
			;;	       
		pkgbuildeditor)
			if [ `type -p "$2"` ]; then
				EDITOR="$2"; shift
			else
				error "PkgbuildEditor not found"
			fi
	  		;;	
		pacmanbin)
			if [ -f "$2" ]; then
				PACMANBIN="$2"; shift
			else
				error "PACMANBIN: $2 is incorrect"
			fi
			;;
		colormod)
			case $lowcasearg in
				lightbackground)
					COLORMODE="--lightbg"; shift
				;;
				nocolor)
					COLORMODE="--nocolor"; shift
				;;
				textonly)
					COLORMODE="--textonly"; shift
				;;
				normal)	shift ;;
			esac
			;;
		*)
		echo "$1 "$(eval_gettext "no recognized in config file")
		sleep 4
		;;
	esac
	shift
done

PACMANBIN="$INENGLISH $PACMANBIN"
	
}


###################################
### MAIN OF INIT PROGRAM        ###
###################################

YAOURTTMPDIR="/tmp/yaourt-tmp-$(id -un)"
if [ -f ~/.yaourtrc ]; then
	configfile="$HOME/.yaourtrc"
else
	configfile="/etc/yaourtrc"
fi

loadlibrary color
readconfigfile `grep "^[\ ]*[a-zA-Z]" $configfile`
initcolor
initpath
