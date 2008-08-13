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
VERSION="0.9.01"
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
}
setPARCH(){
	if [ "$arch" = "any" ]; then
		PARCH='any'
	else
		PARCH="$CARCH"	
	fi
}
find_pkgbuild_deps (){
	unset DEPS DEP_AUR
	readPKGBUILD
	if [ -z "$pkgname" ]; then
		echo $(eval_gettext 'Unable to read PKGBUILD for $PKG')
		return 1
	fi
	for dep in $(echo "${depends[@]} ${makedepends[@]}" | tr -d '\\')
	do
		DEPS[${#DEPS[@]}]=$(echo $dep | sed 's/=.*//' \
		| sed 's/>.*//' \
		| sed 's/<.*//')
	done
	[ ${#DEPS[@]} -eq 0 ] && return 0

	echo
	msg "$(eval_gettext '$PKG dependencies:')"
	DEP_PACMAN=0

	for dep in ${DEPS[@]}; do
		if isinstalled $dep; then echo -e " - ${COL_BOLD}$dep${NO_COLOR}" $(eval_gettext '(already installed)'); continue; fi
		if isprovided $dep; then echo -e " - ${COL_BOLD}$dep${NO_COLOR}" $(eval_gettext '(package that provides ${dep} already installed)'); continue; fi
		if isavailable $dep; then echo -e " - ${COL_BLUE}$dep${NO_COLOR}" $(eval_gettext '(package found)'); DEP_PACMAN=1; continue; fi
		echo -e " - ${COL_YELLOW}$dep${NO_COLOR}" $(eval_gettext '(building from AUR)') 
		DEP_AUR[${#DEP_AUR[@]}]=$dep 
	done

}
install_package(){
	# Install, export, copy package after build 
	source /etc/makepkg.conf || return 1
	setPARCH
	if [ $failed -ne 1 ]; then
		if [ $EXPORT -eq 1 ]
		then
			#msg "Delete old ${pkgname} package"
			# remove this line if you want to keep old pkg.tar.gz files or use rm -i for interactive mode
			#rm -i $EXPORTDIR/$pkgname-[0-9]*.pkg.tar.gz
			rm -f $EXPORTDIR/$pkgname-[0-9]*-*.pkg.tar.gz
			msg $(eval_gettext 'Exporting ${pkgname} to ${EXPORTDIR} repository')
			mkdir -p $EXPORTDIR/$pkgname
			manage_error $? || { error $(eval_gettext 'Unable to write ${EXPORTDIR}/${pkgname}/ directory'); die 1; }
			readPKGBUILD
			unset localsource
			for src in ${source[@]}; do
				if [ `echo $src | grep -v ^\\\\\\(ftp\\\\\\|http\\\\\\)` ]; then
					localsource[${#localsource[@]}]=$src
				fi
			done
			localsource[${#localsource[@]}]="PKGBUILD"
			if [ ! -z "$install" ]; then localsource[${#localsource[@]}]="$install";fi
			for file in ${localsource[@]}; do
				cp -pf "$file" $EXPORTDIR/$pkgname/ 
				manage_error $? || { error $(eval_gettext 'Unable to copy $file to ${EXPORTDIR}/${pkgname}/ directory'); return 1; }
			done
			localsource[${#localsource[@]}]="$pkgname-$pkgver-$pkgrel-$PARCH.pkg.tar.gz" 
			cp -fp ./$pkgname-$pkgver-$pkgrel-$PARCH.pkg.tar.gz $EXPORTDIR/ || error $(eval_gettext 'can not copy $pkgname-$pkgver-$pkgrel-$PARCH.pkg.tar.gz to $EXPORTDIR')
		fi

		echo
		if [ $NOCONFIRM -eq 0 ]; then
			CONTINUE_INSTALLING="V"
			while [ "$CONTINUE_INSTALLING" = "V" -o "$CONTINUE_INSTALLING" = "C" ]; do
				echo -e "${COL_ARROW}==>  ${NO_COLOR}${COL_BOLD}"$(eval_gettext 'Continue installing ''$PKG''? ') $(yes_no 1)"${NO_COLOR}" >&2
				prompt $(eval_gettext '[v]iew package contents   [c]heck package with namcap')
				CONTINUE_INSTALLING=$(userinput "YNVC")
				echo
				if [ "$CONTINUE_INSTALLING" = "V" ]; then
					eval $PACMANBIN --query --list --file ./$pkgname-$pkgver-$pkgrel-$PARCH.pkg.tar.gz
					eval $PACMANBIN --query --info --file ./$pkgname-$pkgver-$pkgrel-$PARCH.pkg.tar.gz
				elif [ "$CONTINUE_INSTALLING" = "C" ]; then
					echo
					if [ `type -p namcap` ]; then
						namcap ./$pkgname-$pkgver-$pkgrel-$PARCH.pkg.tar.gz
					else
						warning $(eval_gettext 'namcap is not installed')
					fi
					echo
				fi
			done
		fi

		if [ "$CONTINUE_INSTALLING" = "N" ]; then
			msg $(eval_gettext 'Package not installed')
			failed=1
		else
			[ -z "$CONTINUE_INSTALLING" ] && echo
			pacman_queuing;	launch_with_su "$PACMANBIN --force --upgrade $asdeps $confirmation ./$pkgname-$pkgver-$pkgrel-$PARCH.pkg.tar.gz"
			if [ $? -ne 0 ]; then
				failed=1
			else
				failed=0
			fi
		fi
		if [ $failed -eq 1 ]; then 
			warning $(eval_gettext 'Your package is saved in /tmp/$pkgname-$pkgver-$pkgrel-$PARCH.pkg.tar.gz')
			cp -i "./$pkgname-$pkgver-$pkgrel-$PARCH.pkg.tar.gz" /tmp/ || warning $(eval_gettext 'Unable to copy $pkgname-$pkgrel-$PARCH.pkg.tar.gz to /tmp/ directory')
		fi
		cd ../..

	else
		dirtosave=`pwd`
		cd ../
		if [ $SYSUPGRADE -ne 1 -a $develpkg -eq 0 ]; then
			plain $(eval_gettext 'Build process aborted for $PKG')
			if [ $NOCONFIRM -eq 0 ]; then
				prompt $(eval_gettext 'Copy ${PKG} directory to /var/abs/local ? ') $(yes_no 2)
				CONTINUE_COPY=$(userinput)
				echo
			fi
			if [ "$CONTINUE_COPY" = "Y" ]; then
				mv "$dirtosave" "/var/abs/local/$PKG" || launch_with_su "mv ${dirtosave} /var/abs/local/${PKG}" || { warning $(eval_gettext 'Unable to copy $PKG directory to $ABSROOT/local'); return 1; }
			fi
		fi
	fi
	return $failed
}
edit_file(){
	local file=$1
	if [ -z "$EDITOR" ]; then
		echo -e ${COL_RED}$(eval_gettext 'Please add \$EDITOR to your environment variables')
		echo -e ${NO_COLOR}$(eval_gettext 'for example:')
		echo -ne ${COL_ARROW}"==> "${NO_COLOR} $(eval_gettext 'Edit PKGBUILD with: ')
		echo $(eval_gettext '(replace gvim with your favorite editor)')
		echo
		echo -ne ${COL_ARROW}"==> "${NO_COLOR}$(eval_gettext 'Edit $file with: ')
		read -e EDITOR
	fi
	if [ "$EDITOR" = "gvim" ]; then edit_prog="gvim --nofork"; else edit_prog="$EDITOR";fi
	( $edit_prog "$file" )
	wait
}
build_package(){
	failed=0
	# Test PKGBUILD for last svn/cvs/... version
	msg "$(eval_gettext 'Building and installing package')"
	develpkg=0
	if [ ! -z "${_svntrunk}" -a ! -z "${_svnmod}" ] \
		|| [ ! -z "${_cvsroot}" -a ! -z "${_cvsmod}" ] \
		|| [ ! -z "${_hgroot}" -a ! -z "${_hgrepo}" ] \
		|| [ ! -z "${_darcsmod}" -a ! -z "${_darcstrunk}" ] \
		|| [ ! -z "${_bzrtrunk}" -a ! -z "${_bzrmod}" ] \
		|| [ ! -z "${_gitroot}" -a ! -z "${_gitname}" ]; then
		develpkg=1
	fi

	if [ $develpkg -eq 1 ];then
		#msg "Building last CVS/SVN/HG/GIT version"
		wdirDEVEL="/var/abs/local/yaourtbuild/${pkgname}"
		# Using previous build directory
		if [ -d "$wdirDEVEL" ]; then
			if [ $NOCONFIRM -eq 0 ]; then
				prompt $(eval_gettext 'Yaourt has detected previous ${pkgname} build. Do you want to use it (faster) ? ') $(yes_no 1)
				USE_OLD_BUILD=$(userinput)
				echo
			fi
			if [ "$USE_OLD_BUILD" != "N" ] || [ $NOCONFIRM -gt 0 ]; then
				cp ./* "$wdirDEVEL/"
				cd $wdirDEVEL
			fi
		else
			mkdir -p $wdirDEVEL
			if [ $? -eq 1 ]; then
				warning $(eval_gettext 'Unable to write in ${wdirDEVEL} directory. Using /tmp directory')
				wdirDEVEL="$wdir/$PKG"
				sleep 3
			else
				cp -r ./* "$wdirDEVEL/"
				cd "$wdirDEVEL"
			fi
		fi

		# Use versionpkg to find latest version
		if [ $VERSIONPKGINSTALLED -eq 1 -a $HOLDVER -eq 0 ]; then
			msg $(eval_gettext 'Searching new CVS/SVN/GIT revision for $PKG')
			versionpkg --modify-only --force
			local localversion=`grep -rl --include="desc" "^$PKG$" "$PACMANROOT/local" | sed -e "s/\/desc//" -e "s/.*\///"`
			readPKGBUILD
			if [ "$localversion" = "$pkgname-$pkgver-$pkgrel" ]; then
				msg $(eval_gettext 'There is no CVS/SVN/GIT update available for $PKG.. Aborted')
				sleep 1
				return 90
			fi
		fi
	fi

	# Check for arch variable
	readPKGBUILD
	if [ -z "$arch" ]; then
		source /etc/makepkg.conf
		[ -z "$CARCH" ] && CARCH="i686"
		warning $(eval_gettext 'the arch variable is missing !\nyaourt will add arch=(''$CARCH'') automatically.')
		sed -i "/^build/iarch=('$CARCH')\n" ./PKGBUILD
	fi

	# Build 
	mkpkg_opt="$confirmation"
	[ $NODEPS -eq 1 ] && mkpkg_opt="$mkpkg_opt -d"
	[ $HOLDVER -eq 1 ] && mkpkg_opt="$mkpkg_opt --holdver"
	if [ $runasroot -eq 1 ]; then 
		pacman_queuing; eval $INENGLISH PKGDEST=`pwd` nice -n 15 makepkg $mkpkg_opt --asroot --syncdeps --force -p ./PKGBUILD
	else
		if [ $SUDOINSTALLED -eq 1 ]; then
			pacman_queuing; eval $INENGLISH PKGDEST=`pwd` nice -n 15 makepkg $mkpkg_opt --syncdeps --force -p ./PKGBUILD
		else
			eval $INENGLISH PKGDEST=`pwd` nice -n 15 makepkg $mkpkg_opt --force -p ./PKGBUILD
		fi
	fi

	if [ $? -ne 0 ]; then
		error $(eval_gettext 'Makepkg was unable to build $PKG package.')
		failed=1
	fi

	readPKGBUILD
	if [ -z "$pkgname" ]; then
		echo $(eval_gettext 'Unable to read PKGBUILD for $PKG')
		return 1
	fi
	return $failed
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
		plain $(eval_gettext '>        SourceforgeMirror belnet')
		plain $(eval_gettext '>  (replace belnet with the name of your favorite sourceforge mirror)')
		echo
		list "1.surfnet(NL) 2.ufpr(BR) 3.heanet(IE) 4.easynews(US) 5.umn(US) 6.switch(CH) 7.belnet(BE) 8.kent(UK)"
		list "9.mesh(DE) 10.optusnet(AU) 11.jaist(JP) 12.puzzle(CH) 13.superb-east(US) 14.nchc(TW) 15.superb-west(US)"
		prompt $(eval_gettext 'Enter the number corresponding tor the mirror or the mirror''s name or press Enter to use automatic redirect (much slower)')
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
### Sync functions              ###
###################################
upgrade_devel_package(){
	tmp_files="$YAOURTTMPDIR/search/"
	mkdir -p $tmp_files
	local i=0
	title $(eval_gettext 'upgrading SVN/CVS/HG/GIT package')
	msg $(eval_gettext 'upgrading SVN/CVS/HG/GIT package')
	loadlibrary pacman_conf
	create_ignorepkg_list || error $(eval_gettext 'list ignorepkg in pacman.conf')
	for PKG in $(pacman -Qq | grep "\-\(svn\|cvs\|hg\|git\|bzr\|darcs\)\ ")
	do
		if grep "^${PKG}$" $tmp_files/ignorelist > /dev/null; then
			echo -e "${PKG}: ${COL_RED} "$(eval_gettext '(ignored from pacman.conf)')"${NO_COLOR}"
		else
			devel_package[$i]=$PKG
			(( i ++ ))
		fi
	done
	[ $i -lt 1 ] && return 0
	plain "\n---------------------------------------------"
	plain $(eval_gettext 'SVN/CVS/HG/GIT/BZR packages that can be updated from ABS or AUR:')
	echo "${devel_package[@]}"
	if [ $NOCONFIRM -eq 0 ]; then
		prompt $(eval_gettext 'Do you want to update these packages ? ') $(yes_no 1)
		[ "`userinput`" = "N" ] && return 0
	fi
	for PKG in ${devel_package[@]}; do
		local repository=`sourcerepository $PKG`
		case $repository in
			core|extra|unstable|testing|community)	
			BUILD=1
			repos_package[${#repos_package[@]}]=${PKG}
			;;
			*)	       
			install_from_aur "$PKG" 
			;;
		esac
	done
	[ ${#repos_package[@]} -gt 0 ] && install_from_abs "${repos_package[*]}"
}

###################################
### General functions           ###
###################################

usage(){
	echo "$(eval_gettext '    ---  Yaourt version $VERSION  ---')"
	echo
	echo "$(eval_gettext 'yaourt is a pacman frontend whith a lot of features like:')"
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
	echo "$(eval_gettext ' --stats                           display various statistics of installed pacakges')"
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
	echo "$(eval_gettext ' -Su --downgrade                *  reinstall all packages which are marked as "newer than extra or core" in -Su output')"
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
	echo
	echo "$(eval_gettext 'Remote search:')"
	echo "$(eval_gettext ' (-S, --sync)  -s [string]    * search remote repositories and AUR for matching strings')"
	echo "$(eval_gettext ' <no option>      [string]    * search for matching strings + allows to install (interactiv)')"
	echo 
	echo "$(eval_gettext ' -Sq --depends    <pkg>       * list all packages which depends on <pkg>')"
	echo "$(eval_gettext ' -Sq --conflicts  <pkg>       * list all packages which conflicts with <pkg>')"
	echo "$(eval_gettext ' -Sq --provides   <pkg>       * list all packages which provides <pkg>')"
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
	echo "$(eval_gettext '  - pacman (remove package + refresh database + install AUR''s package)')"
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
	if [ $TERMINALTITLE -eq 0 -o -z "$DISPLAY" ]; then
		exit $1
	fi
	echo -n -e "\033]0;$TERM\007"
	tput sgr0
	exit $1
}
parameters(){
	# Options
	MAJOR=""
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
	NEEDED=""
	CLEAN=0
	LIST=0
	CLEANDATABASE=0
	UNREQUIRED=0
	CHANGELOG=0
	FOREIGN=0
	OWNER=0
	GROUP=0
	DOWNGRADE=0
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
			--downgrade)
			DOWNGRADE=1
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
			initcolor
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
			FORCE=1; SYSUPGRADE=1; REFRESH=1; AURUPGRADE=1; DEVEL=1; NOCONFIRM=2; EDITPKGBUILD=0
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
			EDITPKGBUILD=0
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
			--depends) QUERYTYPE="%DEPENDS%";;
			--conflicts) QUERYTYPE="%CONFLICTS%";;
			--provides) QUERYTYPE="%PROVIDES%";;
			--lightbg) COLORMODE="--lightbg"; initcolor;;
			--nocolor) COLORMODE="--nocolor"; initcolor;;
			--textonly) COLORMODE="--textonly"; initcolor;;
			--unrequired) UNREQUIRED=1;;
			--changelog) CHANGELOG=1;;
			--holdver) HOLDVER=1;;
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
			while getopts ":VABCRUFGQSbcdefghilmoqr:stuwy" opt $1 $OPTIONAL; do
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
					q) QUERYWHICH=1; QUIET=1 ;;
					r)
					ROOT=1
					NEWROOT="$OPTARG"
					;;
					s) SEARCH=1 ;;
					t) UNREQUIRED=1 ;;
					u) SYSUPGRADE=1 ;;
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
	if [ "$MAJOR" != "query" ] && [ -f "$BACKUPFILE" ]; then
		error $(eval_gettext '--backupfile can be used only with --query')
		die 1
	elif [ "$MAJOR" = "" ]; then
		if [ -z "$ARGLIST" -o -n "$ARGSANS" ]; then
			usage
			die 1
		else
			for file in `echo $ARGLIST`; do
				if echo $file | grep -q ".pkg.tar.gz"; then
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

launch_with_su(){
	# try to launch $1 with sudo, else prompt for root password
	#msg "try to launch '${@}' with sudo"
	command=`echo $@ | awk '{print $1}'`
	if [ $SUDOINSTALLED -eq 1 ] && sudo -l | grep "\(${command}\ *$\|ALL\)" 1>/dev/null; then
		#echo "Allowed to use sudo $command"
		sudo $@ || return 1
	else
		UID_ROOT=0
		if [ "$UID" -ne "$UID_ROOT" ]
		then
			echo -e $(eval_gettext 'You''re not allowed to launch $command with sudo\nPlease enter root password')
		fi
		# hack: using tmp instead of YAOURTTMP because error file can't be removed without root password
		errorfile="/tmp/yaourt_error.$RANDOM"
		for i in 1 2 3; do 
			su root --command "$* || touch $errorfile"
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
	if [ ${#allpkginstalled[@]} -eq 0 ]; then
		allpkginstalled=( `pacman -Qq` )
	fi
	for installedpkg in ${allpkginstalled[@]};do
		if [ "$1" = "$installedpkg" ]; then return 0; else continue; fi
	done
	return 1
}
isavailable(){
	# is the package available in repositories ?
	if [ ${#allpkgavailable[@]} -eq 0 ]; then
		allpkgavailable=( `pacman -Sl | awk '{print $2}'` )
	fi
	for pkgavailable in ${allpkgavailable[@]};do
		if [ "$1" = "$pkgavailable" ]; then return 0; else continue; fi
	done
	return 1
}
isprovided(){
	local candidates=( `grep -srl --line-regexp --include="depends" "$1" "$PACMANROOT/local"` )
	for file in ${candidates[@]};do
		if echo $(cat $file) | grep -q "%PROVIDES%.*$1"; then return 0; else continue;fi
	done
	return 1
}
pkgversion(){
	# searching for version of the given package
	#grep -srl --line-regexp --include="desc" "$1" "$PACMANROOT/local" | xargs grep -A 1 "^%VERSION%$" | tail -n 1
	pacman -Q $1 | awk '{print $2}'
}
sourcerepository(){
	# find the repository where the given package came from
	local lrepository=`pacman -Si $1 2>/dev/null| head -n1 | awk '{print $3}'`
	if [ -z "$lrepository" ]; then
		echo "local"
	else
		echo $lrepository
	fi
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
	comm -1 -3 "$INSTALLED_BEFORE" "$INSTALLED_AFTER" > "$INSTALLED_AFTER.newonly"
	comm -2 -3 "$ORPHANS_AFTER.tmp" "$INSTALLED_AFTER.newonly" | awk '{print $1}' > $ORPHANS_AFTER

	# show new orphans after removing/upgrading
	neworphans=$(comm -1 -3 $ORPHANS_BEFORE $ORPHANS_AFTER | awk '{print $1}' )
	if [ ! -z "$neworphans" ]; then
		plain $(eval_gettext 'Packages that were installed as dependencies but are no longer required by any installed package:')
		list "$neworphans"
	fi

	# testdb
	testdb

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

###################################
### AUR specific functions      ###
###################################
aurcomments(){
	wget --quiet "${AUR_URL3}${1}" -O - \
	| tr '\r' '\n' | sed -e '/-- End of main content --/,//d' \
	-e 's|<[^<]*>||g' \
	-e 's|&quot;|"|g' \
	-e 's|&lt;|<|g' \
	-e 's|&gt;|>|g' \
	-e '/^ *$/d' > ./aurpage
	if [ $AURCOMMENT -eq 1 ]; then
		numcomment=0
		rm -rf ./comments || error $(eval_gettext 'can not remove old comments')
		mkdir -p comments
		cat ./aurpage | sed '1,/Comments/d' |
		while read line; do
			if echo $line |grep -q "Comment by:"; then
				(( numcomment ++ ))
				if [ $numcomment -gt $MAXCOMMENTS -a $MAXCOMMENTS -ne 0 ]; then
					msg $(eval_gettext 'Last $MAXCOMMENTS comments ordered by date ($ORDERBY):')
					break
				fi
			fi
			echo $line >> comments/$numcomment
		done

		numcomment=`ls comments/ | wc -l`
		if [ $numcomment -gt $MAXCOMMENTS -a $MAXCOMMENTS -ne 0 ]; then
			limit=$MAXCOMMENTS
		else
			limit=$numcomment
		fi      
		if [ "$ORDERBY" = "asc" ]; then
			liste=`seq $limit -1 1`
		elif [ "$ORDERBY" = "desc" ]; then
			liste=`seq 1 1 $limit`
		fi
		for comment in ${liste[*]}; do
			if [ -f "comments/$comment" ]; then
				cat comments/$comment |
				while read line; do
					echo -e ${line/#Comment by:/\\n${COL_YELLOW}Comment by:}$NO_COLOR
				done
			fi
		done
	fi
	echo
	grep "First Submitted" ./aurpage | sed "s/First/\n      &/" |sort
}
findaurid(){
	wget -q -O - "http://aur.archlinux.org/rpc.php?type=info&arg=$1"| sed -e 's/^.*{"ID":"//' -e 's/",".*$//'| sed '/^$/d'
}
vote_package(){
	# vote for package
	# Check if this package has been voted on AUR, and vote for it
	if [ $AURVOTEINSTALLED -eq 0 ]; then
		echo -e "${COL_ITALIQUE}"$(eval_gettext 'If you like this package, please install aurvote\nand vote for its inclusion/keeping in [community]')"${NO_COLOR}"
	else
		echo
		_pkg=$1
		msg $(eval_gettext 'Checking for $_pkg''s vote status')
		pkgvote=`aurvote --id --check "$1/$2"`
		if [ "${pkgvote}" = "already voted" ]; then
			_pkg=$1
			echo $(eval_gettext 'You have already voted for $_pkg inclusion/keeping in [community]')
		elif [ "$pkgvote" = "not voted" ]; then
			echo
			if [ $NOCONFIRM -eq 0 ]; then
				_pkg=$1
				prompt $(eval_gettext 'Do you want to vote for $_pkg inclusion/keeping in [community] ? ')$(yes_no 1)
				VOTE=`userinput`
			fi
			if [ "$VOTE" != "N" ]; then
				aurvote --id --vote "$1/$2"
			fi
		else
			echo $pkgvote
		fi
	fi

}
install_from_aur(){
	loadlibrary aur
	pkgname=
	pkgdesc=
	pkgver=
	pkgrel=
	runasroot=0
	failed=0
	DEP_AUR=( )
	local PKG="$1"
	title $(eval_gettext 'Installing $PKG from AUR')
	UID_ROOT=0
	if [ "$UID" -eq "$UID_ROOT" ]
	then
		runasroot=1
		warning $(eval_gettext 'Building unsupported package as root is dangerous.\n Please run yaourt as a non-privileged user.')
		sleep 2
	fi

	wdir="$YAOURTTMPDIR/aur-$PKG"

	if [ -d "$wdir" ]; then
		msg $(eval_gettext 'Resuming previous build')
	else
		mkdir -p "$wdir" || { error $(eval_gettext 'Unable to create directory $wdir.'); return 1; }
	fi
	cd "$wdir/"

	echo
	msg $(eval_gettext 'Downloading $PKG PKGBUILD from AUR...')
	wget -q "http://aur.archlinux.org/packages/$PKG/$PKG.tar.gz" || { error $(eval_gettext '$PKG not found in AUR.'); return 1; }
	tar xfvz "$PKG.tar.gz" > /dev/null || return 1
	cd "$PKG/"
	readPKGBUILD
	if [ -z "$pkgname" ]; then
		echo $(eval_gettext 'Unable to read PKGBUILD for $PKG')
		return 1
	fi

	# Customise PKGBUILD
	[ $CUSTOMIZEPKGINSTALLED -eq 1 ] && customizepkg --modify

	# Eclude package moved into community repository	
	if `is_in_community $PKG`; then
		warning $(eval_gettext '${PKG} is now available in [community]. Aborted')
		error_package[${#error_package[@]}]="$PKG"
		return 1
	fi

	# Test if AUR page exists and show comments
	aurid=`findaurid "$PKG"`
	if [ -z "$aurid" ]; then
		warning $(eval_gettext 'It seems like ${PKG} was removed from AUR probably for security reason. Please Abort')
		sleep 2
		echo -e "${COL_BOLD}${pkgname} ${pkgver}-${pkgrel} ${COL_BLINK}${COL_RED}"$(eval_gettext '(NOT SAFE)')"${NO_COLOR}: ${pkgdesc}"
	else
		# grab AUR comments
		echo
		aurcomments $aurid $PKG
		echo -e "${COL_BOLD}${pkgname} ${pkgver}-${pkgrel} ${COL_BLINK}${COL_RED}"$(eval_gettext '(Unsupported)')"${NO_COLOR}: ${pkgdesc}"
	fi

	find_pkgbuild_deps || return 1
	edit=0
	if [ $EDITPKGBUILD -eq 1 ]; then
		prompt $(eval_gettext 'Edit the PKGBUILD (recommended) ? ')$(yes_no 1)$(eval_gettext '("A" to abort)')
		EDIT_PKGBUILD=$(userinput "YNA")
		echo
		if [ "$EDIT_PKGBUILD" = "A" ]; then
			echo $(eval_gettext 'Aborted...')
			return 1
		elif [ "$EDIT_PKGBUILD" != "N" ]; then
			edit=1
		fi
	fi

	if [ $edit -eq 1 ]; then
		edit_file ./PKGBUILD
		find_pkgbuild_deps || return 1
	fi

	# if install variable is set in PKGBUILD, propose to edit file(s)
	readPKGBUILD
	if [ -f "${install[0]}" -a $EDITPKGBUILD -eq 1 ]; then
		echo 
		warning $(eval_gettext 'This PKGBUILD contains install file that can be dangerous.')
		for installfile in ${install[@]}; do
			edit=0
			list $installfile
			prompt $(eval_gettext 'Edit $installfile (recommended) ? ')$(yes_no 1) $(eval_gettext '("A" to abort)')
			EDIT_INSTALLFILE=$(userinput "YNA")
			echo
			if [ "$EDIT_INSTALLFILE" = "A" ]; then
				echo $(eval_gettext 'Aborted...')
				return 1
			elif [ "$EDIT_INSTALLFILE" != "N" ]; then
				edit=1
			fi
			if [ $edit -eq 1 ]; then
				edit_file $installfile
			fi
		done
	fi

	if [ $NOCONFIRM -eq 0 ]; then
		prompt $(eval_gettext 'Continue the building of ''$PKG''? ')$(yes_no 1)
		if [ "`userinput`" = "N" ]; then
			return 0
		fi
	fi

	echo
	# install new dependencies from AUR
	if [ ${#DEP_AUR[@]} -gt 0 ]; then
		msg $(eval_gettext 'Building missing dependencies from AUR:')
		local depindex=0
		for newdep in ${DEP_AUR[@]}; do
			$BUILDPROGRAM --asdeps "$newdep" || failed=1
			# remove dependencies if failed 
			if [ $failed -eq 1 ]; then
				if [ $depindex -gt 0 ]; then
					warning $(eval_gettext 'Dependencies have been installed before the failure')
					$YAOURTCOMMAND -Rcsn "${DEP_AUR[@]:0:$depindex}"
					plain $(eval_gettext 'press a key to continue')
					read
				fi
				break
			fi
			(( depindex ++ ))
		done
	fi
	echo

	# if dep's building not failed; search for sourceforge mirror
	[ $failed -ne 1 ] && sourceforge_mirror_hack

	# compil PKGBUILD if dep's building not failed
	[ $failed -ne 1 ] && build_package
	retval=$?
	if [ $retval -eq 1 ]; then
		manage_error 1 || return 1
	elif [ $retval -eq 90 ]; then
		return 0
	fi

	# Install, export, copy package after build 
	[ $failed -ne 1 ] && install_package

	# Check if this package has been voted on AUR, and vote for it
	if [ $AURVOTE -eq 1 ]; then
		vote_package "$pkgname" "$aurid"
	fi

	#msg "Delete $wdir"
	rm -rf "$wdir" || warning $(eval_gettext 'Unable to delete directory $wdir.')
	cleanoutput
	echo
	return $failed
}
search_on_aur(){
	#msg "Search for $1 on AUR"
	_pkg=$1
	title $(eval_gettext 'searching for $_pkg on AUR')
	[ "$MAJOR" = "interactivesearch" ] && i=$(($(wc -l $searchfile | awk '{print $1}')+1))
	wget -q "${AUR_URL}${1}" -O - | grep -A 2 "<a href='/packages.php?ID=" \
	| sed -e "s/<\/span>.*$//" -e "s/^.*packages.php?ID=.*span class.*'>/aur\//" -e "s/^.*span class.*'>//" \
	| grep -v "&nbsp;" | grep -v "^--" |
	while read line; do
		if [ "${line%\/*}" = "aur" ]; then
			package=$(echo $line | awk '{ print $1}' | sed 's/^.*\///')
			version=$(echo $line | awk '{print $2}')
			if isinstalled $package; then
				lversion=`pkgversion $package`
				if [ "$lversion" = "$version" ];then
					line="${COL_ITALIQUE}${COL_REPOS}aur/${NO_COLOR}${COL_BOLD}${package} ${COL_GREEN}${version} ${COL_INSTALLED}[$(eval_gettext 'installed')]"
				else
					line="${COL_ITALIQUE}${COL_REPOS}aur/${NO_COLOR}${COL_BOLD}${package} ${COL_GREEN}${version} ${COL_INSTALLED}[${COL_RED}$lversion${COL_INSTALLED} $(eval_gettext 'installed')]"
				fi
			else
				line="${COL_ITALIQUE}${COL_REPOS}aur/${NO_COLOR}${COL_BOLD}${package} ${COL_GREEN}${version}"
			fi
			[ "$MAJOR" = "interactivesearch" ] && line="${COL_NUMBER}${i}${NO_COLOR} $line"
			echo -e "$line${NO_COLOR}"
			[ "$MAJOR" = "interactivesearch" ] && echo "aur/${package}" >> $searchfile 
			[ "$MAJOR" = "interactivesearch" ] && (( i ++ ))
		else
			echo -e "    ${COL_ITALIQUE}$line${NO_COLOR}"
		fi
	done
	cleanoutput
}
upgrade_from_aur(){
	title $(eval_gettext 'upgrading AUR unsupported packages')
	tmp_files="$YAOURTTMPDIR/search/"
	mkdir -p $tmp_files
	loadlibrary pacman_conf
	loadlibrary aur
	create_ignorepkg_list || error $(eval_gettext 'list ignorepkg in pacman.conf')
	# Search for new version on AUR
	local iNum=0
	msg $(eval_gettext 'Searching for new version on AUR')
	for PKG in $(pacman -Qqm)
	do
		echo -n "$PKG: "
		initjsoninfo $PKG || { echo -e "${COL_YELLOW}"$(eval_gettext 'not found on AUR')"${NO_COLOR}"; continue; }
		local_version=`pkgversion $PKG`
		aur_version=`parsejsoninfo Version`
		if `is_x_gt_y $aur_version $local_version`; then
			echo -en "${COL_GREEN}${local_version} => ${aur_version}${NO_COLOR}"
			if grep "^${PKG}$" $tmp_files/ignorelist > /dev/null; then
				echo -e "${COL_RED} "$(eval_gettext '(ignoring package upgrade)')"${NO_COLOR}"
			else
				echo 
				aur_package[$iNum]=$PKG
				(( iNum ++ ))
			fi
		elif [ $local_version != $aur_version ]; then
			echo -e " (${COL_RED}local=$local_version ${NO_COLOR}aur=$aur_version)"
		else
			if [ `parsejsoninfo "OutOfDate"` -eq 1 ]; then
				echo -e $(eval_gettext "up to date ")"${COL_RED}($local_version "$(eval_gettext 'flaged as out of date')"${NO_COLOR}"
			else
				echo $(eval_gettext 'up to date ')
			fi
		fi
	done
	cleanoutput

	[ $iNum -lt 1 ] && return 0

	# upgrade yaourt first
	for package in ${aur_package[@]}; do
		if [ "$package" = "yaourt" ]; then
			warning $(eval_gettext 'New version of $package detected')
			prompt $(eval_gettext 'Do you want to update $package first ? ')$(yes_no 1)
			[ "`userinput`" = "N" ] && break
			echo
			msg $(eval_gettext 'Upgrading $package first')
			install_from_aur "$package" || error $(eval_gettext 'unable to update $package')
			die 0
		fi
	done

	plain "\n---------------------------------------------"
	plain $(eval_gettext 'Packages that can be updated from AUR:')
	echo "${aur_package[*]}"
	if [ $NOCONFIRM -eq 0 ]; then
		prompt $(eval_gettext 'Do you want to update these packages ? ')$(yes_no 1)
		[ "`userinput`" = "N" ] && return 0
		echo
	fi
	for PKG in ${aur_package[@]}; do
		install_from_aur "$PKG" || error $(eval_gettext 'unable to update $PKG')
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
	if `is_unsupported $PKG`; then
		eval $INENGLISH wget "http://aur.archlinux.org/packages/$PKG/$PKG.tar.gz" || { error $(eval_gettext '$PKG not found in AUR.'); die 1; }
		tar xzf $PKG.tar.gz --transform="s,$PKG,," 2>/dev/null
		rm $PKG.tar.gz
	else
		BUILD=1
		install_from_abs $PKG
	fi
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
			case $QUERYTYPE in
				"%DEPENDS%")
				msg $(eval_gettext 'packages which depend on $arg:');;
				"%CONFLICTS%")
				msg $(eval_gettext 'packages which conflicts with $arg');;
				"%PROVIDES%")
				msg $(eval_gettext 'packages which provides $arg');;
			esac
			searchforpackageswhich "$QUERYTYPE" "$arg"
		done
	elif [ $LIST -eq 1 ];then
		#Searching all packages in repos
		title $(eval_gettext 'listing all packages in repos')
		msg $(eval_gettext 'Listing all REPOS''s packages')
		eval $PACMANBIN $ARGSANS ${args[*]}| sed 's/^ /_/' |
		while read line; do
			package=$(echo $line | awk '{print $2}')
			repos="${COL_GREEN}$(echo $line | awk '{print $1}')"
			version=$(echo $line | awk '{print $3}')
			echo -ne "${repos} ${COL_BOLD}${package} ${NO_COLOR}${version}"
			if isinstalled $package; then
				lversion=`pkgversion $package`
				if [ "$lversion" = "$version" ];then
					echo -ne " ${COL_INSTALLED}["$(eval_gettext 'installed')"]${NO_COLOR}"
				else
					echo -ne " ${COL_INSTALLED}[${COL_RED}$lversion${COL_INSTALLED} "$(eval_gettext 'installed')"]${NO_COLOR}"
				fi
			fi
			echo
		done
	elif [ $SEARCH -eq 1 ]; then	
		# Searching for/info/install packages
		#msg "Recherche dans ABS"
		if [ $QUIET -eq 1 ]; then
			eval $PACMANBIN $ARGSANS --search ${args[*]}
			die 0
		fi

		eval $PACMANBIN $ARGSANS --search ${args[*]} | sed 's/^ /_DESCRIPTIONline_/' |
		while read line; do
			if echo "$line" | grep -q "^_DESCRIPTIONline_"; then
				echo -e "$COL_ITALIQUE$line$NO_COLOR" | sed 's/_DESCRIPTIONline_/  /'

				continue
			fi
			package=`echo $line | grep -v "^_" | awk '{ print $1}' | sed 's/^.*\///'`
			repository=`echo $line| sed 's/\/.*//'`
			version=`echo $line | awk '{print $2}'`
			group=`echo $line | sed -e 's/^[^(]*//'`
			line=`colorizeoutputline ${repository}/${NO_COLOR}${COL_BOLD}${package} ${COL_GREEN}${version}`
				if isinstalled $package; then
					lversion=`pkgversion $package`
					if [ "$lversion" = "$version" ];then
						line="$line ${COL_INSTALLED}[$(eval_gettext 'installed')]"
					else
						line="$line ${COL_INSTALLED}[${COL_RED}$lversion${COL_INSTALLED} $(eval_gettext 'installed')]"
					fi
				fi
			echo -e "$line$NO_COLOR $COL_GROUP$group$NO_COLOR"
		done
		########################################################
		#lrepositories=( `LC_ALL="C"; pacman --debug 2>/dev/null| grep "debug: opening database '" | awk '{print $4}' |uniq| tr -d "'"| grep -v 'local'` )
		#regexp=`echo ${args[*]} | sed "s/\*/\.\*/"`
		#packagefiles=( `grep -irl --include="desc" ${regexp} ${lrepositories[*]/#/$PACMANROOT/sync/}` )
		#for packagefile in ${packagefiles[@]}; do
			# hack to exclude wrong result like name/version, email etc..
		#	if ! sed '/%CSIZE%/, //d' $packagefile | grep -qi "${regexp}"; then
		#		continue
		#	fi

		#	package=`echo $packagefile| sed -e "s/\/desc//" -e "s/.*\///" -e "s/-[a-z0-9_.]*-[a-z0-9.]*$//g"`
		#	repository=`echo $packagefile| sed -e "s/\/[^/]*\/desc//" -e "s/.*\///"`
		#	version=`echo $packagefile| sed -e "s/^.*$repository\/$package-//" -e "s/\/desc//"`
		#	line=`colorizeoutputline ${repository}/${NO_COLOR}${COL_BOLD}${package} ${COL_GREEN}${version}`
		#	if isinstalled $package; then
		#		lversion=`pkgversion $package`
		#		if [ "$lversion" = "$version" ];then
		#			line="$line ${COL_INSTALLED}[$(eval_gettext 'installed')]"
		#		else
		#			line="$line ${COL_INSTALLED}[${COL_RED}$lversion${COL_INSTALLED} $(eval_gettext 'installed')]"
		#		fi
		#	fi
		#	echo -e "$line$NO_COLOR"
		#	echo -e "$COL_ITALIQUE    `grep -A 1 "%DESC%" $packagefile | tail -n 1`"
		#done
		###################
		cleanoutput
		if [ $AURSEARCH -eq 1 ]; then
			#msg "Search on AUR"
			for arg in ${args[@]}; do
				search_on_aur $arg || error $(eval_gettext 'unable to contact AUR')
			done
		fi
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
	elif [ $SYSUPGRADE -eq 0 -a ${#args[@]} -eq 0 -a $REFRESH -eq 0 ]; then
		prepare_orphan_list
		msg $(eval_gettext 'yaourt: no argument'):wa
		
		pacman_queuing;	eval $PACMANBIN $ARGSANS
		show_new_orphans
	elif [ $SYSUPGRADE -eq 0 ]; then
		#msg "Install ($ARGSANS)"
		# Install from a list of packages	
		loadlibrary abs
		if [ -f "${args[0]}" ] && file -b "${args[0]}" | grep -qi text ; then
			title $(eval_gettext 'Installing from a list of a packages')
			_pkg_list=${args[0]}
			msg $(eval_gettext 'Installing from a list of a packages ($_pkg_list)')
			AURVOTE=0
			args=( `cat "${args[0]}" | awk '{print $1}'` ) 
		fi
		# Install from arguments
		prepare_orphan_list
		for arg in ${args[@]}; do
			repository=`sourcerepository ${arg#*/}`
			if [ "$repository" != "local" -a $AUR -eq 0 -a ! "$(echo $arg | grep "^aur/")" ]; then
				repos_package[${#repos_package[@]}]=${arg}
			else
				install_from_aur "${arg#aur/}" || failed=1
			fi
		done
		[ ${#repos_package[@]} -gt 0 ] && install_from_abs "${repos_package[*]}"
		show_new_orphans
	elif [ $SYSUPGRADE -eq 1 ]; then
		#msg "System Upgrade"
		prepare_orphan_list
		loadlibrary abs
		#Downgrade all packages marked as "newer than extra/core/etc..."
		if [ $DOWNGRADE -eq 1 ]; then
			msg $(eval_gettext 'Downgrading packages')
			title $(eval_gettext 'Downgrading packages')
			downgradelist=( `LC_ALL=C $PACMANBIN -Qu | grep "is newer than" | awk -F ":" '{print $2}'` )				
			if [ ${#downgradelist[@]} -gt 0 ]; then
				pacman_queuing;	launch_with_su "$PACMANBIN -S ${downgradelist[*]}"
				show_new_orphans
			else
				echo $(eval_gettext 'No package to downgrade')
			fi
			die $?
			exit
		fi
		# Searching for packages to update, buid from sources if necessary
		# Hack while waiting that this pacman's bug (http://bugs.archlinux.org/task/8905) will be fixed:
		if [ $SUDOINSTALLED -eq 1 ] && sudo -l | grep "\(pacman\ *$\|ALL\)" 1>/dev/null; then
			pacman_cmd="sudo $PACMANBIN"
		elif [ "$UID" -eq 0 ]; then
			pacman_cmd="$PACMANBIN"
		else
			msg $(eval_gettext 'Sorry, because of a regression bug in pacman 3.1, you have to use sudo to allow pacman to be run as user\n(see http://bugs.archlinux.org/task/8905)')
		fi
		LC_ALL=C $pacman_cmd --sync --sysupgrade --print-uris $NEEDED $IGNOREPKG &> $YAOURTTMPDIR/sysupgrade
		if [ $? -ne 0 ]; then
			error $(eval_gettext 'problem during full system upgrade')
			cat $YAOURTTMPDIR/sysupgrade | grep -v ':: Starting full system upgrade'
		fi
		packages=( `cat $YAOURTTMPDIR/sysupgrade | grep "^\(ftp:\/\/\|http:\/\/\|file:\/\/\)" | sed -e "s/-i686.pkg.tar.gz$//" \
		-e "s/-x86_64.pkg.tar.gz$//" -e "s/-any.pkg.tar.gz$//" -e "s/.pkg.tar.gz//" -e "s/^.*\///" -e "s/-[^-]*-[^-]*$//" | sort --reverse` )
		# Specific upgrade: pacman and yaourt first. Ask to mount /boot for kernel26 or grub
		for package in ${packages[@]}; do
			case $package in 
				pacman|yaourt)
				warning $(eval_gettext 'New version of $package detected')
				prompt $(eval_gettext 'Do you want to update $package first ? ')$(yes_no 1)
				[ "`userinput`" = "N" ] && continue
				echo
				msg $(eval_gettext 'Upgrading $package first')
				pacman_queuing;	launch_with_su "$PACMANBIN -S $package"
				die 0
				;;
				grub|kernel26*)
				if [ `ls /boot/ | wc -l` -lt 2 ]; then 
					warning $(eval_gettext 'New version of $package detected')
					prompt $(eval_gettext 'Please mount your boot partition first then press ENTER to continue')
					read
				fi
				;;
			esac
		done

		if [ ${#packages} -gt 0 ]; then
			# List packages to build
			if [ $BUILD -eq 1 -o $CUSTOMIZEPKGINSTALLED -eq 1 ] && [ $DOWNLOAD -eq 0 ]; then
				for package in ${packages[@]}; do
					if [ $BUILD -eq 1 -o -f "/etc/customizepkg.d/$package" ]; then
						packagesfromsource[${#packagesfromsource[@]}]=$package
					fi
				done
			fi
			# Show package list before building
			if [ ${#packagesfromsource[@]} -gt 0 ]; then
				eval $PACMANBIN --query --sysupgrade $NEEDED $IGNOREPKG
				if [ $NOCONFIRM -eq 0 ]; then
					echo -n $(eval_gettext 'Proceed with installation? ')$(yes_no 1)
					proceed=`userinput`
				fi
			fi
			# Build some packages if needed, then launch pacman classic sysupgrade
			if [ "$proceed" != "N" ]; then
				if [ ${#packagesfromsource[@]} -gt 0 ]; then
					BUILD=1
					install_from_abs "${packagesfromsource[*]}"
				fi
				if [ ${#packages[@]} -gt ${#packagesfromsource[@]} ]; then
					pacman_queuing;	launch_with_su "$PACMANBIN $ARGSANS"
				fi
			fi
		else
			# Nothing to update. Show various infos
			eval $PACMANBIN --query --sysupgrade $NEEDED $IGNOREPKG
		fi

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
		search_for_installed_package
	elif [ $LIST -eq 1 -o $INFO -eq 1 -o $SYSUPGRADE -eq 1 -o $CHANGELOG -eq 1 ]; then
		# just run pacman -Ql or pacman -Qi
		eval $PACMANBIN $ARGSANS ${args[*]}
	else
		list_installed_packages
	fi
	;;
	
	interactivesearch)
	#msg "Recherche dans ABS"
	tmp_files="$YAOURTTMPDIR/search"
	mkdir -p $tmp_files || die 1
	searchfile=$tmp_files/interactivesearch.$$>$searchfile || die 1
	i=1
	lrepositories=( `LC_ALL="C"; pacman --debug 2>/dev/null| grep "debug: opening database '" | awk '{print $4}' |uniq| tr -d "'"| grep -v 'local'` )
	regexp=`echo ${args[*]} | sed "s/\*/\.\*/"`
	packagefiles=( `grep -irl --include="desc" ${regexp} ${lrepositories[*]/#/$PACMANROOT/sync/}` )
	for packagefile in ${packagefiles[@]}; do
		# hack to exclude wrong result like name/version, email etc..
		if ! sed '/%CSIZE%/, //d' $packagefile | grep -qi "${regexp}"; then
			continue
		fi
		package=`echo $packagefile| sed -e "s/\/desc//" -e "s/.*\///" -e "s/-[a-z0-9_.]*-[a-z0-9.]*$//g"`
		repository=`echo $packagefile| sed -e "s/\/[^/]*\/desc//" -e "s/.*\///"`
		version=`echo $packagefile| sed -e "s/^.*$repository\/$package-//" -e "s/\/desc//"`
		echo "${repository}/${package}" >> $searchfile
		line="${repository}/${NO_COLOR}${COL_BOLD}${package} ${COL_GREEN}${version}"
		if isinstalled $package; then
			lversion=`pkgversion $package`
			if [ "$lversion" = "$version" ];then
				line="$line ${COL_INSTALLED}[$(eval_gettext 'installed')]"
			else
				line="$line ${COL_INSTALLED}[${COL_RED}$lversion${COL_INSTALLED} $(eval_gettext 'installed')]"
			fi
		fi
		echo -e "${COL_NUMBER}${i}${NO_COLOR} `colorizeoutputline $line${NO_COLOR}`"
		(( i ++ ))
		#show description
		echo -e "$COL_ITALIQUE    `grep -A 1 "%DESC%" $packagefile | tail -n 1`"
	done
	cleanoutput
	if [ $AURSEARCH -eq 1 ]; then
		#msg "Search on AUR"
		search_on_aur "`echo ${args[*]} |tr "\*" "\%"`" || error $(eval_gettext 'unable to contact AUR')
	fi
	if [ ! -s "$searchfile" ]; then
		die 0	
	fi
	prompt $(eval_gettext 'Enter n° (separated by blanks, or a range) of packages to be installed\n')
	prompt $(eval_gettext 'Example:   ''1 6 7 8 9''   or   ''1 6-9''')
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
