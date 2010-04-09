#!/bin/bash
#===============================================================================
#
#          FILE: abs.sh
# 
#   DESCRIPTION: yaourt's library to access Arch Building System Repository
# 
#       OPTIONS:  ---
#  REQUIREMENTS:  ---
#          BUGS:  ---
#         NOTES:  ---
#        AUTHOR:   Julien MISCHKOWITZ (wain@archlinux.fr) 
#       VERSION:  1.0
#===============================================================================
loadlibrary alpm_query
loadlibrary pkgbuild
ABS_REPO=(testing core extra community-testing community gnome-unstable kde-unstable)

# Get sources in current dir
# Usage abs_get_pkgbuild ($arch,$repo,$pkg)
abs_get_pkgbuild ()
{
	rsync -mrtv --no-motd --no-p --no-o --no-g rsync.archlinux.org::abs/$1/$2/$3/ . || return 1	
}

# if package is from ABS_REPO, try to build it from abs, else pass it to aur
build_or_get ()
{
	[[ $1 ]] || return 1
	local pkg=${1#*/}
	[[ "$1" != "${1///}" ]] && local repo=${1%/*} || local repo="$(sourcerepository $pkg)"
	BUILD=1
	in_array "$repo" "${ABS_REPO[@]}" && { install_from_abs "$1"; return 0; }
	if [[ "$MAJOR" = "getpkgbuild" ]]; then
		aur_get_pkgbuild "$pkg"
	else
		install_from_aur "$pkg"
	fi
}


# download package from repos or grab PKGBUILD from repos.archlinux.org and run makepkg
install_from_abs(){
	for _line in $(package-query -1Sif "repo=%r;PKG=%n;_pkgver=%v;_arch=%a" "$@"); do
		eval $_line
		local package="$repo/$PKG"
		(( ! BUILD )) && [[ ! -f "/etc/customizepkg.d/$PKG" ]] && binariespackages+=(${package#-/}) && continue
		if [[ "$MAJOR" != "getpkgbuild" ]]; then
			msg $(eval_gettext 'Building $PKG from sources.')
			title $(eval_gettext 'Install $PKG from sources')
		fi
		echo
		if [[ "$MAJOR" != "getpkgbuild" ]]; then
			msg $(gettext 'Retrieving PKGBUILD and local sources...')
			wdir="$YAOURTTMPDIR/abs-$PKG"
			if [[ -d "$wdir" ]]; then
				rm -rf "$wdir" || { error $(eval_gettext 'Unable to delete directory $wdir. Please remove it using root privileges.'); return 1; }
			fi
			mkdir -p "$wdir" || { error $(eval_gettext 'Unable to create directory $wdir.'); return 1; }
			cd $wdir
		fi

		# With splitted package, abs folder may not correspond to package name
		local pkgbase=( $(grep -A1 '%BASE%' "$PACMANROOT/sync/$repo/$PKG-$_pkgver/desc" ) )
		[[ $pkgbase ]] || pkgbase=( '' "$PKG" )
		abs_get_pkgbuild $_arch $repo ${pkgbase[1]} || return 1
		[[ "$MAJOR" = "getpkgbuild" ]] && return 0

		# Customise PKGBUILD
		(( CUSTOMIZEPKGINSTALLED )) && customizepkg --modify
		# Build, install/export
		package_loop 1 || { manage_error 1; continue; }
	done
}


# Searching for packages to update, buid from sources if necessary
sysupgrade()
{
	local pacjages packagesfromsource
	(( UPGRADES > 1 )) && local _arg="-uu" || local _arg="-u"
	$PACMANBIN -Sp $_arg $PACMAN_S_ARG $IGNOREPKG 1> "$YAOURTTMPDIR/sysupgrade" || return 1
	
	packages=($(grep '://' "$YAOURTTMPDIR/sysupgrade"))
	packages=("${packages[@]##*/}")
	packages=("${packages[@]%-*-*-*.pkg*}")
	rm "$YAOURTTMPDIR/sysupgrade"
	[[ ! "$packages" ]] && return 0	

	# Specific upgrade: pacman and yaourt first. Ask to mount /boot for kernel26 or grub
	local i=0
	for package in ${packages[@]}; do
		if (( CUSTOMIZEPKGINSTALLED )) && [[ -f "/etc/customizepkg.d/$package" ]]; then
			packagesfromsource+=($_pkg)
			unset packages[$i]
		fi
		case "$package" in
			pacman|yaourt)
				warning $(eval_gettext 'New version of $package detected')
				prompt "$(eval_gettext 'Do you want to update $package first ? ')$(yes_no 1)"
				useragrees || continue
				msg $(eval_gettext 'Upgrading $package first')
				su_pacman -S $PACMAN_S_ARG --needed $package
				die 0
				;;
			grub*|kernel*)
				if [[ ! $(ls -A /boot/) ]]; then
					warning $(eval_gettext 'New version of $package detected')
					prompt $(gettext 'Please mount your boot partition first then press ENTER to continue')
					(( NOCONFIRM )) || read
				fi
				;;
		esac
		(( i++ ))
	done

	# Specific upgrade: packages to build from sources
	if (( BUILD )); then
		echo
		echo "$(gettext 'Source Targets:') ${packages[@]}" 
		echo -ne "\n$(gettext 'Proceed with upgrade? ') $(yes_no 1) "
		useragrees || return 0
		install_from_abs "${packages[@]}"; 
		return $? 
	fi
	if [[ $packagesfromsource ]]; then
		msg $(eval_gettext 'Packages to build from sources:')
		echo ${packagesfromsource[*]}
		# Show package list before building
		echo -n "$(eval_gettext 'Proceed with compilation and installation ? ')$(yes_no 1)"
		useragrees || return 0
		# Build packages if needed
		BUILD=1	install_from_abs "${packagesfromsource[@]}"
	fi

	# Classic sysupgrade
	### classify pkg to upgrade, filtered by category "new release", "new version", "new pkg"
	OLD_IFS="$IFS"
	IFS=$'\n'
	for _line in $(package-query -1Sxi \
		-f "pkgname=%n;repo=%r;rversion=%v;lversion=%l;pkgdesc=\"%d\"" \
		"${packages[@]}"); do
		eval $_line
		if [[ "$lversion" != "-" ]]; then
			lrel=${lversion#*-}
			rrel=${rversion#*-}
			lver=${lversion%-*}
			rver=${rversion%-*}
			if [[ "$rver" = "$lver" ]]; then
				# new release not a new version
				newrelease+=("$_line;rver=$rver;lrel=$lrel;rrel=$rrel")
			else
		        # new version
		        newversion+=("$_line")
			fi
		else
			# new package (not installed at this time)
			newpkgs+=("$_line")
		fi
	done
	IFS="$OLD_IFS"

	# Show result
	showupgradepackage lite
        
	# Show detail on upgrades
	if [[ $packages ]]; then                                                                                                           
		while true; do
			echo
			msg "$(gettext 'Continue upgrade ?') $(yes_no 1)"
			prompt $(gettext '[V]iew package detail   [M]anualy select packages')
			local answer=$(userinput "YNVM" "Y")
			case "$answer" in
				V)	showupgradepackage full;;
				M)	showupgradepackage manual
					run_editor "$YAOURTTMPDIR/sysuplist" 0
					declare args="$YAOURTTMPDIR/sysuplist"
					SYSUPGRADE=2
					sync_packages
					die 0
					;;
				N)	die 0;;
				*)	break;;
			esac
		done
	fi  

	# ok let's do real sysupgrade
	if [[ $packages ]]; then
		su_pacman -S $PACMAN_S_ARG ${packages[@]}
	fi
}

