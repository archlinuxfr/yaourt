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
buildpackagelist()
{
	# get the repositories list in pacman.conf
	loadlibrary pacman_conf.sh
	list_repositories

	#construct the list of packages	
	#reason 1 : installed as a dependencies for another package
	#reason 0 or null: explicitly installed
	#requiredby 0: Required by none
	#requiredby 1: Required by some package
	for pkg in $(pacman -Q | awk '{print $1"-"$2}'); do
		# recherche des infos sur les paquetages installés
		# recherche du repository d'origine du paquet
		local reponumber=0
		for repo in ${repositories[@]}; do
			if [ -d "$PACMANROOT/sync/$repo/$pkg" ]; then
		       		repos_packages[$reponumber]=$((${repos_packages[$reponumber]}+1))
				found=1
				break
			fi
			reponumber=$(($reponumber+1))
		done
        done
	# Construction de la liste des paquets ignorés/noupgrade/holdpkg
	ignorepkg=(`LC_ALL="C" pacman --debug 2>/dev/null | grep "^debug: config: IgnorePkg:" |awk '{print $4}'|uniq`)
	holdpkg=(`LC_ALL="C" pacman --debug 2>/dev/null | grep "^debug: config: HoldPkg:" |awk '{print $4}'|uniq`)
	ignoregroup=(`LC_ALL="C" pacman --debug 2>/dev/null | grep "^debug: config: IgnoreGroup:" |awk '{print $4}'|uniq`)
}

