#!/bin/bash
#===============================================================================
#
#          FILE: pkgbuild.sh
# 
#   DESCRIPTION: yaourt's library to manage PKGBUILD
# 
#       OPTIONS:  ---
#  REQUIREMENTS:  ---
#          BUGS:  ---
#         NOTES:  ---
#        AUTHOR:  Julien MISCHKOWITZ (wain@archlinux.fr) 
#                 Tuxce (tuxce.net@gmail.com) 
#       VERSION:  1.0
#===============================================================================

# This file use global variables
# PKGBUILD_VARS : important vars in PKGBUILD like pkgbase, pkgname ...
# PKGBUILD_DEPS : deps not installed or provided
# PKGBUILD_DEPS_INSTALLED : deps installed or provided
# PKGBUILD_CONFLICTS : package installed and conflicts
# PARCH : CARCH in makepkg

# source makepkg configuration
source_makepkg_conf ()
{
	# From makepkg, try to source the same way
	# but suppose default confdir = /etc
	local _PKGDEST=${PKGDEST}
	local _SRCDEST=${SRCDEST}
	[ -r /etc/makepkg.conf ] && source /etc/makepkg.conf || return 1
	[ -r ~/.makepkg.conf ] && source ~/.makepkg.conf
	# Preserve environnement variable
	# else left empty (do not set to $PWD)
	PKGDEST=${_PKGDEST:-$PKGDEST}
	SRCDEST=${_SRCDEST:-$SRCDEST}
}

