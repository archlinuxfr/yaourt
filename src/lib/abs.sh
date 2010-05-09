#!/bin/bash
#
# abs.sh 
# This file is part of Yaourt (http://archlinux.fr/yaourt-en)

RSYNCCMD=$(type -p rsync 2> /dev/null)
RSYNCOPT="-mrtv --no-motd --no-p --no-o --no-g"
RSYNCSRC="rsync.archlinux.org::abs"

loadlibrary alpm_query
loadlibrary pkgbuild

# Get sources in current dir
# Usage abs_get_pkgbuild ($repo/$pkg[,$arch])
abs_get_pkgbuild ()
{
	local repo=${1%/*} pkg=${1#*/}
	if [[ $RSYNCCMD ]] && in_array "$repo" "${ABS_REPO[@]}"; then
		[[ $3 ]] && local arch=$3 || \
			local arch=$(pkgquery -Sif "%a" "$repo/$pkg")
		$RSYNCCMD $RSYNCOPT "$RSYNCSRC/$arch/$repo/$pkg/" . && return 0
	fi
	# TODO: store abs archive somewhere else.
	local abs_tar="$YAOURTTMPDIR/$repo.abs.tar.gz"
	local abs_url 
	local repo_date=$(stat -c "%Z" "$PACMANDB/sync/$repo/.lastupdate")
	local abs_repo_date=$(stat -c "%Z" "$abs_tar" 2> /dev/null)
	if (( $? )) || (( abs_repo_date < repo_date )); then
		abs_url=$(pkgquery -1Sif "%u" "$repo/$pkg")
		abs_url="${abs_url%/*}/$repo.abs.tar.gz"
		msg "$1: $(gettext 'retrieve abs archive')"
		curl -f -# "$abs_url" -o "$abs_tar" || return 1
	fi
	bsdtar -s "/${repo}.${pkg}//" -xvf "$abs_tar" "$repo/$pkg"
}

