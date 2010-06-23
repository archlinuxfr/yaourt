#!/bin/bash
#
# pkgbuild.sh : deals with PKGBUILD, makepkg ...
# This file is part of Yaourt (http://archlinux.fr/yaourt-en)

loadlibrary alpm_query

# Global vars:
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
	local _SRCPKGDEST=${SRCPKGDEST}
	[[ -r /etc/makepkg.conf ]] && source /etc/makepkg.conf || return 1
	[[ -r ~/.makepkg.conf ]] && source ~/.makepkg.conf
	# Preserve environnement variable
	# else left empty (do not set to $PWD)
	PKGDEST=${_PKGDEST:-$PKGDEST}
	SRCDEST=${_SRCDEST:-$SRCDEST}
	# Use $EXPORTDIR if defined in {/etc/,~/.}yaourtrc
	export PKGDEST=${EXPORTDIR:-$PKGDEST}
	export SRCDEST=${EXPORTDIR:-$SRCDEST}
	# Since pacman 3.4, SRCPKGDEST for makepkg --[all]source
	SRCPKGDEST=${_SRCPKGDEST:-$SRCPKGDEST}
	SRCPKGDEST=${SRCPKGDEST:-$PKGDEST}
	export SRCPKGDEST=${EXPORTDIR:-$SRCPKGDEST}
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
	local pkgbuild_tmp=$(mktemp --tmpdir=".")
	echo "yaourt_$$() {"                            > $pkgbuild_tmp
	cat PKGBUILD                                    >> $pkgbuild_tmp
	echo                                            >> $pkgbuild_tmp
	if (( update )); then
		echo "devel_check"                          >> $pkgbuild_tmp
		echo "devel_update"                         >> $pkgbuild_tmp
	fi
	echo "declare -p ${vars[*]} 2>/dev/null >&3"    >> $pkgbuild_tmp
	echo "return 0"                                 >> $pkgbuild_tmp
	echo "}"                                        >> $pkgbuild_tmp
	echo "( yaourt_$$ ) || exit 1"                  >> $pkgbuild_tmp
	echo "exit 0"                                   >> $pkgbuild_tmp
	PKGBUILD_VARS="$(makepkg "${MAKEPKG_ARG[@]}" -p "$pkgbuild_tmp" 3>&1 1>/dev/null | tr '\n' ';')"
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
		warning $(gettext 'This PKGBUILD describes a splitted package.')
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
	PKGBUILD_DEPS=( $(pacman_parse -T "${depends[@]}" "${makedepends[@]}" ) )
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
	local cfs=( $(pacman_parse -T "${conflicts[@]}") )
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
			pkgquery -Qqi "${cf%[<=>]*}" || unset PKGBUILD_CONFLICTS[$i]
			(( i++ ))
		done
		[[ "$PKGBUILD_CONFLICTS" ]] && (( nodisplay )) && return 1
	fi
	(( nodisplay )) && return 0
	if [[ "$PKGBUILD_CONFLICTS" ]]; then 
		msg "$(eval_gettext '$PKG conflicts:')"
		for cf in $(pkgquery -Qif "%n-%v" "${PKGBUILD_CONFLICTS[@]%[<=>]*}"); do
			echo -e " - ${COL_BOLD}$cf${NO_COLOR}"
		done
	fi
	echo
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

	local wdirDEVEL="$DEVELBUILDDIR/${pkgbase}"
	if [[ "$(readlink -f .)" != "$wdirDEVEL" ]] && check_devel;then
		#msg "Building last CVS/SVN/HG/GIT version"
		local use_devel_dir=0
		[[ -d "$wdirDEVEL" && -w "$wdirDEVEL" ]] && use_devel_dir=1
		[[ ! -d "$wdirDEVEL" ]] && mkdir -p $wdirDEVEL 2> /dev/null && use_devel_dir=1
		if (( use_devel_dir )); then
			cp -a ./* "$wdirDEVEL/" && cd $wdirDEVEL || \
				warning $(eval_gettext 'Unable to write in ${wdirDEVEL} directory. Using /tmp directory')
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
		local _arg="--asdeps"
		((SYSUPGRADE && ! UP_NOCONFIRM)) && _arg+=" --noconfirm"
		$YAOURTBIN -S "${YAOURT_ARG[@]}" $_arg "${PKGBUILD_DEPS[@]%[<=>]*}"
		local _deps_left=( $(pacman_parse -T "${PKGBUILD_DEPS[@]}") )
		if (( ${#_deps_left[@]} )); then
			warning $(gettext 'Dependencies have been installed before the failure')
			for _deps in "${PKGBUILD_DEPS[@]}"; do
				in_array $_deps "${_deps_left[@]}" || \
					$YAOURTBIN -Rsn "${YAOURT_ARG[@]}" "${_deps%[<=>]*}"
			done
			return 1
		fi
	fi
	
	# Build 
	if (( ! UID )); then
		warning $(gettext 'Building package as root is dangerous.\n Please run yaourt as a non-privileged user.')
		sleep 2
	fi
	PKGDEST="$YPKGDEST" makepkg "${MAKEPKG_ARG[@]}" -s -f -p ./PKGBUILD

	if (( $? )); then
		error $(eval_gettext 'Makepkg was unable to build $PKG.')
		return 1
	fi
	(( EXPORT && EXPORTSRC )) && [[ $SRCPKGDEST ]] && makepkg --allsource
	return 0
}

# Install package after build
# Usage: install_package ()
install_package()
{
	eval $PKGBUILD_VARS
	# Install, export, copy package after build 
	if (( EXPORT )) && [[ $PKGDEST ]]; then
		msg $(eval_gettext 'Exporting ${pkgbase} to ${PKGDEST} repository')
		cp -vfp "$YPKGDEST/"* "$PKGDEST/" 
	fi

	while true; do
		echo
		msg "$(eval_gettext 'Continue installing ''$PKG'' ?') $(yes_no 1)"
		prompt $(gettext '[v]iew package contents   [c]heck package with namcap')
		local answer=$(builduserinput "YNVC" "Y")
		echo
		case "$answer" in
			V)	local i=0
				for _file in "$YPKGDEST"/*; do
					(( i++ )) && { prompt2 $(gettext 'Press any key to continue'); read -n 1; }
					$PACMANBIN -Qlp "$_file"
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
	local _arg=""
	((SYSUPGRADE && ! UP_NOCONFIRM)) && _arg+=" --noconfirm"
	(( ! failed )) && for _file in "$YPKGDEST"/*; do
		su_pacman -Uf "${PACMAN_S_ARG[@]}" $_arg $_file || failed=$?
		(( failed )) && break
	done
	if (( failed )); then 
		warning $(eval_gettext 'Your packages are saved in $YAOURTTMPDIR/')
		cp -i "$YPKGDEST"/* $YAOURTTMPDIR/ || warning $(eval_gettext 'Unable to copy packages to $YAOURTTMPDIR/ directory')
	fi

	return $failed
}

# Initialise build dir ($1)
init_build_dir()
{
	local wdir="$1"
	if [[ -d "$wdir" ]]; then
		rm -rf "$wdir" || { error $(eval_gettext 'Unable to delete directory $wdir. Please remove it using root privileges.'); return 1; }
	fi
	mkdir -p "$wdir" || { error $(eval_gettext 'Unable to create directory $wdir.'); return 1; }
	cd $wdir
}

custom_pkg ()
{
	(( CUSTOMIZEPKGINSTALLED )) && [[ -f "/etc/customizepkg.d/$1" ]] && return 0
	return 1
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
	# Customise PKGBUILD
	custom_pkg "$PKG" && customizepkg --modify

	YPKGDEST=$(mktemp -d --tmpdir="$YAOURTTMPDIR" PKGDEST.XXX)
	(( trust )) && default_answer=2
	while true; do
		failed=0
		edit_pkgbuild $default_answer 1 || { failed=1; break; }
		prompt "$(eval_gettext 'Continue building ''$PKG'' ? ')$(yes_no 1)"
		builduseragrees || { failed=1; break; }
		build_package
		ret=$?
		case "$ret" in
			0|2) break ;;
			1)	prompt "$(eval_gettext 'Restart building ''$PKG'' ? ')$(yes_no 2)"
				builduseragrees "YN" "N" && { failed=1; break; }
				;;
			*) return 99 ;; # should never execute
		esac
	done
	(( ! ret )) && (( ! failed )) && { install_package || failed=1; }
	rm -r "$YPKGDEST"
	cd "$YAOURTTMPDIR"
	return $failed
}



# If we have to deal with PKGBUILD and makepkg, source makepkg conf(s)
source_makepkg_conf 
# vim: set ts=4 sw=4 noet: 
