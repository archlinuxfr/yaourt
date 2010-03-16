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
	PROCEED_UPGD=`userinput`
fi
if [ "$PROCEED_UPGD" = "N" ]; then return; fi
for package in $(package-query -Sif "%r/%n" "$@"); do
	PKG=${package#*/}
	local repository=${package%/*}
	if [ $BUILD -eq 0 -a ! -f "/etc/customizepkg.d/$PKG" ]; then
		binariespackages[${#binariespackages[@]}]=$package
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

	rsync -mrtv --no-motd --no-p --no-o --no-g rsync.archlinux.org::abs/$(arch)/$repository/$PKG/ .

	[ "$MAJOR" = "getpkgbuild" ] && return 0

	check_root	# 
	
	readPKGBUILD || { manage_error 1; continue; }
	
	msg "$pkgname $pkgver-$pkgrel $([ "$branchtags" = "TESTING" ] && echo -e "$COL_BLINK[TESTING]")"
	
	# Customise PKGBUILD
	[ $CUSTOMIZEPKGINSTALLED -eq 1 ] && customizepkg --modify

	# show deps
	find_pkgbuild_deps
	manage_error $? || continue

	edit_file PKGBUILD 2 || { manage_error 1; continue; }
	
	prompt $(eval_gettext 'Continue the building of ''$PKG''? ')$(yes_no 1)
 	if [ "`userinput`" = "N" ]; then
		manage_error 1 || continue
	fi
	
	# TODO: dependecies from AUR should be downloaded here

	# compil PKGBUILD if dep's building not failed
	build_package	
	retval=$?
	if [ $retval -eq 1 ]; then
		manage_error 1 || continue
	elif [ $retval -eq 90 ]; then
		continue
	fi

	# Install, export, copy package after build 
	install_package
	manage_error $? || continue
done

# Install precompiled packages
if [ ${#binariespackages[@]} -gt 0 ]; then
	#pacman_queuing;	launch_with_su "$PACMANBIN $ARGSANS ${binariespackages[*]}"
	pacman_queuing;	launch_with_su "$PACMANBIN --sync $force $confirmation $NEEDED $nodeps $asdeps ${binariespackages[*]}"
fi

}


# Searching for packages to update, buid from sources if necessary
sysupgrade()
{
	prepare_orphan_list
	$PACMANBIN --sync --sysupgrade --print-uris $DOWNGRADE $NEEDED $IGNOREPKG 1>$YAOURTTMPDIR/sysupgrade
	
	if [ $? -ne 0 ]; then
		cat $YAOURTTMPDIR/sysupgrade
	fi
	packages=( `grep '://' $YAOURTTMPDIR/sysupgrade | sed -e "s/^.*\///" -e "s/.pkg.tar.*$//" -e "s/-i686$//" -e "s/-x86_64$//" \
	-e "s/-any$//" -e "s/-ppc$//" -e "s/-[^-]*-[^-]*$//" | sort --reverse` )
	[ -z "$packages" ] && return 0	
	# Show various warnings
	# pacman -Qu don't show warnings anymore
	#eval $PACMANBIN -Qu | sed -n '1,/^$/p' | sed '/^$/d'

	# Specific upgrade: pacman and yaourt first. Ask to mount /boot for kernel26 or grub
	for package in ${packages[@]}; do
		case $package in
			pacman|yaourt)
			warning $(eval_gettext 'New version of $package detected')
			prompt $(eval_gettext 'Do you want to update $package first ? ')$(yes_no 1)
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
			eval $PACMANBIN --query --sysupgrade $DOWNGRADE $NEEDED $IGNOREPKG
			# Show package list before building
			if [ $NOCONFIRM -eq 0 ]; then
				echo -n $(eval_gettext 'Proceed with compilation and installation ? ')$(yes_no 1)
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
				echo -e "${COL_ARROW}==>  ${NO_COLOR}${COL_BOLD}"$(eval_gettext 'Continue installing ''$PKG''? ') $(yes_no 1)"${NO_COLOR}" >&2
				prompt $(eval_gettext '[V]iew package detail   [M]anualy select packages')
				CONTINUE_INSTALLING=$(userinput "YNVM")
				echo
				if [ "$CONTINUE_INSTALLING" = "V" ]; then
					showupgradepackage full
				elif [ "$CONTINUE_INSTALLING" = "M" ]; then
					showupgradepackage manual
					run_editor "$YAOURTTMPDIR/sysuplist"
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
	for _line in $(package-query -1ASif "%r/%n" "${args[@]}"); do
		if [ "${_line%/*}" != "aur" ]; then
			repos_package[${#repos_package[@]}]="$_line"
		else
			install_from_aur "${_line#aur/}" || failed=1
		fi
	done
	[ ${#repos_package[@]} -gt 0 ] && install_from_abs "${repos_package[@]}"
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
		prompt $(eval_gettext 'Do you want to update these packages ? ') $(yes_no 1)
		[ "`userinput`" = "N" ] && return 0
	fi
	for PKG in ${devel_package[@]}; do
		build_or_get "$PKG"
	done
}

install_package(){
	# Install, export, copy package after build 
	source /etc/makepkg.conf || return 1
	readPKGBUILD
	setPARCH
	if [ $failed -ne 1 ]; then
		if [ $EXPORT -eq 1 ]; then
			#msg "Delete old ${pkgname} package"
			rm -f $EXPORTDIR/$pkgname-*-*{-$PARCH,}${PKGEXT}
			msg $(eval_gettext 'Exporting ${pkgname} to ${EXPORTDIR} repository')
			mkdir -p $EXPORTDIR/$pkgname
			manage_error $? || { error $(eval_gettext 'Unable to write ${EXPORTDIR}/${pkgname}/ directory'); die 1; }
			unset localsource
			for src in ${source[@]}; do
				if [ `echo $src | sed 's/.*:://'| grep -v ^\\\\\\(ftp\\\\\\|http\\\\\\)` ]; then
					localsource[${#localsource[@]}]=$src
				fi
			done
			localsource[${#localsource[@]}]="PKGBUILD"
			if [ ! -z "$install" ]; then localsource[${#localsource[@]}]="$install";fi
			for file in ${localsource[@]}; do
				cp -pf "$file" $EXPORTDIR/$pkgname/ 
				manage_error $? || { error $(eval_gettext 'Unable to copy $file to ${EXPORTDIR}/${pkgname}/ directory'); return 1; }
			done
			localsource[${#localsource[@]}]="$pkgname-$pkgver-$pkgrel-$PARCH${PKGEXT}" 
			cp -fp ./$pkgname-$pkgver-$pkgrel-$PARCH${PKGEXT} $EXPORTDIR/ || error $(eval_gettext 'can not copy $pkgname-$pkgver-$pkgrel-$PARCH${PKGEXT} to $EXPORTDIR')
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
					eval $PACMANBIN --query --list --file ./$pkgname-$pkgver-$pkgrel-$PARCH${PKGEXT}
					eval $PACMANBIN --query --info --file ./$pkgname-$pkgver-$pkgrel-$PARCH${PKGEXT}
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
			[ -z "$CONTINUE_INSTALLING" ] && echo
			pacman_queuing;	launch_with_su "$PACMANBIN --force --upgrade $asdeps $confirmation ./$pkgname-$pkgver-$pkgrel-$PARCH${PKGEXT}"
			if [ $? -ne 0 ]; then
				failed=1
			else
				failed=0
			fi
		fi
		if [ $failed -eq 1 ]; then 
			warning $(eval_gettext 'Your package is saved in $YAOURTTMPDIR/$pkgname-$pkgver-$pkgrel-$PARCH${PKGEXT}')
			cp -i "./$pkgname-$pkgver-$pkgrel-$PARCH${PKGEXT}" $YAOURTTMPDIR/ || warning $(eval_gettext 'Unable to copy $pkgname-$pkgrel-$PARCH${PKGEXT} to $YAOURTTMPDIR/ directory')
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
			readPKGBUILD
			if [ "`pkgversion $pkgname`" = "$pkgname-$pkgver-$pkgrel" ]; then
				msg $(eval_gettext 'There is no CVS/SVN/GIT update available for $PKG.. Aborted')
				sleep 1
				return 90
			fi
		fi
	fi

	# Check for arch variable
	readPKGBUILD || return 1
	if [ -z "$arch" ]; then
		source /etc/makepkg.conf
		[ -z "$CARCH" ] && CARCH="i686"
		warning $(eval_gettext 'the arch variable is missing !\nyaourt will add arch=(''$CARCH'') automatically.')
		sed -i "/^build/iarch=('$CARCH')\n" ./PKGBUILD
	fi

	# install deps from abs (build or download) as depends
	find_pkgbuild_deps || return 1
	if [ ${#DEP_ABS[@]} -gt 0 -a $BUILD -eq 1 ]; then
		msg $(eval_gettext 'Install or build missing dependencies for $PKG:')
		$BUILDPROGRAM --asdeps "${DEP_ABS[*]}"
		for installed_dep in ${DEP_ABS[@]}; do
			if ! `isinstalled $installed_dep`; then
				failed=1
				return 1
			fi
		done
	fi
	
	# check if package will conflict with an installed one
	pkg_conflicts=$(package-query -Qt conflicts -f "%n" "$pkgname")
	[ -z "$pkg_conflicts" ] && pkg_conflicts=$(package-query -Qt provides -f "%n" "$pkgname")
	if [ -n "$pkg_conflicts" ]; then
		prompt $(eval_gettext '$pkg_conflicts conflicts or provides $pkgname. Do you want to remove it with "pacman -Rd" ? ') $(yes_no 2)
		if [ "$(userinput)" = "Y" ]; then
			pacman_queuing; launch_with_su "$PACMANBIN -Rd $pkg_conflicts" 
			if [ $? -ne 0 ]; then
				error $(eval_gettext 'Unable to remove $pkg_conflicts.')
				return 1
			fi
		fi
	fi
		

	# Build 
	mkpkg_opt="$confirmation"
	[ $NODEPS -eq 1 ] && mkpkg_opt="$mkpkg_opt -d"
	[ $IGNOREARCH -eq 1 ] && mkpkg_opt="$mkpkg_opt -A"
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

	readPKGBUILD || return 1
	return $failed
}
find_pkgbuild_deps (){
	unset DEPS DEP_AUR DEP_ABS
	readPKGBUILD || return 1
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
		if isavailable $dep; then echo -e " - ${COL_BLUE}$dep${NO_COLOR}" $(eval_gettext '(package found)'); DEP_PACMAN=1; DEP_ABS[${#DEP_ABS[@]}]=$dep; continue; fi
		echo -e " - ${COL_YELLOW}$dep${NO_COLOR}" $(eval_gettext '(building from AUR)') 
		DEP_AUR[${#DEP_AUR[@]}]=$dep 
	done

}
