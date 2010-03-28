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

# Query installed version
pkgversion()
{
	package-query -Qif "%v" $1
}

# search in sync db for packages wich depends on/conflicts whith/provides argument
searchforpackageswhich(){
	# repositories variable is set by pacman_conf.sh
	#action can be %DEPENDS% %REQUIREDBY %CONFLICTS% %PROVIDES%
	local action=$1
	local name=$2
	package-query -S -t $action $name -f "%n %v %l" |
	while read package ver lver; do
		if [ "$lver" != "-" ]; then
			echo -e "$package $ver $COL_RED[installed]$NO_COLOR"
		else
			echo $package $ver
		fi
	done
}

search_which_package_owns(){
for arg in ${args[@]}; do
	#msg "who owns $arg ?"
	title $(eval_gettext 'Searching wich package owns "$arg"')
	argpath=$(type -p "$arg") || argpath="$arg"
	$PACMANBIN -Qo "$argpath"
done
}

# searching for packages installed as dependecy from another packages, but not required anymore
search_forgotten_orphans(){
orphans=( `pacman -Qqdt` )
if [ ${#orphans[@]} -eq 0 ]; then return 0; fi
msg "$(eval_gettext 'Packages installed as dependencies but are no longer required by any installed package')"
echo -en "${COL_YELLOW}"
for orphan in ${orphans[@]}; do
      	echo "$orphan"
done
echo -e "${NO_COLOR}"
prompt "$(eval_gettext 'Do you want to remove these packages (with -Rcs options) ? ') $(yes_no 2)"
remove=$(userinput)
echo
if [ "$remove" = "Y" ]; then
	$YAOURTCOMMAND -Rcs ${orphans[@]}
fi
}

# list installed packages filtered by criteria
list_installed_packages(){
	_msg=""
	if (( DEPENDS )); then
		_msg='List all packages installed as dependencies'
	elif (( EXPLICITE )); then
		(( UNREQUIRED )) && _msg="and not required by any package"
		_msg="List all packages explicitly installed $_msg"
	elif (( UNREQUIRED )); then
		_msg='List all packages installed (explicitly or as depends) and not required by any package'
	elif (( FOREIGN )); then
		_msg='List installed packages not found in sync db(s)'
	elif (( GROUP )); then
		_msg='List all installed packages members of a group'
	elif (( DATE )); then
		_msg='List last installed packages '
		> $YAOURTTMPDIR/instdate
	else
		_msg='List all installed packages'
	fi
	title $(gettext "$_msg")
	msg $(gettext "$_msg")
	$PACMANBIN $ARGSANS -q ${args[*]} | cut -d' ' -f2 |
	xargs package-query -1QSif "%1 %r %n %v %g" |
	while read _date repository name version group; do
		_msg=$(colorizeoutputline "$repository/")
		_msg="$_msg${NO_COLOR}${COL_BOLD}${name} ${COL_GREEN}${version}$NO_COLOR"
		[ "$group" != "-" ] && _msg="$_msg  ${COL_GROUP}(${group})$NO_COLOR"
		(( DATE )) && echo -e "$_date $_msg" >> $YAOURTTMPDIR/instdate || echo -e $_msg 
	done
	if (( DATE )); then
		sort $YAOURTTMPDIR/instdate | awk '{printf("%s: %s %s %s\n", strftime("%X %x",$1), $2, $3, $4)}'
	fi
}

