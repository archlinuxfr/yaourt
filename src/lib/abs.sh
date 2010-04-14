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
	$PACMANBIN -Sp $_arg "${PACMAN_S_ARG[@]}" 1> "$YAOURTTMPDIR/sysupgrade" || return 1
	
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
				su_pacman -S "${PACMAN_S_ARG[@]}" "$package"
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
	unset newrelease newversion newpkgs 
	longestpkg=(0 0)
	while read pkgname repo rversion lversion pkgdesc; do
		printf -v pkgdesc "%q" "$pkgdesc"
		if [[ "$lversion" != "-" ]]; then
			pkgver=$lversion
			lrel=${lversion#*-}
			rrel=${rversion#*-}
			lver=${lversion%-*}
			rver=${rversion%-*}
			if [[ "$rver" = "$lver" ]]; then
				# new release not a new version
				newrelease+=("1 $repo $pkgname $pkgver $lrel $rrel $pkgdesc")
			else
		        # new version
				newversion+=("2 $repo $pkgname $pkgver $rversion - $pkgdesc")
			fi
			(( ${#lversion} > longestpkg[1] )) && longestpkg[1]=${#lversion}
		else
			# new package (not installed at this time)
			pkgver=$rversion
			local requiredbypkg=$(printf "%q" "$(gettext 'not found')")
			local pkg_dep_on=( $(package-query -S --query-type depends -f "%n" "$pkgname") )
			for pkg in ${pkg_dep_on[@]}; do
				in_array "$pkg" "${packages[@]}" &&	requiredbypkg=$pkg && break
			done
			newpkgs+=("3 $repo $pkgname $pkgver $requiredbypkg - $pkgdesc")
		fi
		(( ${#repo} + ${#pkgname} > longestpkg[0] )) && longestpkg[0]=$(( ${#repo} + ${#pkgname}))
		(( ${#pkgver} > longestpkg[1] )) && longestpkg[1]=${#pkgver}
	done < <(package-query -1Sif '%n %r %v %l %d' "${packages[@]}")
	(( longestpkg[1]+=longestpkg[0] ))
	upgrade_details=("${newrelease[@]}" "${newversion[@]}" "${newpkgs[@]}")
	unset newrelease newversion newpkgs

	# Show result
	showupgradepackage lite
        
	# Show detail on upgrades
	if [[ $packages ]]; then                                                                                                           
		while true; do
			echo
			msg "$(gettext 'Continue upgrade ?') $(yes_no 1)"
			prompt "$(gettext '[V]iew package detail   [M]anualy select packages')"
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
		su_pacman -S "${PACMAN_S_ARG[@]}" "${packages[@]}"
	fi
}

# Show package to upgrade
showupgradepackage()
{
	# $1=full or $1=lite or $1=manual
	if [[ "$1" = "manual" ]]; then
		> "$YAOURTTMPDIR/sysuplist"
		printf -vseparator "%79s" ""
		separator=${separator// /#}
	fi
	
	local ex_uptype=0
	for line in "${upgrade_details[@]}"; do
		eval line=($line)
		if (( exuptype != ${line[0]} )); then
			case "${line[0]}" in
				1) _msg="$(gettext 'Package upgrade only (new release):')";;
				2) _msg="$(gettext 'Software upgrade (new version) :')";;
				3) _msg="$(gettext 'New package :')";;
			esac
			exuptype=${line[0]}
			if [[ "$1" = "manual" ]]; then
				echo -e "\n$separator\n# $_msg\n$separator" >> "$YAOURTTMPDIR/sysuplist"
			else
				echo
				msg "$_msg"
			fi
		fi
		if [[ "$1" = "manual" ]]; then
			echo -n "${line[1]}/${line[2]} # " >> "$YAOURTTMPDIR/sysuplist"
			case "${line[0]}" in
				1) echo "${line[3]} ${line[4]} -> ${line[5]}";;
				2) echo "${line[3]} -> ${line[4]}";;
				3) requiredbypkg=${line[4]}
				   echo "${line[3]} $(eval_gettext '(required by $requiredbypkg)')";;
			esac >> "$YAOURTTMPDIR/sysuplist"
			echo "# ${line[6]}" >> "$YAOURTTMPDIR/sysuplist"
		else
			case "${line[0]}" in
				1) printf "%*s   $COL_BOLD${line[4]}$NO_COLOR -> $COL_RED${line[5]}$NO_COLOR" ${longestpkg[1]} "";;
				2) printf "%*s   -> $COL_RED${line[4]}$NO_COLOR" ${longestpkg[1]} "";;
				3) requiredbypkg=${line[4]}
					printf "%*s   $COL_RED$(eval_gettext '(required by $requiredbypkg)')" ${longestpkg[1]} "";;
			esac
			printf "\r%-*s  ${COL_GREEN}${line[3]}${NO_COLOR}" ${longestpkg[0]} ""
			pkg_output ${line[1]} ${line[2]}
			echo -e "\r$pkgoutput"
			if [[ "$1" = "full" ]]; then
				echo_wrap 4 "${line[6]}"
			fi
		fi
	done
}		

# Sync packages
sync_packages()
{
	local repo_pkgs aur_pkgs _pkg
	# Install from a list of packages
	if [[ -f "${args[0]}" ]] && file -b "${args[0]}" | grep -qi text ; then
		if (( ! SYSUPGRADE )); then 
			title $(gettext 'Installing from a package list')
			msg $(gettext 'Installing from a package list')"($_pkg_list)"
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
	[[ $binariespackages ]] && su_pacman -S "${PACMAN_S_ARG[@]}" "${binariespackages[@]}"
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


