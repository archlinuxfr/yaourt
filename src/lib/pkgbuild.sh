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

loadlibrary alpm_query

# This file use global variables
# SPLITPKG:	1 if current PKGBUILD describe multiple package
# PKGBUILD_VARS : important vars in PKGBUILD like pkgbase, pkgname ...
# PKGBUILD_DEPS : deps not installed or provided
# PKGBUILD_DEPS_INSTALLED : deps installed or provided
# PKGBUILD_CONFLICTS : package installed and conflicts
# PARCH : 'any' or CARCH in makepkg

# source makepkg configuration
source_makepkg_conf ()
{
	# From makepkg, try to source the same way
	# but suppose default confdir = /etc
	local _PKGDEST=${PKGDEST}
	local _SRCDEST=${SRCDEST}
	[[ -r /etc/makepkg.conf ]] && source /etc/makepkg.conf || return 1
	[[ -r ~/.makepkg.conf ]] && source ~/.makepkg.conf
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
		groups license source install md5sums depends makedepends conflicts \
		replaces \
		_svntrunk _svnmod _cvsroot_cvsmod _hgroot _hgrepo \
		_darcsmod _darcstrunk _bzrtrunk _bzrmod _gitroot _gitname \
		)

	unset ${vars[*]}
	local pkgbuild_tmp=$(mktemp --tmpdir="$YAOURTTMPDIR")
	echo "yaourt_$$() {"                > $pkgbuild_tmp
	cat PKGBUILD                        >> $pkgbuild_tmp
	echo                                >> $pkgbuild_tmp
	if (( update )); then
		echo "devel_check"              >> $pkgbuild_tmp
		echo "devel_update"             >> $pkgbuild_tmp
	fi
	echo "declare -p ${vars[*]} >&3"    >> $pkgbuild_tmp
	echo "return 0"                     >> $pkgbuild_tmp
	echo "}"                            >> $pkgbuild_tmp
	echo "( yaourt_$$ ) || exit 1"      >> $pkgbuild_tmp		
	echo "exit 0"                       >> $pkgbuild_tmp
	PKGBUILD_VARS="$(makepkg -p "$pkgbuild_tmp" 3>&1 1>/dev/null 2>&1 | tr '\n' ';')"
	rm "$pkgbuild_tmp"
	eval $PKGBUILD_VARS
	[[ "$pkgbase" ]] || pkgbase="${pkgname[0]}"
	PKGBUILD_VARS="$(declare -p ${vars[*]} 2>/dev/null | tr '\n' ';')"
	PKGBUILD_VARS=${PKGBUILD_VARS//declare -- /}
	if [[ ! "$pkgbase" ]]; then
		echo $(eval_gettext 'Unable to read PKGBUILD for $PKG')
		return 1
	fi
	(( ${#pkgname[@]} > 1 )) && SPLITPKG=1 || SPLITPKG=0
	(( SPLITPKG )) && {
		warning $(gettext 'This PKGBUILD describe a splitted packages.')
		msg $(gettext 'Specific package options are unknown')
	}
	[[ "$arch" = 'any' ]] && PARCH=any || PARCH=$CARCH
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
			PKGBUILD_DEPS_INSTALLED+=("$dep")
		fi
	done
	(( nodisplay )) && return 0
	msg "$(eval_gettext '$PKG dependencies:')"
	for dep in "${PKGBUILD_DEPS_INSTALLED[@]}"; do
		echo -e " - ${COL_BOLD}$dep${NO_COLOR}" $(gettext '(already installed)')
	done
	for dep in "${PKGBUILD_DEPS[@]}"; do
		isavailable $dep && echo -e " - ${COL_BLUE}$dep${NO_COLOR}" $(gettext '(package found)') && continue
		echo -e " - ${COL_YELLOW}$dep${NO_COLOR}" $(gettext '(building from AUR)') 
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
	if (( ${#cfs[@]} != ${#conflicts[@]} )); then 
		for cf in "${conflicts[@]}"
		do
			if ! in_array "$cf" "${cfs[@]}"; then
				PKGBUILD_CONFLICTS+=("$cf")
			fi
		done
		# Workaround to disable self detection 
		# If package is installed and provides that 
		# which conflict with.
		local i=0
		for cf in "${PKGBUILD_CONFLICTS[@]}"; do
			package-query -Qqi "${cf%[<=>]*}" || unset PKGBUILD_CONFLICTS[$i]
			(( i++ ))
		done
		[[ "$PKGBUILD_CONFLICTS" ]] && (( nodisplay )) && return 1
	fi
	(( nodisplay )) && return 0
	if [[ "$PKGBUILD_CONFLICTS" ]]; then 
		msg "$(eval_gettext '$PKG conflicts:')"
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
	local _pkg=$1
	shift
	[[ "$*" ]] || return 0
	local pkgs=( $(package-query -Qif "%n" "${@%[<=>]*}") )
	(( ! ${#pkgs[@]} )) && return 0
	warning $(eval_gettext '$_pkg conflicts with those packages:')
	for pkg in "${pkgs[@]}"; do
		echo -e " - ${COL_BOLD}$pkg${NO_COLOR}"
	done
	prompt "$(gettext 'Do you want to remove them with "pacman -Rd" ? ') $(yes_no 2)"
	if ! useragrees "YN" "N"; then
		su_pacman -Rd "${pkgs[@]}" 
		if (( $? )); then
			error $(eval_gettext 'Unable to remove:') ${pkgs[@]}.
			return 1
		fi
	fi
	return 0
}

# Check if PKGBUILD install a devel version
# call read_pkgbuild() before
check_devel ()
{
	eval $PKGBUILD_VARS
	if [[ -n "${_svntrunk}" && -n "${_svnmod}" ]] \
		|| [[ -n "${_cvsroot}" && -n "${_cvsmod}" ]] \
		|| [[ -n "${_hgroot}" && -n "${_hgrepo}" ]] \
		|| [[ -n "${_darcsmod}" && -n "${_darcstrunk}" ]] \
		|| [[ -n "${_bzrtrunk}" && -n "${_bzrmod}" ]] \
		|| [[ -n "${_gitroot}" && -n "${_gitname}" ]]; then
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
		[[ "$installfile" ]] || continue
		run_editor "$installfile" $default_answer 
		(( $? == 2 )) && return 1
	done
	return 0
}

# Build package using makepkg
# Usage: build_package ()
# Return 0: on success
#		 1: on error
#		 2: if sysupgrade and no update available
build_package()
{
	eval $PKGBUILD_VARS
	msg "$(gettext 'Building and installing package')"

	if check_devel;then
		#msg "Building last CVS/SVN/HG/GIT version"
		wdirDEVEL="/var/abs/local/yaourtbuild/${pkgbase}"
		# Using previous build directory
		if [[ -d "$wdirDEVEL" ]]; then
			prompt "$(eval_gettext 'Yaourt has detected previous ${pkgbase} build. Do you want to use it (faster) ? ') $(yes_no 1)"
			if useragrees; then
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
		if (( SYSUPGRADE )) && (( DEVEL )) && (( ! FORCE )); then
			# re-read PKGBUILD to update version
			read_pkgbuild 1 || return 1
			eval $PKGBUILD_VARS
			if ! is_x_gt_y "$pkgver-$pkgrel" $(pkgversion $pkgbase); then
				msg $(eval_gettext '$pkgbase is already up to date.')
				return 2
			fi
		fi
	fi

	# install deps from abs (build or download) as depends
	if [[ $PKGBUILD_DEPS ]]; then
		msg $(eval_gettext 'Install or build missing dependencies for $PKG:')
		$YAOURTBIN -S "${YAOURT_ARG[@]}" --asdeps "${PKGBUILD_DEPS[@]%[<=>]*}"
		local _deps_left=( $(pacman -T "${PKGBUILD_DEPS[@]}") )
		if (( ${#_deps_left[@]} )); then
			warning $(gettext 'Dependencies have been installed before the failure')
			for _deps in "${PKGBUILD_DEPS[@]}"; do
				in_array $_deps "${_deps_left[@]}" || \
					$YAOURTBIN -Rcsn "${YAOURT_ARG[@]}" "${_deps%[<=>]*}"
			done
			return 1
		fi
	fi
	
	# Build 
	check_root
	mkpkg_opt=$MAKEPKG_ARG
	(( runasroot )) && mkgpkg_opt="$mkpkg_opt --asroot"
	(( SUDOINSTALLED )) || (( runasroot )) &&  mkgpkg_opt="$mkpkg_opt --syncdeps"
	PKGDEST="$YPKGDEST" nice -n 15 makepkg $mkpkg_opt --force -p ./PKGBUILD

	if (( $? )); then
		error $(eval_gettext 'Makepkg was unable to build $PKG package.')
		return 1
	fi
	if (( EXPORT )); then
		YSRCPKGDEST=$(mktemp -d --tmpdir="$YAOURTTMPDIR" SRCPKGDEST.XXX)
		PKGDEST="$YSRCPKGDEST" makepkg --allsource
		bsdtar -vxf "$YSRCPKGDEST/"* -C "$EXPORTDIR"
		rm -r "$YSRCPKGDEST"
	fi
	return 0
}

# Install package after build
# Usage: install_package ()
install_package()
{
	eval $PKGBUILD_VARS
	# Install, export, copy package after build 
	if (( EXPORT )); then
		for _pkg in ${pkgname[@]}; do
			cd "$EXPORTDIR"  || break
			find . -maxdepth 1 -regex "./$pkgname-[^-]+-[^-]+-[^-]+$PKGEXT" -delete
			cd - > /dev/null
		done
		msg $(eval_gettext 'Exporting ${pkgbase} to ${EXPORTDIR} repository')
		cp -vfp "$YPKGDEST/"* "$EXPORTDIR/" 
	fi

	for _file in "$YPKGDEST/"*; do
		local pkg_conflicts=($(package-query -Qp -f "%c" "$_file"))
		eval $(package-query -Qp -f "_pkg=%n;_pkgver=%v" "$_file")
		pkg_conflicts=( "${pkg_conflicts[@]}" $(package-query -Q --query-type conflicts -f "%n" "$_pkg=$_pkgver"))
		(( ! ${#pkg_conflicts[@]} )) && continue;
		manage_conflicts "$_pkg" "${pkg_conflicts[@]}" || return 1
	done

	while true; do
		echo
		msg "$(eval_gettext 'Continue installing ''$PKG'' ?') $(yes_no 1)"
		prompt $(gettext '[v]iew package contents   [c]heck package with namcap')
		local answer=$(userinput "YNVC" "Y")
		echo
		case "$answer" in
			V)	local pkg_nb=${#pkgname[@]}
				local i=0
				for _file in "$YPKGDEST"/*; do
					$PACMANBIN --query --list --file "$_file"
					$PACMANBIN --query --info --file "$_file"
					(( i++ )) && (( i < pkg_nb )) && { prompt $(gettext 'Press any key to continue'); read -n 1; }
				done
				;;
			C)	if type -p namcap &>/dev/null ; then
					for _file in "$YPKGDEST"/*; do
						namcap "$_file"
					done
				else
					warning $(gettext 'namcap is not installed')
				fi
				echo
				;;
			N)	failed=1; break;;
			*)	break;;
		esac
	done
	(( ! failed )) && for _file in "$YPKGDEST"/*; do
		su_pacman -Uf $PACMAN_S_ARG $_file || failed=$?
		(( failed )) && break
	done
	if (( failed )); then 
		warning $(eval_gettext 'Your packages are saved in $YAOURTTMPDIR/')
		cp -i "$YPKGDEST"/* $YAOURTTMPDIR/ || warning $(eval_gettext 'Unable to copy packages to $YAOURTTMPDIR/ directory')
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
	YPKGDEST=$(mktemp -d --tmpdir="$YAOURTTMPDIR" PKGDEST.XXX)
	(( trust )) && default_answer=2
	while true; do
		failed=0
		edit_pkgbuild $default_answer 1 || { failed=1; break; }
		prompt "$(eval_gettext 'Continue the building of ''$PKG''? ')$(yes_no 1)"
		useragrees || { ret=1; break; }
		build_package
		ret=$?
		case "$ret" in
			0|2) break ;;
			1)	prompt "$(eval_gettext 'Restart building ''$PKG''? ')$(yes_no 2)"
				useragrees || { failed=1; break; }
				;;
			*) return 99 ;; # should never execute
		esac
	done
	(( ! ret )) && (( ! failed )) && { install_package || failed=1; }
	rm -r "$YPKGDEST"
	return $failed
}



# If we have to deal with PKGBUILD and makepkg, source makepkg conf(s)
source_makepkg_conf 