# Read PKGBUILD
# PKGBUILD must be in current directory
# Usage:	read_pkgbuild ($update)
#	$update: 1: call devel_check & devel_update from makepkg
# Set PKGBUILD_VARS, exec "eval $PKGBUILD_VARS" to have PKGBUILD content.
read_pkgbuild ()
{
	local update=${1:-0}
	local vars=(pkgbase pkgname pkgver pkgrel arch pkgdesc provides url \
		source install md5sums depends makedepends conflicts replaces \
		_svntrunk _svnmod _cvsroot_cvsmod _hgroot _hgrepo \
		_darcsmod _darcstrunk _bzrtrunk _bzrmod _gitroot _gitname \
		)

	unset ${vars[*]}
	pkgbuild_tmp=$(mktemp --tmpdir="$YAOURTTMPDIR")
	echo "yaourt_$$() {" 				> $pkgbuild_tmp
	cat PKGBUILD						>> $pkgbuild_tmp
	if (( update )); then
		echo "devel_check"				>> $pkgbuild_tmp
		echo "devel_update"				>> $pkgbuild_tmp
	fi
	echo "declare -p ${vars[*]} >&3"	>> $pkgbuild_tmp
	echo "return 0"						>> $pkgbuild_tmp
	echo "}"							>> $pkgbuild_tmp
	echo "( yaourt_$$ ) || exit 1"		>> $pkgbuild_tmp		
	echo "exit 0"						>> $pkgbuild_tmp
	PKGBUILD_VARS="$(makepkg -p "$pkgbuild_tmp" 3>&1 1>/dev/null 2>&1 | tr '\n' ';')"
	PKGBUILD_VARS=${PKGBUILD_VARS//declare -- /}
	rm "$pkgbuild_tmp"
	eval $PKGBUILD_VARS
	if [ -z "$pkgname" ]; then
		echo $(eval_gettext 'Unable to read PKGBUILD for $PKG')
		return 1
	fi
	if [ "$arch" = 'any' ]; then
		PARCH=any
	else
		PARCH=$CARCH
	fi
	return 0
}

# Check PKGBUILD dependances 
# call read_pkgbuild() before
# Usage:	check_deps ($nodisplay)
#	$nodisplay: 1: don't display depends information
check_deps ()
{
	local nodisplay=${1:-0}
	eval $PKGBUILD_VARS
	PKGBUILD_DEPS=( $(pacman -T "${depends[@]}" "${makedepends[@]}" ) )
	unset PKGBUILD_DEPS_INSTALLED
	for dep in "${depends[@]}" "${makedepends[@]}"
	do
		if ! in_array "$dep" "${PKGBUILD_DEPS[@]}"; then
			PKGBUILD_DEPS_INSTALLED[${#PKGBUILD_DEPS_INSTALLED[@]}]="$dep"
		fi
	done
	(( nodisplay )) && return 0
	msg "$(eval_gettext '$PKG dependencies:')"
	for dep in "${PKGBUILD_DEPS_INSTALLED[@]}"; do
		echo -e " - ${COL_BOLD}$dep${NO_COLOR}" $(eval_gettext '(already installed)')
	done
	for dep in "${PKGBUILD_DEPS[@]}"; do
		isavailable $dep && echo -e " - ${COL_BLUE}$dep${NO_COLOR}" $(eval_gettext '(package found)') && continue
		echo -e " - ${COL_YELLOW}$dep${NO_COLOR}" $(eval_gettext '(building from AUR)') 
	done
	echo
	return 0 
}

# Check if PKGBUILD conflicts with an installed package
# call read_pkgbuild() before
# Usage:	check_conflicts ($nodisplay)
#	$nodisplay: 1: don't display depends information
# If nodisplay, return 1 if conflicts and 0 if not
check_conflicts ()
{
	local nodisplay=${1:-0}
	eval $PKGBUILD_VARS
	local cfs=( $(pacman -T "${conflicts[@]}") )
	unset PKGBUILD_CONFLICTS
	if [ ${#cf[@]} -ne ${#conflicts[@]} ]; then 
		for cf in "${conflicts[@]}"
		do
			if ! in_array "$cf" "${cfs[@]}"; then
				PKGBUILD_CONFLICTS[${#PKGBUILD_CONFLICTS[@]}]="$cf"
			fi
		done
		(( nodisplay )) && return 1
	fi
	(( nodisplay )) && return 0
	msg "$(eval_gettext '$PKG conflicts:')"
	if [ ${#cf[@]} -ne ${#conflicts[@]} ]; then 
		for cf in $(package-query -Qif "%n-%v" "${PKGBUILD_CONFLICTS[@]%[<=>]*}"); do
			echo -e " - ${COL_BOLD}$cf${NO_COLOR}"
		done
	fi
	echo
	return 0
}

# Manage PKGBUILD conflicts
manage_conflicts ()
{
	[ -z "$*" ] && return 0
	local pkgs=( $(package-query -Qif "%n" "${@%[<=>]*}") )
	(( ! ${#pkgs[@]} )) && return 0
	warning $(eval_gettext '$pkgname conflicts with those packages:')
	for pkg in "${pkgs[@]}"; do
		echo -e " - ${COL_BOLD}$pkg${NO_COLOR}"
	done
	if (( ! NOCONFIRM )); then
		prompt "$(eval_gettext 'Do you want to remove them with "pacman -Rd" ? ') $(yes_no 2)"
		if [ "$(userinput)" = "Y" ]; then
			pacman_queuing; launch_with_su $PACMANBIN -Rd "${pkgs[@]}" 
			if (( $? )); then
				error $(eval_gettext 'Unable to remove $pkg_conflicts.')
				return 1
			fi
		fi
	fi
	return 0
}

# Check if PKGBUILD install a devel version
# call read_pkgbuild() before
check_devel ()
{
	eval $PKGBUILD_VARS
	if [ ! -z "${_svntrunk}" -a ! -z "${_svnmod}" ] \
		|| [ ! -z "${_cvsroot}" -a ! -z "${_cvsmod}" ] \
		|| [ ! -z "${_hgroot}" -a ! -z "${_hgrepo}" ] \
		|| [ ! -z "${_darcsmod}" -a ! -z "${_darcstrunk}" ] \
		|| [ ! -z "${_bzrtrunk}" -a ! -z "${_bzrmod}" ] \
		|| [ ! -z "${_gitroot}" -a ! -z "${_gitname}" ]; then
		return 0
	fi
	return 1
}

# Edit PKGBUILD and install files
# Usage:	edit_pkgbuild ($default_answer, $loop, $check_dep)
# 	$default_answer: 1 (default): Y 	2: N
# 	$loop: for PKGBUILD, 1: loop until answer 'no' 	0 (default) : no loop
# 	$check_dep: 1 (default): check for deps and conflicts
edit_pkgbuild ()
{
	local default_answer=${1:-1}
	local loop=${2:-0}
	local check_dep=${3:-1}
	(( ! EDITFILES )) && { 
		read_pkgbuild || return 1
		(( check_dep )) && { check_deps; check_conflicts; }
		return 0
	}
	local iter=1

	while (( iter )); do
		run_editor PKGBUILD $default_answer
		local ret=$?
		(( ret == 2 )) && return 1
		(( ret )) || (( ! loop )) && iter=0
		read_pkgbuild || return 1
		(( check_dep )) && { check_deps; check_conflicts; }
	done
	
	eval $PKGBUILD_VARS
	for installfile in "${install[@]}"; do
		[ -z "$installfile" ] && continue
		run_editor "$installfile" $default_answer 
		(( $? == 2 )) && return 1
	done
	return 0
}

# Build package using makepkg
# Usage: build_package ()
build_package()
{
	# Test PKGBUILD for last svn/cvs/... version
	msg "$(eval_gettext 'Building and installing package')"

	local pkg_conflicts=$(package-query -Qt conflicts -f "%n" "$pkgname=$pkgver")
	[ -n "$pkg_conflicts" ] && PKGBUILD_CONFLICTS[${#PKGBUILD_CONFLICTS[@]}]="$pkg_conflicts"
	manage_conflicts "${PKGBUILD_CONFLICTS[@]}" || return 1

	if check_devel;then
		#msg "Building last CVS/SVN/HG/GIT version"
		wdirDEVEL="/var/abs/local/yaourtbuild/${pkgname}"
		# Using previous build directory
		if [ -d "$wdirDEVEL" ]; then
			if (( ! NOCONFIRM )); then
				prompt "$(eval_gettext 'Yaourt has detected previous ${pkgname} build. Do you want to use it (faster) ? ') $(yes_no 1)"
				USE_OLD_BUILD=$(userinput)
				echo
			fi
			if [ "$USE_OLD_BUILD" != "N" ] || (( NOCONFIRM )); then
				cp ./* "$wdirDEVEL/"
				cd $wdirDEVEL
			fi
		else
			mkdir -p $wdirDEVEL 2> /dev/null
			if (( $? )); then
				warning $(eval_gettext 'Unable to write in ${wdirDEVEL} directory. Using /tmp directory')
				wdirDEVEL="$wdir/$PKG"
			else
				cp -r ./* "$wdirDEVEL/"
				cd "$wdirDEVEL"
			fi
		fi
		# re-read PKGBUILD to update version
		read_pkgbuild 1 || return 1

	fi

	# install deps from abs (build or download) as depends
	if [ ${#PKGBUILD_DEPS[@]} -gt 0 ]; then
		msg $(eval_gettext 'Install or build missing dependencies for $PKG:')
		$BUILDPROGRAM --asdeps "${PKGBUILD_DEPS[@]%[<=>]*}"
		local _deps_left=( $(pacman -T "${PKGBUILD_DEPS[@]}") )
		if [ -n ${_deps_left[@]} ]; then
			warning $(eval_gettext 'Dependencies have been installed before the failure')
			for _deps in "${PKGBUILD_DEPS[@]}"; do
				in_array $_deps "${_deps_left[@]}" || \
					$YAOURTCOMMAND -Rcsn "${_deps%[<=>]*}"
			done
			return 1
		fi
	fi
	
	# Build 
	check_root
	mkpkg_opt="$confirmation"
	(( NODEPS )) && mkpkg_opt="$mkpkg_opt -d"
	(( IGNOREARCH )) && mkpkg_opt="$mkpkg_opt -A"
	(( HOLDVER )) && mkpkg_opt="$mkpkg_opt --holdver"
	(( runasroot )) && mkgpkg_opt="$mkpkg_opt --asroot"
	(( SUDOINSTALLED )) || (( runasroot )) &&  mkgpkg_opt="$mkpkg_opt --syncdeps"
	pacman_queuing; eval $INENGLISH PKGDEST=`pwd` nice -n 15 makepkg $mkpkg_opt --force -p ./PKGBUILD

	if (( $? )); then
		error $(eval_gettext 'Makepkg was unable to build $PKG package.')
		return 1
	fi

	return 0
}

# Install package after build
# Usage: install_package ()
install_package()
{
	# Install, export, copy package after build 
	if (( EXPORT )); then
		rm $EXPORTDIR/$pkgname-*-*{-$PARCH,}${PKGEXT}
		msg $(eval_gettext 'Exporting ${pkgname} to ${EXPORTDIR} repository')
		PKGDEST="$EXPORTDIR/" && makepkg --allsource
		bsdtar -xf "$EXPORTDIR/${pkgbase}-${pkgver}-${pkgrel}${SRCEXT}"
		rm "$EXPORTDIR/${pkgbase}-${pkgver}-${pkgrel}${SRCEXT}"
		cp -fp "$pkgname-$pkgver-$pkgrel-$PARCH${PKGEXT}" "$EXPORTDIR/" 
	fi

	if (( ! NOCONFIRM )); then
		CONTINUE_INSTALLING="V"
		while [ "$CONTINUE_INSTALLING" = "V" -o "$CONTINUE_INSTALLING" = "C" ]; do
			echo -e "${COL_ARROW}==>  ${NO_COLOR}${COL_BOLD}$(eval_gettext 'Continue installing ''$PKG''? ') $(yes_no 1)${NO_COLOR}" >&2
			prompt $(eval_gettext '[v]iew package contents   [c]heck package with namcap')
			CONTINUE_INSTALLING=$(userinput "YNVC")
			echo
			if [ "$CONTINUE_INSTALLING" = "V" ]; then
				$PACMANBIN --query --list --file ./$pkgname-$pkgver-$pkgrel-$PARCH${PKGEXT}
				$PACMANBIN --query --info --file ./$pkgname-$pkgver-$pkgrel-$PARCH${PKGEXT}
			elif [ "$CONTINUE_INSTALLING" = "C" ]; then
				echo
				if [ `type -p namcap` ]; then
					namcap ./$pkgname-$pkgver-$pkgrel-$PARCH${PKGEXT}
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
		pacman_queuing;	launch_with_su "$PACMANBIN --force --upgrade $asdeps $confirmation ./$pkgname-$pkgver-$pkgrel-$PARCH${PKGEXT}"
		failed=$?
	fi
	if (( failed )); then 
		warning $(eval_gettext 'Your package is saved in $YAOURTTMPDIR/$pkgname-$pkgver-$pkgrel-$PARCH${PKGEXT}')
		cp -i "./$pkgname-$pkgver-$pkgrel-$PARCH${PKGEXT}" $YAOURTTMPDIR/ || warning $(eval_gettext 'Unable to copy $pkgname-$pkgrel-$PARCH${PKGEXT} to $YAOURTTMPDIR/ directory')
	fi

	return $failed
}

# Call build_package until success or abort
# on success, call install_package
# Usage: package_loop ($trust)
#	$trust: 1: default answer for editing: Y (for abs)
package_loop ()
{
	local trust=${1:-0}
	local default_answer=1
	local ret=0
	(( trust )) && default_answer=2
	while true; do
		edit_pkgbuild $default_answer 1 || return 1
		if (( ! NOCONFIRM )); then
			prompt "$(eval_gettext 'Continue the building of ''$PKG''? ')$(yes_no 1)"
		 	[ "`userinput`" = "N" ] && return 1
		fi
		build_package
		ret=$?
		if (( ret )) && (( ! NOCONFIRM )); then
			prompt "$(eval_gettext 'Restart building ''$PKG''? ')$(yes_no 2)"
	 		[ "`userinput`" != "Y" ] && return 1
		elif (( ret )); then
			return 1
		else
			break;
		fi
	done
	install_package || return 1
}



# If we have to deal with PKGBUILD and makepkg, source makepkg conf(s)
source_makepkg_conf 

