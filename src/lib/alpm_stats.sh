#!/bin/bash
#===============================================================================
#
#          FILE:  alpm_stats.sh
# 
#   DESCRIPTION: yaourt's library for misc stats on alpm db 
# 
#       OPTIONS:  ---
#  REQUIREMENTS:  ---
#          BUGS:  ---
#         NOTES:  ---
#        AUTHOR:   Julien MISCHKOWITZ (wain@archlinux.fr)
#       VERSION:  1.0
#===============================================================================
loadlibrary pacman_conf
loadlibrary pkgbuild
unset repos_packages pkgs_nb
buildpackagelist()
{
	list_repositories
	#construct the list of packages	
	
	for pkg in $(pacman -Q | awk '{print $1"-"$2}'); do
		(( pkgs_nb++ ))
		# recherche des infos sur les paquetages installés
		# recherche du repository d'origine du paquet
		local reponumber=0
		for repo in ${repositories[@]}; do
			if [[ -d "$PACMANROOT/sync/$repo/$pkg" ]]; then
		       		(( repos_packages[$reponumber]++ ))
				found=1
				break
			fi
			(( reponumber++ ))
		done
	done
	# Construction de la liste des paquets ignorés/noupgrade/holdpkg
	ignorepkg=(`LC_ALL="C" pacman --debug 2>/dev/null | grep "^debug: config: IgnorePkg:" |awk '{print $4}'|uniq`)
	holdpkg=(`LC_ALL="C" pacman --debug 2>/dev/null | grep "^debug: config: HoldPkg:" |awk '{print $4}'|uniq`)
	ignoregroup=(`LC_ALL="C" pacman --debug 2>/dev/null | grep "^debug: config: IgnoreGroup:" |awk '{print $4}'|uniq`)
}

showpackagestats(){
	echo -e "${COL_BLUE} -------------------------------------------${NO_COLOR}"	
	echo -e "${COL_BLUE}|$NO_COLOR    $(gettext 'Archlinux Core Dump')    $COL_GREEN($NAME $VERSION)$COL_BLUE  |${NO_COLOR}"	
	echo -e "${COL_BLUE} -------------------------------------------${NO_COLOR}\n"	
	echo -e "\n${COL_BLUE}-----------------------------------------------${NO_COLOR}"	
	echo -e "${COL_GREEN}$(gettext 'Total installed packages:')  ${COL_YELLOW}$pkgs_nb"	
	echo -e "${COL_GREEN}$(gettext 'Explicitly installed packages:')  ${NO_COLOR}${COL_YELLOW}`pacman -Qe | wc -l`"	
	echo -e "${COL_GREEN}$(gettext 'Packages installed as dependencies to run other packages:')  ${COL_YELLOW}`pacman -Qd | wc -l`"   
	local orphans=(`pacman -Qdt | awk '{print $1}' | sort`)
	if [[ $orphans ]]; then 
		_orphans=${#orphans[@]}
		echo -e "${COL_RED}$(eval_gettext 'Where $_orphans packages seems no more used by any package:')${NO_COLOR}"
		echo -e "$NO_COLOR${orphans[*]}$NO_COLOR"
	else
		echo -e "${COL_GREEN}$(gettext 'Packages installed as dependencies but no more required:')  ${COL_YELLOW}0"  
	fi
	echo -e "${COL_GREEN}$(gettext 'Number of HoldPkg:')  ${NO_COLOR}${COL_YELLOW}${#holdpkg[@]}"
	echo -e "${COL_GREEN}$(gettext 'Number of IgnorePkg:')  ${NO_COLOR}${COL_YELLOW}${#ignorepkg[@]}"
	echo -e "${COL_GREEN}$(gettext 'Group ignored:')  ${NO_COLOR}${COL_YELLOW}${ignoregroup[*]}"
	echo -e "\n${COL_BLUE}-----------------------------------------------${NO_COLOR}"	
}

showrepostats(){
	local NBCOLMAX=4
	local nbcol=1
	echo -e "${COL_GREEN}$(gettext 'Number of configured repsitories:')  ${NO_COLOR}${COL_YELLOW}${#repositories[@]}"
	echo -e "${COL_GREEN}$(gettext 'Packages by repositories (ordered by pacman''s priority)')${NO_COLOR}:"
	local reponumber=0
	for repo in ${repositories[@]}; do
		[[ ${repos_packages[$reponumber]} ]] || repos_packages[$reponumber]=0
		echo -en "${NO_COLOR}${repo}${COL_YELLOW}(${repos_packages[$reponumber]})${NO_COLOR}, "
		(( reponumber++ ))
		(( nbcol++ ))
		(( nbcol % NBCOLMAX )) || echo
	done
	pacman -Sl | awk '{print $2"-"$3}' | LC_ALL=C sort | uniq > $tmp_files/abs
	pacman -Q | awk '{print $1"-"$2}' | LC_ALL=C sort > $tmp_files/installed
	echo -e " ${NO_COLOR}$(gettext 'others')* ${COL_YELLOW}($(LC_ALL=C comm -2 -3 $tmp_files/installed $tmp_files/abs|wc -l))${NO_COLOR}"
	echo
	echo -e "${NO_COLOR}"*$(gettext 'others')" $(gettext 'are packages not up to date or installed from local\nbuild or AUR Unsupported')${NO_COLOR}"
	echo -e "\n${COL_BLUE}-----------------------------------------------${NO_COLOR}"	
}

showdiskusage()
{
	local cachedir size inode countfile i s _msg_label _msg_prog
	# Get cachedir
	cachedir=(`LC_ALL=C pacman --debug 2>/dev/null | grep "^debug: option 'cachedir'" |awk '{print $5}'`)

	# Get space used by installed package (from info in alpm db)
	size=0
	i=1
	_msg_label=$(gettext 'Theorical space used by packages:')
	_msg_prog=$(gettext 'progression:')
	for s in $(package-query -Qf "%2"); do
		(( size+=s ))
		echo -ne "\r${COL_GREEN} $_msg_label ${COL_YELLOW}$(($size/1048576))Mo $_msg_prog $i/$pkgs_nb" >&2
		(( i++ ))
	done
	echo -e "\r${COL_GREEN}$_msg_label ${COL_YELLOW}$(($size/1048576))Mo                               "
	# Get real space used by package (after localpurge)
	cd /
	size=0
	i=1
	countfile=$(pacman -Qql | wc -l)
	_msg_label=$(gettext 'Real space used by packages:')
	inode=0
	for s in $(pacman -Qql | xargs stat -c "%i/%s" 2> /dev/null | sort -n ); do
		(( inode == ${s%/*} )) && s=0 || { inode=${s%/*};  s=${s#*/}; }
		(( size+=s ))
		echo -ne "\r${COL_GREEN}$_msg_label ${COL_YELLOW}$(($size/1048576))Mo $_msg_prog $i/$countfile" >&2
		(( i++ ))
	done
	echo
	echo -e "\r${COL_GREEN}$_msg_label ${COL_YELLOW}$(($size/1048576))Mo                               "
	# space used by download packages or sources in cache
	echo -e "${COL_GREEN}$(gettext 'Space used by pkg downloaded in cache (cachedir):') ${COL_YELLOW} $(du -skh $cachedir 2>/dev/null|awk '{print $1}')"
	[[ "$SRCDEST" ]] && srcdestsize=`du -skh $SRCDEST 2>/dev/null|awk '{print $1}'` || srcdestsize=null
	echo -e "${COL_GREEN}$(gettext 'Space used by src downloaded in cache:') ${COL_YELLOW} $srcdestsize"
}

