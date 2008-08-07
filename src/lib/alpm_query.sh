#!/bin/bash
#===============================================================================
#
#          FILE: alpm_query.sh
# 
#   DESCRIPTION: yaourt's library to query packages from alpm database
# 
#       OPTIONS:  ---
#  REQUIREMENTS:  ---
#          BUGS:  ---
#         NOTES:  ---
#        AUTHOR:   Julien MISCHKOWITZ (wain@archlinux.fr) 
#       VERSION:  1.0
#===============================================================================


# search in sync db for packages wich depends on/conflicts whith/provides argument
searchforpackageswhich(){
	# repositories variable is set by pacman_conf.sh
	#action can be %DEPENDS% %REQUIREDBY %CONFLICTS% %PROVIDES%
	local action=$1
	local name=$2
	for repository in ${repositories[@]}; do
		local candidates=( ${candidates[*]} `grep -srl --include="depends" "^${name}" "$PACMANROOT/sync/$repository/"` )
	done
	for file in ${candidates[@]}; do
		if `findindependsfile "$action" "$name" "$file"`; then
			package=`echo $file| awk -F "/" '{print $(NF-1)}'`
			if [ -d "$PACMANROOT/local/$package" ]; then
				echo -e "$package $COL_RED[installed]$NO_COLOR"
			else
				echo $package
			fi
		fi
	done
	return
}

search_which_package_owns(){
for arg in ${args[@]}; do
	#msg "who owns $arg ?"
	title $(eval_gettext 'Searching wich package owns "$arg"')
	argpath=`type -p "$arg"`
	if [ ! -z "$argpath" ]; then
		eval $PACMANBIN -Qo "$argpath"
	else
		eval $PACMANBIN -Qo "$arg"
	fi
done
}

# searching for packages installed as dependecy from another packages, but not required anymore
search_forgotten_orphans(){
orphans=( `pacman -Qdt | awk '{print $1}'` )
if [ ${#orphans[@]} -eq 0 ]; then return 0; fi
for orphan in ${orphans[@]}; do
      	echo -e "${COL_YELLOW}${orphan} ${NO_COLOR}$(eval_gettext 'was installed as dependencies but are no longer required by any installed package')"
done
echo
prompt $(eval_gettext 'Do you want to remove these packages (with -Rcs options) ? ') $(yes_no 2)
remove=$(userinput)
echo
if [ "$remove" = "Y" ]; then
	$YAOURTCOMMAND -Rcs ${orphans[@]}
fi
}

# searching for argument in installed packages
search_for_installed_package(){
	_arg=${args[*]}
	title $(eval_gettext 'Searching for "$_arg" in installed packages')
	eval $PACMANBIN $ARGSANS ${args[*]}| sed 's/^ /_DESCRIPTIONline_/' |
	while read line; do
		if echo "$line" | grep -q "^_DESCRIPTIONline_"; then
			echo -e "$COL_ITALIQUE$line$NO_COLOR" | sed 's/_DESCRIPTIONline_/  /'
			continue
		fi
		package=`echo $line | grep -v "^_" | awk '{ print $1}' | sed 's/^.*\///'`
		version=`echo $line | grep -v "^_" | awk '{ print $2}' | sed 's/^.*\///'`
		group=`echo $line | sed -e 's/^[^(]*//'`
		repository=`sourcerepository $package`
		echo -e `colorizeoutputline "$repository/${NO_COLOR}${COL_BOLD}${package} ${COL_GREEN}${version} ${COL_GROUP}$group${NO_COLOR}"` 
	done
}

# list installed packages filtered by criteria
list_installed_packages(){
	if [ $DEPENDS -eq 1 ]; then
		title $(eval_gettext 'List all packages installed as dependencies')
		msg $(eval_gettext 'List all packages installed as dependencies')
	elif [ $EXPLICITE -eq 1 ]; then
		if [ $UNREQUIRED -eq 1 ]; then
			title $(eval_gettext 'List all packages explicitly installed and not required by any package')
			msg $(eval_gettext 'List all packages explicitly installed and not required by any package')
		else
			title $(eval_gettext 'List all packages explicitly installed')
			msg $(eval_gettext 'List all packages explicitly installed')
		fi
	elif [ $UNREQUIRED -eq 1 ]; then
		title $(eval_gettext 'List all packages installed (explicitly or as depends) and not required by any package')
		msg $(eval_gettext 'List all packages installed (explicitly or as depends) and not required by any package')
	elif [ $FOREIGN -eq 1 ]; then
		title $(eval_gettext 'List installed packages not found in sync db(s)')
		msg $(eval_gettext 'List installed packages not found in sync db(s)')
		eval $PACMANBIN $ARGSANS ${args[*]}
		return
	elif [ $GROUP -eq 1 ]; then
		title $(eval_gettext 'List all installed packages members of a group')
		msg $(eval_gettext 'List all installed packages members of a group')
	else
		msg $(eval_gettext 'List all installed packages')
		title $(eval_gettext 'List all installed packages')
	fi
	if [ $GROUP -eq 1 ]; then
		colpkg=2
		colsecond=1
	else
		colpkg=1
		colsecond=2
	fi
	eval $PACMANBIN $ARGSANS ${args[*]} |
	while read line; do
		local col1=$(echo $line | awk '{print $'$colpkg'}')
		local col2=$(echo $line | awk '{print $'$colsecond'}')
		local repository=`sourcerepository $col1`
		echo -e `colorizeoutputline "$repository/${NO_COLOR}${COL_BOLD}${col1} ${COL_GREEN}${col2}"` 
	done
}