# Build from abs or aur
build_or_get ()
{
	[[ $1 ]] || return 1
	local pkg=${1#*/} _func="aur"
	[[ "$1" != "${1///}" ]] && local repo=${1%/*} || \
		local repo="$(sourcerepository $pkg)"
	[[ -n "$repo" && "$repo" != "aur" && "$repo" != "local" ]] && _func="abs"
	if [[ "$MAJOR" = "getpkgbuild" ]]; then
		${_func}_get_pkgbuild "$repo/$pkg"
	else
		BUILD=1 install_from_${_func} "$repo/$pkg"
	fi
}

sync_first ()
{
	[[ $* ]] || return 0
	warning $(eval_gettext 'The following packages should be upgraded first :')
	echo_wrap 4 "$*"
	prompt "$(eval_gettext 'Do it now ?') $(yes_no 1)"
	useragrees || return 0
	args=("$@")
	sync_packages
	die $?
}

# Build packages from repos
install_from_abs(){
	for _line in $(pkgquery -1Sif "repo=%r;PKG=%n;_pkgver=%v;_arch=%a" "$@"); do
		eval $_line
		local package="$repo/$PKG"
		(( ! BUILD )) && ! custom_pkg "$PKG" && binariespackages+=(${package#-/}) && continue
		msg $(eval_gettext 'Building $PKG from sources.')
		title $(eval_gettext 'Install $PKG from sources')
		echo
		msg $(gettext 'Retrieving PKGBUILD and local sources...')
		init_build_dir "$YAOURTTMPDIR/abs-$PKG" || return 1

		# With splitted package, abs folder may not correspond to package name
		local pkgbase=( $(grep -A1 '%BASE%' "$PACMANDB/sync/$repo/$PKG-$_pkgver/desc" ) )
		[[ $pkgbase ]] || pkgbase=( '' "$PKG" )
		abs_get_pkgbuild $repo/${pkgbase[1]} $_arch || return 1
		[[ "$MAJOR" = "getpkgbuild" ]] && return 0

		# Build, install/export
		package_loop 1 || { manage_error 1; continue; }
	done
}

# Set vars:
# upgrade_details=(new release, new version then new pkgs)
# syncfirstpkgs=(pkgs in SyncFirst from pacman.conf)
# srcpkgs=(pkgs with a custom pkgbuild)
# pkgs=(others)
# usage: classify_pkg $pkg_nb < [one pkg / line ] 
# read from stdin: pkgname repo rversion lversion outofdate pkgdesc
classify_pkg ()
{
	unset newrelease newversion newpkgs syncfirstpkgs srcpkgs pkgs
	longestpkg=(0 0) 
	local i=0 bar="|/-\\"
	while read pkgname repo rversion lversion outofdate pkgdesc; do
		printf -v pkgdesc "%q" "$pkgdesc"
		((! DETAILUPGRADE )) && echo -en "${bar:$((++i%4)):1} $i / $1\r"
		if [[ "$repo" = "aur" ]]; then
			aur_update_exists "$pkgname" "$rversion" "$lversion" "$outofdate" \
				|| continue
		fi
		[[ " ${SyncFirst[@]} " =~ " $pkgname " ]] && syncfirstpkgs+=("$pkgname")
		custom_pkg "$pkgname" && srcpkgs+=("$pkgname") || pkgs+=("$pkgname")
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
			local pkg_dep_on=( $(pkgquery -S --query-type depends -f "%n" "$pkgname") )
			for pkg in ${pkg_dep_on[@]}; do
				in_array "$pkg" "${packages[@]}" &&	requiredbypkg=$pkg && break
			done
			newpkgs+=("3 $repo $pkgname $pkgver $requiredbypkg - $pkgdesc")
		fi
		(( ${#repo} + ${#pkgname} > longestpkg[0] )) && longestpkg[0]=$(( ${#repo} + ${#pkgname}))
		(( ${#pkgver} > longestpkg[1] )) && longestpkg[1]=${#pkgver}
	done 
	((! DETAILUPGRADE)) && echo -n "            "
	(( longestpkg[1]+=longestpkg[0] ))
	upgrade_details=("${newrelease[@]}" "${newversion[@]}" "${newpkgs[@]}")
	unset newrelease newversion newpkgs
}

display_update ()
{
	# Show result
	showupgradepackage lite
        
	# Show detail on upgrades
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
				return 2
				;;
			N)	return 1;;
			*)	break;;
		esac
	done
}

show_targets ()
{
	local t="$(gettext "$1") "; shift
	t+="($#): "
	echo
	echo_wrap_next_line "$COL_YELLOW$t$NO_COLOR" ${#t} "$*" 
	echo
	prompt "$(gettext 'Proceed with upgrade? ') $(yes_no 1) "
	useragrees 
}	

# Searching for packages to update, buid from sources if necessary
sysupgrade()
{
	(( UPGRADES > 1 )) && local _arg="-uu" || local _arg="-u"
	(( ! DETAILUPGRADE )) && { su_pacman -S "${PACMAN_S_ARG[@]}" $_arg; return $?; }
	pacman_parse -Sp $_arg "${PACMAN_S_ARG[@]}" 1> "$YAOURTTMPDIR/sysupgrade" || return 1
	
	packages=($(grep '://' "$YAOURTTMPDIR/sysupgrade"))
	packages=("${packages[@]##*/}")
	packages=("${packages[@]%-*-*-*.pkg*}")
	rm "$YAOURTTMPDIR/sysupgrade"
	[[ ! "$packages" ]] && return 0	
	loadlibrary pacman_conf
	classify_pkg < <(pkgquery -1Sif '%n %r %v %l - %d' "${packages[@]}")
	sync_first "${syncfirstpkgs[@]}"
	(( BUILD )) && srcpkgs+=("${pkgs[@]}") && unset pkgs
	if [[ $srcpkgs ]]; then 
		show_targets 'Source targets' "${srcpkgs[@]}" || return 0
		BUILD=1 install_from_abs "${srcpkgs[@]}" 
		local ret=$?
		[[ $pkgs ]] || return $ret
	fi
	[[ $pkgs ]] || return 0
	display_update && su_pacman -S "${PACMAN_S_ARG[@]}" "${pkgs[@]}"
}

# Show package to upgrade
showupgradepackage()
{
	# $1=full or $1=lite or $1=manual
	if [[ "$1" = "manual" ]]; then
		> "$YAOURTTMPDIR/sysuplist"
		local separator=$(echo_fill "" "#" "")
	fi
	
	local exuptype=0
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
			msg $(gettext 'Installing from a package list')
		fi
		AURVOTE=0
		args=( `grep -o '^[^#[:space:]]*' "${args[0]}"` ) 
	fi
	[[ "$args" ]] || return 0
	# Install from arguments
	local pkgs=()
	while read repo pkg target; do
		[[ "$repo" = "-" ]] && continue
		[[ "${repo}" != "aur" ]] && repo_pkgs+=("${repo}/${pkg}") || aur_pkgs+=("$pkg")
		pkgs+=("$target")
	done < <(pkgquery -1ASif "%r %n %t" "${args[@]}")
	for _pkg in "${args[@]}"; do
		in_array "$_pkg" "${pkgs[@]}" || binariespackages+=("$_pkg")
	done
	[[ $repo_pkgs ]] && install_from_abs "${repo_pkgs[@]}"
	[[ $binariespackages ]] && su_pacman -S "${PACMAN_S_ARG[@]}" "${binariespackages[@]}"
	for _pkg in "${aur_pkgs[@]}"; do install_from_aur "$_pkg"; done
}

# Search to upgrade devel package 
upgrade_devel_package(){
	local devel_pkgs=()
	title $(gettext 'upgrading SVN/CVS/HG/GIT package')
	msg $(gettext 'upgrading SVN/CVS/HG/GIT package')
	loadlibrary pacman_conf
	for PKG in $(pacman_parse -Qq | grep "\-\(svn\|cvs\|hg\|git\|bzr\|darcs\)")
	do
		is_package_ignored "$PKG" && continue
		devel_pkgs+=($PKG)
	done
	[[ $devel_pkgs ]] || return 0
	show_targets 'Targets' "${devel_pkgs[@]}" && for PKG in ${devel_pkgs[@]}; do
		build_or_get "$PKG"
	done
}

# vim: set ts=4 sw=4 noet: 
