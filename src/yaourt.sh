#!/bin/bash
#
#   Yaourt (Yet Another Outil Utilisateur): More than a Pacman frontend
#
#   Copyright (C) 2008, Julien MISCHKOWITZ wain@archlinux.fr
#   Homepage: http://www.archlinux.fr/yaourt-en
#   Based on:
#   yogurt from Federico Pelloni <federico.pelloni@gmail.com>
#   srcpac from Jason Chu  <jason@archlinux.org>
#   pacman from Judd Vinet <jvinet@zeroflux.org>
#
#       This program is free software; you can redistribute it and/or modify
#       it under the terms of the GNU General Public License as published by
#       the Free Software Foundation; either version 2 of the License, or
#       (at your option) any later version.
#       
#       This program is distributed in the hope that it will be useful,
#       but WITHOUT ANY WARRANTY; without even the implied warranty of
#       MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#       GNU General Public License for more details.
#       
#       You should have received a copy of the GNU General Public License
#       along with this program; if not, write to the Free Software
#       Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston,
#       MA 02110-1301, USA.
export TEXTDOMAINDIR=/usr/share/locale
export TEXTDOMAIN=yaourt
type gettext.sh > /dev/null 2>&1 && { . gettext.sh; } || eval_gettext () { echo "$1"; }

NAME="yaourt"
VERSION="0.9.2.6"
AUR_URL="http://aur.archlinux.org/packages.php?setlang=en&do_Search=SeB=nd&L=2&C=0&PP=100&K="
AUR_URL3="http://aur.archlinux.org/packages.php?setlang=en&ID="
ABS_URL="http://archlinux.org/packages/search/?category=all&limit=99000"
ABS_REPOS_URL="http://repos.archlinux.org/viewvc.cgi"
[ -z "$LC_ALL" ] && export LC_ALL=$LANG

###################################
### Build functions             ###
###################################
readPKGBUILD(){
	unset pkgname pkgver pkgrel arch pkgdesc provides url source install md5sums \
	depends makedepends conflicts replaces _svntrunk _svnmod _cvsroot _cvsmod _hgroot \
	_hgrepo	_gitroot _gitname _darcstrunk _darcsmod _bzrtrunk _bzrmod 
	source ./PKGBUILD &> /dev/null
	local failed=0
	local PKG="$1"
	[ -z "$pkgname" ] && failed=1
	if [ $failed -eq 1 ]; then
		echo $(eval_gettext 'Unable to read PKGBUILD for $PKG')
		return 1
	fi
	return 0
}
setPARCH(){
	if [ "$arch" = "any" ]; then
		PARCH='any'
	else
		PARCH="$CARCH"	
	fi
}

sourceforge_mirror_hack(){
	readPKGBUILD
	if ! echo ${source[*]} | grep -q "http://dl.sourceforge.net/"; then
		return 0
	fi
	warning $(eval_gettext 'Sourceforge Direct Downloads is reserved to Premium Subscribers')
	if [ -z "$sfmirror" -a $NOCONFIRM -eq 0 ]; then
		plain $(eval_gettext 'Please choose a specific mirror:')
		plain $(eval_gettext '>  TIPS: You can define the mirror by adding this line in yaourtrc')
		plain '>        SourceforgeMirror belnet'
		plain $(eval_gettext '>  (replace belnet with the name of your favorite sourceforge mirror)')
		echo
		list "1.surfnet(NL) 2.ufpr(BR) 3.heanet(IE) 4.easynews(US) 5.umn(US) 6.switch(CH) 7.belnet(BE) 8.kent(UK)"
		list "9.mesh(DE) 10.optusnet(AU) 11.jaist(JP) 12.puzzle(CH) 13.superb-east(US) 14.nchc(TW) 15.superb-west(US)"
		prompt $(eval_gettext 'Enter the number corresponding to the mirror or the mirror''s name or press Enter to use automatic redirect (slower)')
		read -e mirror_reply
		mirror=( none surfnet ufpr heanet easynews umn switch belnet kent mesh optusnet jaist puzzle superb-east nchc superb-west )
		if [ -z "${mirror_reply}" ]; then
			return 0
		elif [ ! -z "${mirror[${mirror_reply}]}" ]; then
			sfmirror=${mirror[$mirror_reply]}
		else
			sfmirror=$mirror_reply
		fi
	fi
	if [ "$sfmirror" = "none" ]; then
		plain $(eval_gettext 'no mirror will be used')
	else
		plain $(eval_gettext '$sfmirror mirror will be used')
		sed -i "s|http://dl.sourceforge.net/|http://${sfmirror}.dl.sourceforge.net/|g" ./PKGBUILD
	fi
	return
}

###################################
### General functions           ###
###################################