showpackagestats(){
	echo -e "${COL_BLUE} -------------------------------------------${NO_COLOR}"	
	echo -e "${COL_BLUE}|$NO_COLOR    $(eval_gettext 'Archlinux Core Dump')   $COL_GREEN($NAME $VERSION)$COL_BLUE |${NO_COLOR}"	
	echo -e "${COL_BLUE} -------------------------------------------${NO_COLOR}\n"	
	echo -e "\n${COL_BLUE}-----------------------------------------------${NO_COLOR}"	
	echo -e "${COL_GREEN}$(eval_gettext 'Total installed packages:')  ${COL_YELLOW}`pacman -Q | wc -l`"	
	echo -e "${COL_GREEN}$(eval_gettext 'Explicitly installed packages:')  ${NO_COLOR}${COL_YELLOW}`pacman -Qe | wc -l`"	
	echo -e "${COL_GREEN}$(eval_gettext 'Packages installed as dependencies to run other packages:')  ${COL_YELLOW}`pacman -Qd | wc -l`"   
	local orphans=(`pacman -Qdt | awk '{print $1}' | sort`)
	if [  ${#orphans[@]} -gt 0 ]; then 
		_orphans=${#orphans[@]}
		echo -e "${COL_RED}$(eval_gettext 'Where $_orphans packages seems no more used by any package:')${NO_COLOR}"
		echo -e "$NO_COLOR${orphans[*]}$NO_COLOR"
	else
		echo -e "${COL_GREEN}$(eval_gettext 'Packages installed as dependencies but no more required:')  ${COL_YELLOW}0"  
	fi
	echo -e "${COL_GREEN}$(eval_gettext 'Number of HoldPkg:')  ${NO_COLOR}${COL_YELLOW}${#holdpkg[@]}"
	echo -e "${COL_GREEN}$(eval_gettext 'Number of IgnorePkg:')  ${NO_COLOR}${COL_YELLOW}${#ignorepkg[@]}"
	echo -e "${COL_GREEN}$(eval_gettext 'Group ignored:')  ${NO_COLOR}${COL_YELLOW}${ignoregroup[*]}"
	echo -e "\n${COL_BLUE}-----------------------------------------------${NO_COLOR}"	
}

showrepostats(){
	local NBCOLMAX=4
	local nbcol=1
	echo -e "${COL_GREEN}$(eval_gettext 'Number of configured repsitories:')  ${NO_COLOR}${COL_YELLOW}${#repositories[@]}"
	echo -e "${COL_GREEN}$(eval_gettext 'Packages by repositories (ordered by pacman''s priority)')${NO_COLOR}:"
	local reponumber=0
	for repo in ${repositories[@]}; do
		if [ -z "${repos_packages[$reponumber]}" ]; then repos_packages[$reponumber]=0;fi
		echo -en "${NO_COLOR}${repo}${COL_YELLOW}(${repos_packages[$reponumber]})${NO_COLOR}, "
		reponumber=$(($reponumber+1))
		nbcol=$(($nbcol+1))
		if [ $nbcol -gt $NBCOLMAX ] ; then echo;nbcol=1;fi
	done
	pacman -Sl | awk '{print $2"-"$3}' | sort | uniq > $tmp_files/abs
        pacman -Q | awk '{print $1"-"$2}' | sort > $tmp_files/installed
	echo -e " ${NO_COLOR}$(eval_gettext 'others')* ${COL_YELLOW}($(comm -2 -3 $tmp_files/installed $tmp_files/abs|wc -l))${NO_COLOR}"
	echo
	echo -e "${NO_COLOR}"*$(eval_gettext 'others')" $(eval_gettext 'are packages not up to date or installed from local\nbuild or AUR Unsupported')${NO_COLOR}"
	echo -e "\n${COL_BLUE}-----------------------------------------------${NO_COLOR}"	
}

showdiskusage()
{

	# Get SRCDEST
	source /etc/makepkg.conf

	# Get cachedir
	local cachedir=(`LC_ALL=C pacman --debug 2>/dev/null | grep "^debug: option 'cachedir'" |awk '{print $5}'`)

	# Get space used by installed package (from info in alpm db)
	size=0
	i=1
	countpkg=$(ls $PACMANROOT/local | wc -l)
	for pkg in $PACMANROOT/local/*; do
		sizeb=`grep -A1 %SIZE% $pkg/desc | tail -n1`
		if [ -z $sizeb ]; then sizeb=0; fi
		size=$(($size+$sizeb))
		echo -ne "\r${COL_GREEN} $(eval_gettext 'Theorical space used by packages:') ${COL_YELLOW}$(($size/1048576))Mo $(eval_gettext 'progression:') $i/$countpkg\r" >&2
		i=$(($i+1))
	done
	echo -e "${COL_GREEN}$(eval_gettext 'Theorical space used by installed packages:') ${COL_YELLOW}$(($size/1048576))Mo                               "

	# Get real space used by package (after localpurge)
	cd /
	size=0
	i=1
	countpkg=$(ls $PACMANROOT/local | wc -l)
	for pkg in $PACMANROOT/local/*; do
		sizeb=$(grep "/" $pkg/files | grep -v "/$" | xargs --no-run-if-empty du -bc 2>/dev/null | awk '{print $1}'|tail -n 1)
		if [ -z $sizeb ]; then sizeb=0; fi
		size=$(($size+$sizeb))
		echo -ne "\r${COL_GREEN} $(eval_gettext 'Real space used by packages:') ${COL_YELLOW}$(($size/1048576))Mo $(eval_gettext 'progression:') $i/$countpkg\r" >&2
		i=$(($i+1))
	done
	echo -e "${COL_GREEN}$(eval_gettext 'Real space used by installed packages:') ${COL_YELLOW}$(($size/1048576))Mo                               "
	# space used by download packages or sources in cache
	echo -e "${COL_GREEN}$(eval_gettext 'Space used by pkg downloaded in cache (cachedir):') ${COL_YELLOW} $(du -skh $cachedir 2>/dev/null|awk '{print $1}')"
	if [ -z "$SRCDEST" ]; then
		srcdestsize="null"
	else
		srcdestsize=`du -skh $SRCDEST 2>/dev/null|awk '{print $1}'`
	fi
	echo -e "${COL_GREEN}$(eval_gettext 'Space used by src downloaded in cache:') ${COL_YELLOW} $srcdestsize"
}

