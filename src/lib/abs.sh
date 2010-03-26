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
loadlibrary pkgbuild
ABS_REPO=(testing core extra community-testing community gnome-unstable kde-unstable)

# if package is from ABS_REPO, try to build it from abs, else pass it to aur
build_or_get ()
{
	[ -z "$1" ] && return 1
	local pkg=${1#*/}
	[ "$1" != "${1///}" ] && local repo=${1%/*} || local repo="$(sourcerepository $pkg)"
	BUILD=1
	in_array "$repo" "${ABS_REPO[@]}" && install_from_abs "$1" 
	if [ $? -ne 0 ]; then
		if [ "$MAJOR" = "getpkgbuild" ]; then
			aur_get_pkgbuild "$pkg"
		else
			install_from_aur "$pkg"
		fi
	fi
}

# download package from repos or grab PKGBUILD from repos.archlinux.org and run makepkg
install_from_abs(){
if [ $NOCONFIRM -eq 0 -a $SYSUPGRADE -eq 1 ]; then
	echo
	_pkgs="$*"
	echo "$(eval_gettext 'Source Targets:  $_pkgs')"
	echo -ne "\n$(eval_gettext 'Proceed with upgrade? ') $(yes_no 1) "
	[ "`userinput`" = "N" ] && return 0
fi
for package in $(package-query -1Sif "%r/%n" "$@"); do
	PKG=${package#*/}
	local repository=${package%/*}
	if [ $BUILD -eq 0 -a ! -f "/etc/customizepkg.d/$PKG" ]; then
		binariespackages[${#binariespackages[@]}]=${package#-/}
		continue
	fi
	[ "$MAJOR" != "getpkgbuild" ] && msg "Building $PKG from sources"
	title $(eval_gettext 'Install $PKG from sources')
	failed=0

	echo
	if [ "$MAJOR" != "getpkgbuild" ]; then
		msg $(eval_gettext 'Retrieving PKGBUILD and local sources...')
		wdir="$YAOURTTMPDIR/abs-$PKG"
		if [ -d "$wdir" ]; then
			rm -rf "$wdir" || { error $(eval_gettext 'Unable to delete directory $wdir. Please remove it using root privileges.'); return 1; }
		fi
		mkdir -p "$wdir" || { error $(eval_gettext 'Unable to create directory $wdir.'); return 1; }
		cd $wdir
	fi

	rsync -mrtv --no-motd --no-p --no-o --no-g rsync.archlinux.org::abs/$(arch)/$repository/$PKG/ . || return 1

	[ "$MAJOR" = "getpkgbuild" ] && return 0

	msg "$pkgname $pkgver-$pkgrel $([ "$branchtags" = "TESTING" ] && echo -e "$COL_BLINK[TESTING]")"
	
	# Customise PKGBUILD
	[ $CUSTOMIZEPKGINSTALLED -eq 1 ] && customizepkg --modify
	# Build, install/export
	package_loop 1 || { manage_error 1; continue; }
done


}


# Searching for packages to update, buid from sources if necessary
sysupgrade()
{
	prepare_orphan_list
	local _arg=""
	(( UPGRADES > 1 )) && _arg="$_arg -u"
	(( NEEDED )) && _arg="$_arg --needed"
	$PACMANBIN --sync --sysupgrade --print-uris $_arg $IGNOREPKG 1>$YAOURTTMPDIR/sysupgrade
	
	if [ $? -ne 0 ]; then
		cat $YAOURTTMPDIR/sysupgrade
	fi
	packages=( `grep '://' $YAOURTTMPDIR/sysupgrade | sed -e "s/^.*\///" -e "s/.pkg.tar.*$//" -e "s/-i686$//" -e "s/-x86_64$//" \
	-e "s/-any$//" -e "s/-ppc$//" -e "s/-[^-]*-[^-]*$//" | sort --reverse` )
	[ -z "$packages" ] && return 0	

	# Specific upgrade: pacman and yaourt first. Ask to mount /boot for kernel26 or grub
	for package in ${packages[@]}; do
		case $package in
			pacman|yaourt)
			warning $(eval_gettext 'New version of $package detected')
			prompt "$(eval_gettext 'Do you want to update $package first ? ')$(yes_no 1)"
			[ "`userinput`" = "N" ] && continue
			echo
			msg $(eval_gettext 'Upgrading $package first')
			pacman_queuing; launch_with_su "$PACMANBIN -S $package"
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

	# Specific upgrade: packages to build from sources
	if [ $BUILD -eq 1 -o $CUSTOMIZEPKGINSTALLED -eq 1 ] && [ $DOWNLOAD -eq 0 ]; then
		for package in ${packages[@]}; do
			if [ $BUILD -eq 1 -o -f "/etc/customizepkg.d/$package" ]; then
				packagesfromsource[${#packagesfromsource[@]}]=$package
			fi
		done
		if [ ${#packagesfromsource[@]} -gt 0 ]; then
			msg $(eval_gettext 'Packages to build from sources:')
			$PACMANBIN --query --sysupgrade $_arg $IGNOREPKG
			# Show package list before building
			if [ $NOCONFIRM -eq 0 ]; then
				echo -n "$(eval_gettext 'Proceed with compilation and installation ? ')$(yes_no 1)"
				proceed=`userinput`
			fi
			# Build packages if needed
			if [ "$proceed" != "N" ]; then
				BUILD=1
				install_from_abs "${packagesfromsource[*]}"
				die 0
			fi
		fi
	fi

	# Classic sysupgrade
	### classify pkg to upgrade, filtered by category "new release", "new version", "new pkg"
	OLD_IFS="$IFS"
	IFS=$'\n'
	for _line in $(package-query -1Sei \
		-f "pkgname=%n;repository=%r;rversion=%v;lversion=%l;description=\"%d\"" \
		"${packages[@]}"); do
		eval $_line
		if [ "$lversion" != "-" ]; then
			lrel=${lversion#*-}
			rrel=${rversion#*-}
			lver=${lversion%-*}
			rver=${rversion%-*}
			if [ "$rver" = "$lver" ] && `is_x_gt_y $rrel $lrel`; then
				# new release not a new version
				newrelease[${#newrelease[@]}]="$_line;rver=$rver;lrel=$lrel;rrel=$rrel"
			else
		        # new version
		        newversion[${#newversion[@]}]="$_line"
			fi
		else
			# new package (not installed at this time)
			newpkgs[${#newpkgs[@]}]="$_line"
		fi
	done
	IFS="$OLD_IFS"

	# Show result
	showupgradepackage lite
        
	# Show detail on upgrades
	if [ ${#packages[@]} -gt 0 ]; then                                                                                                           
		if [ $NOCONFIRM -eq 0 ]; then
			CONTINUE_INSTALLING="V"
			while [ "$CONTINUE_INSTALLING" = "V" -o "$CONTINUE_INSTALLING" = "C" ]; do
				echo
				echo -e "${COL_ARROW}==>  ${NO_COLOR}${COL_BOLD}$(eval_gettext 'Continue installing ''$PKG''? ') $(yes_no 1)${NO_COLOR}" >&2
				prompt $(eval_gettext '[V]iew package detail   [M]anualy select packages')
				CONTINUE_INSTALLING=$(userinput "YNVM")
				echo
				if [ "$CONTINUE_INSTALLING" = "V" ]; then
					showupgradepackage full
				elif [ "$CONTINUE_INSTALLING" = "M" ]; then
					showupgradepackage manual
					run_editor "$YAOURTTMPDIR/sysuplist" 0
					declare args="$YAOURTTMPDIR/sysuplist"
					SYSUPGRADE=2
					sync_packages
					die 0
				elif [ "$CONTINUE_INSTALLING" = "N" ]; then
					die 0
				fi
			done
		fi
	fi  

	# ok let's do real sysupgrade
	if [ ${#packages[@]} -gt 0 ]; then
		pacman_queuing;	launch_with_su "$PACMANBIN $ARGSANS"
	fi
}

## show package to upgrade
showupgradepackage()
{
	# $1=full or $1=lite or $1=manual
	if [ "$1" = "manual" ]; then
		> $YAOURTTMPDIR/sysuplist
		local separator="################################################"
	fi

	# show new release
	if [ ${#newrelease[@]} -gt 0 ]; then
		echo
		if [ "$1" = "manual" ]; then
			echo -e "$separator\n# $(eval_gettext 'Package upgrade only (new release):')\n$separator" >> $YAOURTTMPDIR/sysuplist
		else
			msg $(eval_gettext 'Package upgrade only (new release):')
		fi
		for line in "${newrelease[@]}"; do
			eval $line
			if [ "$1" = "manual" ]; then
				echo -e "\n$repository/$pkgname version $rver release $lrel -> $rrel"  >> $YAOURTTMPDIR/sysuplist
				echo "#    $description" >> $YAOURTTMPDIR/sysuplist
			else
				echo -e `colorizeoutputline $repository/$NO_COLOR$COL_BOLD$pkgname`"$NO_COLOR version $COL_GREEN$rver$NO_COLOR release $COL_BOLD$lrel$NO_COLOR -> $COL_RED$rrel$NO_COLOR"
				[ "$1" = "full" ] && echo -e "    $COL_ITALIQUE$description$NO_COLOR"
			fi
		done
	fi
	
	# show new version
	if [ ${#newversion[@]} -gt 0 ]; then
		echo
		if [ "$1" = "manual" ]; then
			echo -e "\n\n$separator\n# $(eval_gettext 'Software upgrade (new version) :')\n$separator" >> $YAOURTTMPDIR/sysuplist
		else
			msg $(eval_gettext 'Software upgrade (new version) :')
		fi
		for line in "${newversion[@]}"; do
			eval $line
			if [ "$1" = "manual" ]; then
                        	echo -e "\n$repository/$pkgname $lversion -> $rversion" >> $YAOURTTMPDIR/sysuplist
				echo "#    $description" >> $YAOURTTMPDIR/sysuplist
			else
                        	echo -e `colorizeoutputline $repository/$NO_COLOR$COL_BOLD$pkgname`$NO_COLOR" $COL_GREEN$lversion$NO_COLOR -> $COL_RED$rversion$NO_COLOR"
				[ "$1" = "full" ] && echo -e "    $COL_ITALIQUE$description$NO_COLOR"
			fi
		done
	fi

	# show new package
	if [ ${#newpkgs[@]} -gt 0 ]; then
       	echo
		if [ "$1" = "manual" ]; then
			echo -e "\n$separator\n# $(eval_gettext 'New package :')\n$separator" >> $YAOURTTMPDIR/sysuplist
		else
			msg $(eval_gettext 'New package :')
		fi
		for line in "${newpkgs[@]}"; do
			eval $line
			### Searching for package which depends on 'new package'
			requiredbypkg=$(eval_gettext 'not found')
			for pkg in ${packages[@]}; do
				if [ "$pkg" != "$pkgname" ] && `LC_ALL=C pacman -Si $pkg |grep -m1 -A15 "^Repository"| sed -e '1,/^Provides/d' -e '/^Optional\ Deps/,$d'\
				       | grep -q "\ $pkgname[ >=<]"`; then
					requiredbypkg=$pkg
					break
				fi
			done

			if [ "$1" = "manual" ]; then
				echo -e "\n$repository/$pkgname $rversion" >> $YAOURTTMPDIR/sysuplist
				echo "#    $description $(eval_gettext '(required by $requiredbypkg)')" >> $YAOURTTMPDIR/sysuplist
			else
				echo -e `colorizeoutputline $repository/$NO_COLOR$COL_BOLD$pkgname`" $COL_GREEN$rversion $COL_RED $(eval_gettext '(required by $requiredbypkg)')$NO_COLOR"
				[ "$1" = "full" ] && echo -e "    $COL_ITALIQUE$description$NO_COLOR"
			fi
		done
	fi
}

# Sync packages
sync_packages()
{
	# Install from a list of packages
	if [ -f "${args[0]}" ] && file -b "${args[0]}" | grep -qi text ; then
		if [ $SYSUPGRADE -eq 0 ]; then 
			title $(eval_gettext 'Installing from a list of a packages')
			msg $(eval_gettext 'Installing from a list of a packages ($_pkg_list)')
		fi
		_pkg_list=${args[0]}
		AURVOTE=0
		args=( `grep -o '^[^#[:space:]]*' "${args[0]}"` ) 
	fi
	[ -z "$args" ] && return 0
	# Install from arguments
	prepare_orphan_list
	declare -a pkgs
	for _line in $(package-query -1ASif "%t/%r/%n" "${args[@]}"); do
		local repo="${_line%/*}"
		repo="${repo##*/}"
		local pkg="${_line##*/}"
		local target="${_line%/$repo/$pkg}"
		if [ "${repo}" != "aur" ]; then
			repos_package[${#repos_package[@]}]="${repo}/${pkg}"
		else
			install_from_aur "${pkg}" || failed=1
		fi
		pkgs[${#pkgs[@]}]="$target"
	done
	for _pkg in "${args[@]}"; do
		in_array "$_pkg" "${pkgs[@]}" || binariespackages[${#binariespackages[@]}]="$_pkg"
	done
	(( ${#repos_package[@]} )) && install_from_abs "${repos_package[@]}"
	# Install precompiled packages
	if (( ${#binariespackages[@]} )); then
		pacman_queuing;	launch_with_su $PACMANBIN $ARGSANS "${binariespackages[@]}"
	fi
	show_new_orphans
}

upgrade_devel_package(){
	tmp_files="$YAOURTTMPDIR/search/"
	mkdir -p $tmp_files
	local i=0
	title $(eval_gettext 'upgrading SVN/CVS/HG/GIT package')
	msg $(eval_gettext 'upgrading SVN/CVS/HG/GIT package')
	loadlibrary pacman_conf
	create_ignorepkg_list || error $(eval_gettext 'list ignorepkg in pacman.conf')
	for PKG in $(pacman -Qq | grep "\-\(svn\|cvs\|hg\|git\|bzr\|darcs\)")
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
		prompt "$(eval_gettext 'Do you want to update these packages ? ') $(yes_no 1)"
		[ "`userinput`" = "N" ] && return 0
	fi
	for PKG in ${devel_package[@]}; do
		build_or_get "$PKG"
	done
}