usage(){
	echo "$(eval_gettext '    ---  Yaourt version $VERSION  ---')"
	echo
	echo "$(eval_gettext 'yaourt is a pacman frontend with a lot of features like:')"
	echo
	echo "$(eval_gettext '. AUR support (search, easy install, vote etc..)')"
	echo "$(eval_gettext '. interactiv search + install (with AUR Unsupported results integrated)')"
	echo "$(eval_gettext '. building packages directly from ABS cvs sources')"
	echo "$(eval_gettext '. search output colorised (skinable) + always show the repository where a package came from')"
	echo "$(eval_gettext '. handling config files .pacnew/.pacsave')"
	echo "$(eval_gettext '. managing alpm database backup (save, restore, query database directly on backup file)')"
	echo "$(eval_gettext '. alert user when new orphans  are  detected  and  check  the  database integrity with testdb after each operation')"
	echo "$(eval_gettext '. downloading PKGBUILD directly from ABS cvs or AUR Unsupported')"
	echo "$(eval_gettext '. statistics on installed packages')"
	echo "$(eval_gettext 'Yaourt can be run as a non-privileged user (safest for AUR unsupported packages).')"
	echo "$(eval_gettext 'Root password will be required only when it is necessary.')"
	echo
	echo "$(eval_gettext 'USAGE: yaourt [OPTION...] <parameter>')"
	echo "$(eval_gettext 'example:')"
	echo "$(eval_gettext '   yaourt [regexp]        : search for matching strings (with *) and allows to install it')"
	echo "$(eval_gettext '   yaourt -S [packagename]: download package from repository, and fallback on AUR')"
	echo "$(eval_gettext '   yaourt -S [list file]  : download all packages stored in the first column of the given file')"
	echo "$(eval_gettext '   yaourt -Ss [regexp]    : search remote repositories and AUR for matching strings')"
	echo "$(eval_gettext '   yaourt -Syu --aur      : upgrade system + packages from aur')"
	echo "$(eval_gettext '   yaourt -Sybu --aur     : upgrade by building PKGBUILD + packages from aur')"
	echo "$(eval_gettext '   yaourt -Syu --devel    : upgrade all cvs/svn/mercurial packages (from aur)')"
	echo
	echo "$(eval_gettext 'OPTIONS:')"
	echo "$(eval_gettext ' yaourt''s options are the same as pacman, so check the pacman man page for more info')"
	echo "$(eval_gettext ' yaourt adds/enhances options marked with ''*''')"
	echo
	echo "$(eval_gettext 'General:')"
	echo "$(eval_gettext ' (-h, --help)                      give this help list')"
	echo "$(eval_gettext ' (-V, --version)                   give program version')"
	echo "$(eval_gettext ' --noconfirm                       do not ask for any confirmation')"
	echo "$(eval_gettext ' --tmp /where/you/want             use given directory for temporary files')"
	echo "$(eval_gettext ' --lightbg                         change colors for terminal with light background')"
	echo "$(eval_gettext ' --nocolor                         don''t use any color')"
	echo "$(eval_gettext ' --textonly                        good for scripting yaourt''s output')"
	echo "$(eval_gettext ' --stats                           display various statistics of installed packages')"
	echo
	echo "$(eval_gettext 'Install:')"
	echo "$(eval_gettext ' (-S, --sync)     <package>      * download package from repository, and fallback on aur')"
	echo "$(eval_gettext ' (-S, --sync)     <file>         * download all packages listed on the first column of the file')"
	echo "$(eval_gettext ' (-S, --sync) -b                 * builds the targets from source')"
	echo "$(eval_gettext ' (-S, --sync) -c, --clean          remove old packages from cache directory (use -cc for all)')"
	echo "$(eval_gettext ' (-S, --sync) -d, --nodeps         skip dependency checks')"
	echo "$(eval_gettext ' (-S, --sync) -f, --force          force install, overwrite conflicting files')"
	echo "$(eval_gettext ' (-S, --sync) -g, --groups         view all members of a package group')"
	echo "$(eval_gettext ' (-S, --sync) -i, --info         * view package (or PKGBUILD from AUR) information')"
	echo "$(eval_gettext ' (-S, --sync) -l, --list         * list all packages belonging to the specified repository')"
	echo "$(eval_gettext ' (-S, --sync) -p, --print-uris     print out download URIs for each package to be installed')"
	echo "$(eval_gettext ' (-S, --sync) --export <destdir> * export packages for local repository')"
	echo "$(eval_gettext ' (-S, --sync) --ignore <pkg>       skip some package')"
	echo "$(eval_gettext ' (-U, --upgrade) <file.pkg.tar.gz> upgrade a package from <file.pkg.tar.gz>')"
	echo "$(eval_gettext ' (<no option>) <file.pkg.tar.gz> * upgrade a package from <file.pkg.tar.gz>')"
	echo "$(eval_gettext ' (-G, --getpkgbuild) <pkg>       * Retrieve PKGBUILD and local sources for package name')"
	echo "$(eval_gettext '  --asdeps                         Install packages non-explicitly to be installed as a dependency')"
	echo "$(eval_gettext ' --ignorearch                      ignore incomplete arch field PKGBUILD')"
	echo
	echo "$(eval_gettext 'Upgrade:')"
	echo "$(eval_gettext ' -Su,  --sysupgrade                upgrade all packages that are out of date')"
	echo "$(eval_gettext ' -Su --aur                       * upgrade all aur packages')"
	echo "$(eval_gettext ' -Su --devel                     * upgrade all cvs/svn/mercurial/git/bazar packages')"
	echo "$(eval_gettext ' -Sud, --nodeps                    skip dependency checks')"
	echo "$(eval_gettext ' -Suf, --force                     force install, overwrite conflicting files')"
	echo "$(eval_gettext ' -Su --ignore <pkg>                skip some package')"
	echo "$(eval_gettext ' -Sy,  --refresh                   download fresh package databases from the server')"
	echo "$(eval_gettext ' --holdver                         avoid building last developement version for git/cvs/svn package')"
	echo "$(eval_gettext 'Note: yaourt always shows new orphans after package update')"
	echo
	echo "$(eval_gettext 'Downgrade:')"
	echo "$(eval_gettext ' -Su --upgrades                previously "downgrades"  reinstall all packages which are marked as "newer than extra or core" in -Su output')"
	echo "$(eval_gettext '           (this is specially for users who experience problems with [testing] and want to revert back to current)')"
	echo
	echo "$(eval_gettext 'Local search:')"
	echo "$(eval_gettext ' (-Q, --query) -e,            * list all packages explicitly installed')"
	echo "$(eval_gettext ' (-Q, --query) -d,            * list all packages installed as a dependency for another package')"
	echo "$(eval_gettext ' (-Q, --query) -t             * list all packages unrequired by any other package')"
	echo "$(eval_gettext '               -Qdt           * list missed packages installed as dependecies but not required')"
	echo "$(eval_gettext '               -Qet           * list top level packages explicitly installed')"
	echo "$(eval_gettext ' (-Q, --query) -g, --groups     view all members of a package group')"
	echo "$(eval_gettext ' (-Q, --query) -i, --info       view package information (use -ii for more)')"
	echo "$(eval_gettext ' (-Q, --query) -l, --list       list the contents of the queried package')"
	echo "$(eval_gettext ' (-Q, --query) -o  <string>   * search for package that owns <file> or <command>')"
	echo "$(eval_gettext ' (-Q, --query) -p, --file       will query the package file [package] instead of db')"
	echo "$(eval_gettext ' (-Q, --query) -s, --search   * search locally-installed packages for matching strings')"
	echo "$(eval_gettext ' (-Q) --backupfile  <file>    * query a database previously saved in a tar.bz2 file (with yaourt --backup)')"
	echo "$(eval_gettext ' Example: you want to reinstall archlinux with the same packages as your backup pacman-2008-02-22_10h12.tar.bz2')"
	echo "$(eval_gettext '  just run yaourt -Qet --backupfile pacman-2008-02-22_10h12.tar.bz2 > TopLevelPackages.txt')"
	echo "$(eval_gettext '  To reinstall later, just run yaourt -S TopLevelPackages.txt')"
	echo "$(eval_gettext ' (-Q) --date                  * list last installed packages, ordered by install date')"
	echo
	echo "$(eval_gettext 'Remote search:')"
	echo "$(eval_gettext ' (-S, --sync)  -s [string]    * search remote repositories and AUR for matching strings')"
	echo "$(eval_gettext ' <no option>      [string]    * search for matching strings + allows to install (interactiv)')"
	echo 
	echo "$(eval_gettext ' -Sq --depends    <pkg>       * list all packages which depends on <pkg>')"
	echo "$(eval_gettext ' -Sq --conflicts  <pkg>       * list all packages which conflicts with <pkg>')"
	echo "$(eval_gettext ' -Sq --provides   <pkg>       * list all packages which provides <pkg>')"
	echo "$(eval_gettext ' -Sq --replaces   <pkg>       * list all packages which replaces <pkg>')"
	echo
	echo "$(eval_gettext 'Clean:')"
	echo "$(eval_gettext ' (-C, --clean)                * manage, show diff .pacsave/.pacnew files')"
	echo "$(eval_gettext ' (-C, --clean) -c             * delete all .pacsave/.pacnew files')"
	echo "$(eval_gettext ' (-C, --clean) -d, --database * clean database (show obsolete repositories)')"
	echo "$(eval_gettext ' (-S, --sync)  -c               remove old packages from cache')"
	echo "$(eval_gettext ' (-S, --sync)  -c -c            remove all packages from cache')"
	echo "$(eval_gettext ' (-R, --remove)  <package>      remove packages')"
	echo "$(eval_gettext ' (-R, --remove) -c, --cascade   remove packages and all packages that depend on them')"
	echo "$(eval_gettext ' (-R, --remove) -d, --nodeps    skip dependency checks')"
	echo "$(eval_gettext ' (-R, --remove) -k, --dbonly    only remove database entry, do not remove files')"
	echo "$(eval_gettext ' (-R, --remove) -n, --nosave    remove configuration files as well')"
	echo "$(eval_gettext ' (-R, --remove) -s, --recursive remove dependencies also (that won''t break packages)')"
	echo "$(eval_gettext 'Note: yaourt always shows new orphans after package removal')"
	echo 
	echo "$(eval_gettext 'Backup:')"
	echo "$(eval_gettext ' (-B, --backup) [directory]     * backup pacman database in given directory')"
	echo "$(eval_gettext ' (-B, --backup) <file.tar.bz2>  * restore a previous backup of the pacman database')"
	echo
	echo
	echo "$(eval_gettext 'Runing yaourt as a non-privileged user requiers some entries in sudoers file:')"
	echo "$(eval_gettext '  - pacman (remove package + refresh database + install package from AUR package)')"
	echo "$(eval_gettext '  - pacdiffviewer (manage pacsave/pacnew files)')"
	echo "______________________________________"
	echo "$(eval_gettext 'written by Julien MISCHKOWITZ <wain@archlinux.fr>')"
	echo "$(eval_gettext ' homepage: http://archlinux.fr/yaourt-en')"
}
version(){
	plain "$(eval_gettext 'yaourt $VERSION is a pacman frontend with AUR support and more')"
	echo "$(eval_gettext 'homepage: http://archlinux.fr/yaourt-en')"
	echo "$(eval_gettext '      Copyright (C) 2008 Julien MISCHKOWITZ <wain@archlinux.fr>')"
	echo "$(eval_gettext '      This program may be freely redistributed under')"
	echo "$(eval_gettext '      the terms of the GNU General Public License')"
	exit
}
pacman_queuing(){
	# from nesl247
	if [ -f "$LOCKFILE" ]; then
		msg $(eval_gettext 'Pacman is currently in use, please wait.')
		while [ -f "$LOCKFILE" ]; do
			sleep 3
		done
	fi
}
title(){
	if [ $TERMINALTITLE -eq 0 -o -z "$DISPLAY" ]; then
		return 0
	fi
	case $TERM in
		rxvt*|xterm*|aterm)
		echo -n -e "\033]0;yaourt: $@\007"
		;;
	esac
}
die(){
	# reset term title
	tput sgr0
	if [ $TERMINALTITLE -eq 1 -a ! -z "$DISPLAY" ]; then
		echo -n -e "\033]0;$TERM\007"
	fi
	exit $1
}
parameters(){
	# Options
	MAJOR=""
	PRINTURIS=0
	INFO=0
	ROOT=0
	NEWROOT=""
	NODEPS=0
	ASDEPS=0
	SEARCH=0
	BUILD=0
	REFRESH=0
	SYSUPGRADE=0
	DOWNLOAD=0


	AUR=0
	HOLDVER=0
	IGNORE=0
	IGNOREPKG=""
	IGNOREARCH=0
	NEEDED=""
	CLEAN=0
	LIST=0
	CLEANDATABASE=0
	DATE=0
	UNREQUIRED=0
	CHANGELOG=0
	FOREIGN=0
	OWNER=0
	GROUP=0
	DOWNGRADE=""
	QUERYTYPE=""
	QUERYWHICH=0
	QUIET=0
	develpkg=0
	failed=0
	SUDOINSTALLED=0
	VERSIONPKGINSTALLED=0
	AURVOTEINSTALLED=0
	CUSTOMIZEPKGINSTALLED=0
	EXPLICITE=0
	DEPENDS=0

	ARGLIST=$@
	ARGSANS=""
	while [ "$#" -ne "0" ]; do
		case $1 in
			--help)
			usage
			exit 0
			;;
			--version) version ;;
			--clean)
			MAJOR="clean"
			ARGSANS="$ARGSANS $1"
			;;
			--remove)
			MAJOR="remove"
			ARGSANS="$ARGSANS $1"
			;;
			--upgrade)
			MAJOR="upgrade"
			ARGSANS="$ARGSANS $1"
			;;
			--upgrades)
			DOWNGRADE="--upgrades"
			;;
			--groups)
			GROUP=1
			ARGSANS="$ARGSANS $1"
			;;
			--getpkgbuild)
			MAJOR="getpkgbuild"
			;;
			--backup)
			MAJOR="backup"
			;;
			--backupfile)
			if [ ! -f "$2" -o ! -r "$2" ]; then
				_file=$2
				error $(eval_gettext 'Unable to read $_file file')
				die 1
			fi
			COLORMODE="--textonly"
			BACKUPFILE="$2"
			shift
			;;
			--query)
			MAJOR="query"
			ARGSANS="$ARGSANS $1"
			;;
			--sync)
			MAJOR="sync"
			ARGSANS="$ARGSANS $1"
			;;
			--info)
			INFO=1
			ARGSANS="$ARGSANS $1"
			;;
			--print-uris)
			PRINTURIS=1
			;;
			--list)
			LIST=1
			ARGSANS="$ARGSANS $1"
			;;
			--force)
			FORCE=1
			ARGSANS="$ARGSANS $1"
			;;
			--root)
			ROOT=1
			NEWROOT="$2"
			ARGSANS="$ARGSANS $1 $2"
			shift
			;;
			--stats)
			MAJOR="stats"
			break
			;;
			--sucre)
			MAJOR="sync"
			FORCE=1; SYSUPGRADE=1; REFRESH=1; AURUPGRADE=1; DEVEL=1; NOCONFIRM=2; EDITFILES=0
			ARGSANS="-Su --noconfirm --force"
			break
			;;
			--export)
			EXPORT=1
			EXPORTDIR="$2"
			shift
			;;
			--tmp)
			cd "$2"
			YAOURTTMPDIR="`pwd`/yaourt-tmp-`id -un`"
			cd - 1>/dev/null; shift
			;;
			--nodeps)
			NODEPS=1
			ARGSANS="$ARGSANS $1"
			;;
			--asdeps)
			ASDEPS=1
			ARGSANS="$ARGSANS $1"
			;;
			--deps)
			DEPENDS=1
			ARGSANS="$ARGSANS $1"
			;;
			--explicit)
			EXPLICITE=1
			ARGSANS="$ARGSANS $1"
			;;
			--build)
			BUILD=1
			ARGSANS="$ARGSANS $1"
			;;
			--refresh)
			if [ $REFRESH -eq 1 ]; then
				REFRESH=2
			else
				REFRESH=1
			fi
			ARGSANS="$ARGSANS $1"
			;;
			--sysupgrade)
			SYSUPGRADE=1
			ARGSANS="$ARGSANS $1"
			;;
			--downloadonly)
			DOWNLOAD=1
			ARGSANS="$ARGSANS $1"
			;;
			--foreign)
			FOREIGN=1
			ARGSANS="$ARGSANS $1"
			;;
			--noconfirm)
			NOCONFIRM=1
			EDITFILES=0
			ARGSANS="$ARGSANS $1"
			;;
			--needed)
			NEEDED="--needed"
			ARGSANS="$ARGSANS $1"
			;;
			--ignore)
			IGNORE=1
			IGNOREPKG="$IGNOREPKG --ignore $2"
			ARGSANS="$ARGSANS $1 $2"
			;;
			--aur) AUR=1; AURUPGRADE=1; AURSEARCH=1;;
			--svn) DEVEL=1
			warning $(eval_gettext '--svn is obsolete. Please use --devel instead');;
			--devel) DEVEL=1;;
			--database) CLEANDATABASE=1;;
			--date) DATE=1;;
			--depends) QUERYTYPE="depends";;
			--conflicts) QUERYTYPE="conflicts";;
			--provides) QUERYTYPE="provides";;
			--replaces) QUERYTYPE="replaces";;
			--lightbg) COLORMODE="--lightbg";;
			--nocolor) COLORMODE="--nocolor";;
			--textonly) COLORMODE="--textonly";;
			--unrequired) UNREQUIRED=1;;
			--changelog) CHANGELOG=1;;
			--holdver) HOLDVER=1;;
			--ignorearch) IGNOREARCH=1;;
			--*)
			#			usage
			#			exit 1
			ARGSANS="$ARGSANS $1"
			;;
			-*)
			ARGSANS="$ARGSANS $1"
			if [ `echo $1 | grep r` ]; then
				OPTIONAL=$2
			fi
			while getopts ":VABCRUFGQSbcdefghilmopqr:stuwy" opt $1 $OPTIONAL; do
				case $opt in
					V) version ;;
					B) MAJOR="backup";;
					C) MAJOR="clean" ;;
					G) MAJOR="getpkgbuild" ;;
					R) MAJOR="remove" ;;
					U) MAJOR="upgrade" ;;
					F) MAJOR="freshen" ;;
					Q) MAJOR="query" ;;
					S) MAJOR="sync" ;;
					b) BUILD=1 ;;
					c) CLEAN=1
					CHANGELOG=1;;
					d) NODEPS=1 #OR
					CLEANDATABASE=1
					DEPENDS=1 ;;
					e) EXPLICITE=1 ;;
					f) FORCE=1 ;;
					g) GROUP=1;;
					h)
					usage
					exit 0
					;;
					i) INFO=1 ;;
					l) LIST=1 ;;
					m) FOREIGN=1 ;;
					o) OWNER=1 ;;
					p) PRINTURIS=1 ;;
					q) QUERYWHICH=1; QUIET=1 ;;
					r)
					ROOT=1
					NEWROOT="$OPTARG"
					;;
					s) SEARCH=1 ;;
					t) UNREQUIRED=1 ;;
					u) 
					if [ $SYSUPGRADE -eq 1 ]; then
						DOWNGRADE="--upgrades"  
					else
						SYSUPGRADE=1
					fi;;
					w) DOWNLOAD=1 ;;
					y) 
					if [ $REFRESH -eq 1 ]; then
						REFRESH=2
					else
						REFRESH=1
					fi
					;;
				esac
			done
			;;
			*)
			args[${#args[@]}]=$1
			;;
		esac
		shift
	done

	# set color theme
	initcolor

	# 
	if [ "$MAJOR" != "query" ] && [ -f "$BACKUPFILE" ]; then
		error $(eval_gettext '--backupfile can be used only with --query')
		die 1
	elif [ "$MAJOR" = "" ]; then
		if [ -z "$ARGLIST" -o -n "$ARGSANS" ]; then
			usage
			die 1
		else
			for file in `echo $ARGLIST`; do
				if echo $file | grep -q ".pkg.tar.\(gz\|bz2\)"; then
					filelist[${#filelist[@]}]=$file
				fi
			done
			if [ ${#filelist[@]} -gt 0 ]; then
				args=( "${filelist[*]}" )
				ARGSANS="--upgrade $force $confirmation"
			else
				MAJOR="interactivesearch"
			fi
		fi
	fi
	return 0
}
manage_error(){
	if [ $1 -ne 0 ]; then
		error_package[${#error_package[@]}]="$PKG"
		return 1
	fi
	return 0
}

# Check if sudo is allowed for given command
is_sudo_allowed()
{
       [ $SUDOINSTALLED -eq 1 ] && (sudo -v && sudo -l "$@") &>/dev/null && return 0
       return 1
}

launch_with_su(){
	# try to launch $1 with sudo, else prompt for root password
	#msg "try to launch '${@}' with sudo"
	command=`echo $* | awk '{gsub(/LC_ALL=\"C\"/,""); print $1}'`

	if is_sudo_allowed "$command"; then
		#echo "Allowed to use sudo $command"
		sudo $@ || return 1
	else
		UID_ROOT=0
		if [ "$UID" -ne "$UID_ROOT" ]
		then
			# command output can be parsed
			echo -e $(eval_gettext 'You are not allowed to launch $command with sudo\nPlease enter root password') 1>&2 
		fi
		# hack: using tmp instead of YAOURTTMP because error file can't be removed without root password
		errorfile="/tmp/yaourt_error.$RANDOM"
		for i in 1 2 3; do 
			su --shell=/bin/bash --command "$* || touch $errorfile"
			if [ $? -eq 1 ] && [ ! -f "$errorfile" ]; then
				continue
			else
				if [ -f "$errorfile" ]; then
					return 1
				else
					return 0
				fi
			fi
		done
		return 1
	fi
}

###################################
### Package database functions  ###
###################################
isinstalled(){
	pacman -Qq $1 &>/dev/null
}
isavailable(){
	package-query -1Siq $1 || package-query -1Sq -t provides $1
}
isprovided(){
	package-query -Qq -t provides $1 
}
pkgversion(){
	# searching for version of the given package
	#grep -srl --line-regexp --include="desc" "$1" "$PACMANROOT/local" | xargs grep -A 1 "^%VERSION%$" | tail -n 1
	package-query -Qif "%v" $1
}
pkgdescription(){
	package-query -1Sif "%d" $1
}
sourcerepository(){
	# find the repository where the given package came from
	package-query -1SQif "%r" $1 
}

prepare_orphan_list(){
	# Prepare orphan list before upgrade and remove action
	mkdir -p "$YAOURTTMPDIR/orphans"
	ORPHANS_BEFORE="$YAOURTTMPDIR/orphans/orphans_before.$$"
	ORPHANS_AFTER="$YAOURTTMPDIR/orphans/orphans_after.$$"
	INSTALLED_BEFORE="$YAOURTTMPDIR/orphans/installed_before.$$"
	INSTALLED_AFTER="$YAOURTTMPDIR/orphans/installed_after.$$"
	# search orphans before removing or upgrading
	pacman -Qqt | LC_ALL=C sort > $ORPHANS_BEFORE
	# store package list before
	pacman -Q | LC_ALL=C sort > "$INSTALLED_BEFORE.full"
	cat "$INSTALLED_BEFORE.full" | awk '{print $1}' > $INSTALLED_BEFORE
}
show_new_orphans(){
	# search for new orphans after upgrading or after removing (exclude new installed package)
	pacman -Qqt | LC_ALL=C sort > "$ORPHANS_AFTER.tmp"
	pacman -Q | LC_ALL=C sort > "$INSTALLED_AFTER.full"
	cat "$INSTALLED_AFTER.full" | awk '{print $1}'  > $INSTALLED_AFTER

	LC_ALL=C comm -1 -3 "$INSTALLED_BEFORE" "$INSTALLED_AFTER" > "$INSTALLED_AFTER.newonly"
	LC_ALL=C comm -2 -3 "$ORPHANS_AFTER.tmp" "$INSTALLED_AFTER.newonly" | awk '{print $1}' > $ORPHANS_AFTER

	# show new orphans after removing/upgrading
	neworphans=$(LC_ALL=C comm -1 -3 "$ORPHANS_BEFORE" "$ORPHANS_AFTER" | awk '{print $1}' )
	if [ ! -z "$neworphans" ]; then
		plain $(eval_gettext 'Packages that were installed as dependencies but are no longer required by any installed package:')
		list "$neworphans"
	fi

	# testdb
	LC_ALL=C testdb | grep -v "Checking the integrity of the local database"

	# save original of backup files (pacnew/pacsave)
	if [ "$MAJOR" != "remove" ] && [ $AUTOSAVEBACKUPFILE -eq 1 ] && ! diff "$INSTALLED_BEFORE.full" "$INSTALLED_AFTER.full" > /dev/null; then
		msg $(eval_gettext 'Searching for original config files to save')
		launch_with_su "pacdiffviewer --backup"
	fi

}
cleandatabase(){
	# search in /var/lib/pacman/ for repositories
	# parmis ces dépôts, quels sont les paquetages aussi présents sur le système
	# si les paquets sont installés sur le systèmes, est-ce bien de CE dépôt qu'ils viennent ?
	# if repository is not used => remove it
	title "$(eval_gettext 'clean pacman database')"
	echo "$(eval_gettext 'Please wait...')"
	repositories=( `LC_ALL="C"; pacman --debug 2>/dev/null| grep "debug: opening database '" | awk '{print $4}' |uniq| tr -d "'"| grep -v 'local'` )
	downloadedrepositories=( `ls --almost-all $PACMANROOT/sync | grep -v "\(lost+found\|.*.db.tar.gz\)"` )
	for repository in ${downloadedrepositories[@]}; do
		used=0
		for pkg in `ls "$PACMANROOT/sync/$repository"`;do
			if [ -d "$PACMANROOT/local/$pkg" ];then
				pkgname=$(grep -A 1 "%NAME%" -F "$PACMANROOT/local/$pkg/desc" | tail -n 1)
				if [ "$(sourcerepository $pkgname)" = "$repository" ]; then
					used=1
					break
				fi
			fi
		done

		if [ $used -eq 0 ];then
			for repoinconfig in ${repositories[@]}; do
				if [ "$repository" = "$repoinconfig" ]; then
					break
				fi
			done
			if [ "$repository" = "$repoinconfig" ]; then
				#echo $(eval_gettext '$repository peut être retiré du fichier pacman.conf')
				unused_repository[${#unused_repository[@]}]=$repository
			else
				#echo $(eval_gettext '$repository peut être supprimé')
				old_repository[${#old_repository[@]}]=$repository
			fi
			continue
		fi
	done

	if [ ${#old_repository[@]} -gt 0 ]; then
		msg $(eval_gettext 'Some directories in /var/lib/pacman/sync are no more used and should be removed:')
		echo ${old_repository[@]}
		prompt $(eval_gettext 'Do you want to delete these directories ? ')$(yes_no 2)
		if [ "`userinput`" = "Y" ]; then
			cd $PACMANROOT/sync
			launch_with_su "rm -r ${old_repository[*]}"
			if [ $? -eq 0 ]; then
				msg "$(eval_gettext 'Your database is now optimized')"
			else
				error $(eval_gettext 'Problem when deleting directories')
			fi
		fi
	fi

	if [ ${#unused_repository[@]} -gt 0 ]; then
		echo
		msg "$(eval_gettext 'Some repositories in pacman.conf are no more used and can be removed:')"
		echo ${unused_repository[@]}
	fi

}

###################################
### Search functions            ###
###################################
search_packages_by_installreason(){
	# reason=0: explicitly installed
	# reason=1: installed as depends
	local reason=$1
	if [ $reason -eq 0 ]; then
		msg "$(eval_gettext 'Packages explicitly installed')"
	elif [ $reason -eq 1 ]; then
		msg "$(eval_gettext 'Packages installed as a dependency for another package')"
	fi

	for pkg in `ls "$PACMANROOT/local/"`; do
		if echo $(cat "$PACMANROOT/local/$pkg/desc" 2>/dev/null) | grep -q "%REASON% 1"; then
			pkgreason=1
		else
			pkgreason=0
		fi
		if [ $pkgreason -eq $reason ]; then echo "$pkg"; fi
	done

}

# Search for packages
# usage: search ($interactive, $result_file)
# return: none
search ()
{
	local interactive=${1:-0}
	local searchfile="$2"
	[ $interactive -eq 1 -a -z "$searchfile" ] && return 1
	i=1
	local search_option=""
	[ $AURSEARCH -eq 1 ] && search_option="$search_option -A"
	[ "$MAJOR" = "query" ] && search_option="$search_option -Q" || search_option="$search_option -S"
	[ "$LIST" -eq 1 ] && search_option="$search_option -l"
	package-query $search_option -sef "%n %r %v %l %g %w %o %d" ${args[*]} |
	while read package repository version lversion group votes outofdate description ; do
		[ $interactive -eq 1 ] && echo "${repository}/${package}" >> $searchfile
		line=`colorizeoutputline ${repository}/${NO_COLOR}${COL_BOLD}${package} ${COL_GREEN}${version}`
		if [ "$lversion" != "-" ]; then
			line="$line ${COL_INSTALLED}["
			if [ "$lversion" = "$version" ];then
				line="$line$(eval_gettext 'installed')"
			else
				line="$line${COL_RED}$lversion${COL_INSTALLED} $(eval_gettext 'installed')"
			fi
			line="${line}]${NO_COLOR}"
		fi
		[ "$group" != "-" ] && \
			line="$line${NO_COLOR} $COL_GROUP($group)$NO_COLOR"
		[ "$outofdate" != "-" ] && [ $outofdate -eq 1 ] && \
			line="$line${NO_COLOR} ${COL_INSTALLED}($(eval_gettext 'Out of Date'))"
		[ "$votes" != "-" ] && \
			line="$line${NO_COLOR} $COL_NUMBER($votes)${NO_COLOR}"
		[ $interactive -eq 1 ] && echo -ne "${COL_NUMBER}${i}${NO_COLOR} "
		echo -e "$line"
		echo -e "  $COL_ITALIQUE$description$NO_COLOR"
		(( i ++ ))
	done

	cleanoutput
}	


###################################
### MAIN PROGRAM                ###
###################################
# Basic init and librairies
source /usr/lib/yaourt/basicfunctions.sh || exit 1 
declare -a args
parameters $@


# grab environement options
if [ `type -p sudo` ]; then SUDOINSTALLED=1; fi
if [ `type -p versionpkg` ]; then VERSIONPKGINSTALLED=1; fi
if [ `type -p aurvote` ]; then AURVOTEINSTALLED=1; fi
if [ `type -p customizepkg` ]; then CUSTOMIZEPKGINSTALLED=1; fi

# Refresh
# todo: find a better way to remove "y"
if [ $REFRESH -gt 0 -a "$MAJOR" = "sync" ]; then
	title $(eval_gettext 'synchronizing package databases')
	ARGSANS=$(echo $ARGSANS | sed s/" --refresh"// | sed s/" -y"// \
	| tr -d "y" | sed -e 's/--snc/--sync/' -e 's/--quer/--query/' \
	-e 's/--ssupgrade/--sysupgrade/' -e 's/--downloadonl/--downloadonly/' )
	if [ $REFRESH -eq 1 ]; then
		pacman_queuing;	launch_with_su "$PACMANBIN -Sy"
	elif [ $REFRESH -eq 2 ]; then
		pacman_queuing; launch_with_su "$PACMANBIN -Syy"
	fi
fi

# BUILD OPTION to use
YAOURTCOMMAND="$0 $COLORMODE"
if [ $BUILD -eq 1 ]; then
	BUILDPROGRAM="$YAOURTCOMMAND -Sb"
else
	BUILDPROGRAM="$YAOURTCOMMAND -S"
fi
if [ $NOCONFIRM -gt 0 ]; then 
	BUILDPROGRAM="${BUILDPROGRAM} --noconfirm"
	confirmation="--noconfirm"
fi
if [ $FORCE -eq 1 ]; then force="--force"; fi
if [ $NODEPS -eq 1 ]; then 
	BUILDPROGRAM="${BUILDPROGRAM} --nodeps"
	nodeps="--nodeps"
fi
if [ $IGNOREARCH -eq 1 ]; then 
	BUILDPROGRAM="${BUILDPROGRAM} --ignorearch"
fi
if [ $ASDEPS -eq 1 ]; then 
	BUILDPROGRAM="${BUILDPROGRAM} --asdeps"
	asdeps="--asdeps"
fi

if [ $EXPORT -eq 1 ]; then BUILDPROGRAM="$BUILDPROGRAM --export $EXPORTDIR"; fi

# Action
case "$MAJOR" in
	remove)
	#msg "Remove"
	title $(eval_gettext 'remove packages')
	prepare_orphan_list
	# remove with pacman
	pacman_queuing;	launch_with_su "$PACMANBIN $ARGSANS ${args[*]}"
	show_new_orphans
	;;

	clean)
	#msg "Clean"
	if [ $CLEANDATABASE -eq 1 ]; then
		cleandatabase
	else
		if [ $CLEAN -eq 1 ]; then
			launch_with_su "pacdiffviewer -c"
		else
			launch_with_su "pacdiffviewer"
		fi
	fi
	;;

	stats)
	loadlibrary pacman_conf
	loadlibrary alpm_stats
	tmp_files="$YAOURTTMPDIR/stats.$$"
	mkdir -p "$tmp_files" || die 1
	buildpackagelist
	#clear
	showpackagestats
	showrepostats
	showdiskusage
	;;

	getpkgbuild)
	title "$(eval_gettext 'get PKGBUILD')"
	loadlibrary aur
	loadlibrary abs
	# don't replace the file if exist
	if [ -f "./PKGBUILD" ]; then
		prompt $(eval_gettext 'PKGBUILD file already exist. Replace ? ')$(yes_no 1)
		[ "`userinput`" = "N" ] && die 1
	fi

	if [ ${#args[@]} -gt 1 ]; then
		warning $(eval_gettext 'only one package is allowed')
	elif [ ${#args[@]} -eq 0 ]; then
		warning $(eval_gettext 'error: no targets specified (use -h for help)')
		die 1
	fi
	PKG=${args[0]}
	#msg "Get PKGBUILD for $PKG"
	build_or_get "$PKG"
	;;

	backup)
	case ${#args[@]} in
		0) savedir="`pwd`";;
		1)  if [ -d "${args[0]}" ]; then
				savedir=`echo "${args[0]}" | sed "s/\/$//1"`
			elif [ -f "${args[0]}" ]; then
				backupfile="${args[0]}"
			fi
		;;
		*) error $(eval_gettext 'wrong argument'); die 1
		;;
	esac
	loadlibrary alpm_backup
	if [ ! -z "$savedir" ]; then
		save_alpm_db || die 1
	elif [ ! -z "$backupfile" ]; then
		restore_alpm_db || die 1
	else
		error $(eval_gettext 'wrong argument'); die 1
	fi
	;;
	
	sync)
	#msg "Synchronisation"
	if [ $GROUP -eq 1 ]; then
		title $(eval_gettext 'show groups')
		pacman_queuing;	eval $PACMANBIN -Sg ${args[*]}
	elif [ $QUERYWHICH -eq 1 ]; then
		if [ "$QUERYTYPE" = "" ]; then usage; die 1; fi
		if [ ${#args[@]} -lt 1 ]; then die 1; fi
		title $(eval_gettext 'query packages')
		loadlibrary pacman_conf
		list_repositories
		loadlibrary alpm_query
		for arg in ${args[@]}; do
			msg $(eval_gettext 'packages which '$QUERYTYPE' on $arg:')
			searchforpackageswhich "$QUERYTYPE" "$arg"
		done
	elif [ $LIST -eq 1 ];then
		#Searching all packages in repos
		title $(eval_gettext 'listing all packages in repos')
		msg $(eval_gettext 'Listing all packages in repos')
		AURSEARCH=0 search 0
	elif [ $SEARCH -eq 1 ]; then	
		# Searching for/info/install packages
		#msg "Recherche dans ABS"
		if [ $QUIET -eq 1 ]; then
			eval $PACMANBIN $ARGSANS --search ${args[*]}
			die 0
		fi
		search
		cleanoutput
	elif [ $CLEAN -eq 1 ]; then 
		#msg "clean sources files"
		launch_with_su "$PACMANBIN $ARGSANS ${args[*]}"
	elif [ $INFO -eq 1 ]; then
		#msg "Information"
		loadlibrary aur
		for arg in ${args[@]}; do
			title $(eval_gettext 'Information for $arg')
			if isavailable ${arg#*/} && [ "${arg%/*}" != "aur" ]; then
				eval $PACMANBIN -Si $arg
			else
				info_from_aur "${arg#*/}"
			fi
		done
	elif [ $PRINTURIS -eq 1 ]; then
		$PACMANBIN -Sp "${args[@]}"
	elif [ $SYSUPGRADE -eq 0 -a ${#args[@]} -eq 0 -a $REFRESH -eq 0 ]; then
		prepare_orphan_list
		msg $(eval_gettext 'yaourt: no argument'):wa
		
		pacman_queuing;	eval $PACMANBIN $ARGSANS
		show_new_orphans
	elif [ $SYSUPGRADE -eq 0 ]; then
		#msg "Install ($ARGSANS)"
		loadlibrary abs
		loadlibrary aur
		sync_packages
	elif [ $SYSUPGRADE -eq 1 ]; then
		#msg "System Upgrade"
		loadlibrary abs
		loadlibrary aur
		sysupgrade
		# Upgrade all AUR packages or all Devel packages
		if [ $DEVEL -eq 1 ]; then upgrade_devel_package; fi
		if [ $AURUPGRADE -eq 1 ]; then upgrade_from_aur; fi
		#show package which have not been installed
		if [ ${#error_package[@]} -gt 0 ]; then
			echo -e "${COL_YELLOW}" $(eval_gettext 'Following packages have not been installed:')"${NO_COLOR}"
			echo "${error_package[*]}"
		fi
		show_new_orphans
	fi
	;;

	query)
	# action = query
	loadlibrary alpm_query
	# query in a backup file or in current alpm db
	if [ ! -z "$BACKUPFILE" ]; then
		loadlibrary alpm_backup
		if is_an_alpm_backup "$BACKUPFILE"; then
			title $(eval_gettext 'Query backup database')
			msg $(eval_gettext 'Query backup database')
		PACMANROOT="$backupdir/"
			eval $PACMANBIN --dbpath "$backupdir/" $ARGSANS ${args[*]}
		else
			die 1
		fi
	elif [ $OWNER -eq 1 ]; then
		search_which_package_owns
	elif	[ $DEPENDS -eq 1 -a $UNREQUIRED -eq 1 ]; then
		search_forgotten_orphans
	elif	[ $SEARCH -eq 1 ]; then
		AURSEARCH=0 search 0
	elif [ $LIST -eq 1 -o $INFO -eq 1 -o $SYSUPGRADE -eq 1 -o $CHANGELOG -eq 1 ]; then
		# just run pacman -Ql or pacman -Qi
		eval $PACMANBIN $ARGSANS ${args[*]}
	else
		list_installed_packages
	fi
	;;
	
	interactivesearch)
	tmp_files="$YAOURTTMPDIR/search"
	mkdir -p $tmp_files || die 1
	searchfile=$tmp_files/interactivesearch.$$>$searchfile || die 1
	search 1 "$searchfile"
	if [ ! -s "$searchfile" ]; then
		die 0	
	fi
	prompt $(eval_gettext 'Enter n° (separated by blanks, or a range) of packages to be installed')
	read -ea packagesnum
	if [ ${#packagesnum[@]} -eq 0 ]; then die 0; fi
	for line in ${packagesnum[@]}; do
		if echo $line | grep -q "[0-9]-[0-9]"; then
			for multipackages in `seq ${line/-/ }`;do
				packages[${#packages[@]}]=$(sed -n ${multipackages}p $searchfile)
			done
		elif echo $line | grep -q "[0-9]"; then
			packages[${#packages[@]}]=$(sed -n ${line}p $searchfile)
		else
			die 1
		fi
	done
	$BUILDPROGRAM ${packages[@]}
	;;
	
	*)
	#msg "Other action"
	prepare_orphan_list
	pacman_queuing;	launch_with_su "$PACMANBIN $ARGSANS ${args[*]}" || { plain $(eval_gettext 'press a key to continue'); read; }
	show_new_orphans
	;;
esac
die $failed