# Show package to upgrade
showupgradepackage()
{
	# $1=full or $1=lite or $1=manual
	if [[ "$1" = "manual" ]]; then
		> $YAOURTTMPDIR/sysuplist
		local separator="################################################"
	fi

	# show new release
	if [[ $newrelease ]]; then
		echo
		if [[ "$1" = "manual" ]]; then
			echo -e "$separator\n# $(gettext 'Package upgrade only (new release):')\n$separator" >> $YAOURTTMPDIR/sysuplist
		else
			msg $(eval_gettext 'Package upgrade only (new release):')
		fi
		for line in "${newrelease[@]}"; do
			eval $line
			if [[ "$1" = "manual" ]]; then
				echo -e "\n$repo/$pkgname version $rver release $lrel -> $rrel"  >> $YAOURTTMPDIR/sysuplist
				echo "#    $pkgdesc" >> $YAOURTTMPDIR/sysuplist
			else
				echo -e "${COL_REPOS[$repo]:-$COL_O_REPOS}$repo/$NO_COLOR$COL_BOLD$pkgname$NO_COLOR version $COL_GREEN$rver$NO_COLOR release $COL_BOLD$lrel$NO_COLOR -> $COL_RED$rrel$NO_COLOR"
				[[ "$1" = "full" ]] && echo -e "  $COL_ITALIQUE$pkgdesc$NO_COLOR"
			fi
		done
	fi
	
	# show new version
	if [[ $newversion ]]; then
		echo
		if [[ "$1" = "manual" ]]; then
			echo -e "\n\n$separator\n# $(gettext 'Software upgrade (new version) :')\n$separator" >> $YAOURTTMPDIR/sysuplist
		else
			msg $(eval_gettext 'Software upgrade (new version) :')
		fi
		for line in "${newversion[@]}"; do
			eval $line
			if [[ "$1" = "manual" ]]; then
				echo -e "\n$repo/$pkgname $lversion -> $rversion" >> $YAOURTTMPDIR/sysuplist
				echo "#    $pkgdesc" >> $YAOURTTMPDIR/sysuplist
			else
				echo -e "${COL_REPOS[$repo]:-$COL_O_REPOS}$repo/$NO_COLOR$COL_BOLD$pkgname$NO_COLOR $COL_GREEN$lversion$NO_COLOR -> $COL_RED$rversion$NO_COLOR"
				[[ "$1" = "full" ]] && echo -e "  $COL_ITALIQUE$pkgdesc$NO_COLOR"
			fi
		done
	fi

	# show new package
	if [[ $newpkgs ]]; then
       	echo
		if [[ "$1" = "manual" ]]; then
			echo -e "\n$separator\n# $(eval_gettext 'New package :')\n$separator" >> $YAOURTTMPDIR/sysuplist
		else
			msg $(eval_gettext 'New package :')
		fi
		for line in "${newpkgs[@]}"; do
			eval $line
			### Searching for package which depends on 'new package'
			local pkg_dep_on=( $(package-query -S --query-type depends -f "%n" "$pkgname") )
			local requiredbypkg
			for pkg in ${pkg_dep_on[@]}; do
				in_array "$pkg" "${packages[@]}" &&	requiredbypkg=$pkg && break
			done
			[[ "$requiredbypkg" ]] || requiredbypkg=$(gettext 'not found')

			if [[ "$1" = "manual" ]]; then
				echo -e "\n$repo/$pkgname $rversion" >> $YAOURTTMPDIR/sysuplist
				echo "#    $pkgdesc $(eval_gettext '(required by $requiredbypkg)')" >> $YAOURTTMPDIR/sysuplist
			else
				echo -e "${COL_REPOS[$repo]:-$COL_O_REPOS}$repo/$NO_COLOR$COL_BOLD$pkgname $COL_GREEN$rversion $COL_RED ($(gettext 'required by ')$requiredbypkg)$NO_COLOR"
				[[ "$1" = "full" ]] && echo -e "  $COL_ITALIQUE$pkgdesc$NO_COLOR"
			fi
		done
	fi
}

