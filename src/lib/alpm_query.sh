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
	for _line in $(package-query -S -t $action $name -f "package=%n;ver=%v;lver=%l"); do
		eval $_line
		if [ "$lver" != "-" ]; then
			echo -e "$package $ver $COL_RED[installed]$NO_COLOR"
		else
			echo $package $ver
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
orphans=( `pacman -Qqdt` )
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

	OLD_IFS="$IFS"
	IFS=$'\n'
	for _line in $(package-query -Qe ${args[*]} -f "package=%n;version=%v;version=%v;group=%g;repository=%r;description=\"%d\""); do
		eval $_line
		echo -e `colorizeoutputline "$repository/${NO_COLOR}${COL_BOLD}${package} ${COL_GREEN}${version} ${COL_GROUP}$group${NO_COLOR}"` 
		echo -e "  $COL_ITALIQUE$description$NO_COLOR" 
	done
	IFS="$OLD_IFS"
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
	elif [ $DATE -eq 1 ]; then
		msg $(eval_gettext 'List last installed packages ')
		title $(eval_gettext 'List last installed packages')
		> $YAOURTTMPDIR/instdate
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
		if [ $DATE -eq 1 ]; then
			installdate=`LC_ALL=C pacman -Qi $col1 | grep "^Install Date"| awk -F " : " '{print $2}'`
			echo -e "`date --date "$installdate" +%s` `colorizeoutputline "$repository/${NO_COLOR}${COL_BOLD}${col1} ${COL_GREEN}${col2}$NO_COLOR"`" >> $YAOURTTMPDIR/instdate 
		else
			echo -e `colorizeoutputline "$repository/${NO_COLOR}${COL_BOLD}${col1} ${COL_GREEN}${col2}$NO_COLOR"` 
		fi
	done
	if [ $DATE -eq 1 ]; then
		cat $YAOURTTMPDIR/instdate | sort |
		awk '
		{
			printf("%s: %s %s\n",
			strftime("%X %x",$1), $2, $3)
		}'
	fi
}

findindependsfile(){
	#usage:  findindependsfile <section> <package> <file>
	local section=$1
	local package=$2
	local file=$3
	local nextiscandidate=0
	local filecontent=( `cat $file`)
	for word in ${filecontent[@]};do
		# parse the appropriate section only for word
		if [ $(echo "$word" | grep "^%.*%$") ]; then
			if [ "$word" = "$section" ]; then 
				iscandidate=1
			else
				iscandidate=0
			fi
		elif [ $iscandidate -eq 1 -a "${word%%[<>=]*}" = "$package" ]; then
			return 0
		fi
	done
	return 1
}