# Sync packages
sync_packages()
{
	local repo_pkgs aur_pkgs _pkg
	# Install from a list of packages
	if [[ -f "${args[0]}" ]] && file -b "${args[0]}" | grep -qi text ; then
		if (( ! SYSUPGRADE )); then 
			title $(gettext 'Installing from a list of a packages')
			msg $(gettext 'Installing from a list of a packages')"($_pkg_list)"
		fi
		AURVOTE=0
		args=( `grep -o '^[^#[:space:]]*' "${args[0]}"` ) 
	fi
	[[ "$args" ]] || return 0
	# Install from arguments
	declare -a pkgs
	for _line in $(package-query -1ASif "%t/%r/%n" "${args[@]}"); do
		local repo="${_line%/*}"
		repo="${repo##*/}"
		[[ "$repo" = "-" ]] && continue
		local pkg="${_line##*/}"
		local target="${_line%/$repo/$pkg}"
		[[ "${repo}" != "aur" ]] && repo_pkgs+=("${repo}/${pkg}") || aur_pkgs+=("$pkg")
		pkgs+=("$target")
	done
	for _pkg in "${args[@]}"; do
		in_array "$_pkg" "${pkgs[@]}" || binariespackages+=("$_pkg")
	done
	[[ $repo_pkgs ]] && install_from_abs "${repo_pkgs[@]}"
	for _pkg in "${aur_pkgs[@]}"; do install_from_aur "$_pkg"; done
	# Install precompiled packages
	[[ $binariespackages ]] && su_pacman -S $PACMAN_S_ARG "${binariespackages[@]}"
}

# Search to upgrade devel package 
upgrade_devel_package(){
	local devel_pkgs
	title $(eval_gettext 'upgrading SVN/CVS/HG/GIT package')
	msg $(eval_gettext 'upgrading SVN/CVS/HG/GIT package')
	loadlibrary pacman_conf
	create_ignorepkg_list
	for PKG in $(pacman -Qq | grep "\-\(svn\|cvs\|hg\|git\|bzr\|darcs\)")
	do
		if in_array "$PKG" "${PKGS_IGNORED[@]}"; then
			echo -e "${PKG}: ${COL_RED} "$(gettext '(ignored from pacman.conf)')"${NO_COLOR}"
		else
			devel_pkgs+=($PKG)
		fi
	done
	[[ $devel_pkgs ]] || return 0
	echo
	plain $(gettext 'SVN/CVS/HG/GIT/BZR packages that can be updated from ABS or AUR:')
	echo "${devel_pkgs[@]}"
	prompt "$(eval_gettext 'Do you want to update these packages ? ') $(yes_no 1)"
	useragrees || return 0
	for PKG in ${devel_pkgs[@]}; do
		build_or_get "$PKG"
	done
}


