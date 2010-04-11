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
unset repos_packages orphans IgnorePkg IgnoreGroup HoldPkg
pkgs_nb=0 pkgs_nb_d=0 pkgs_nb_e=0 pkgs_nb_dt=0 pkgs_nb_u=0

buildpackagelist()
{
	list_repositories
	#construct the list of packages	
	local f_foreign=1 f_explicit=2 f_deps=4 f_unrequired=8 f_upgrades=16 f_group=32 
	IFS=$'\n'	
	for line in $(package-query -Qf "%4 %s %n"); do
		IFS=' '
		local data=($line)
		(( pkgs_nb++ ))
		(( ${data[0]} & f_deps )) && (( ++pkgs_nb_d )) && (( ${data[0]} & f_unrequired )) && {
			(( pkgs_nb_dt++ ))
			orphans+=(${data[2]})
		}
		(( ${data[0]} & f_explicit )) && (( pkgs_nb_e++ ))
		(( ${data[0]} & f_upgrades )) && (( pkgs_nb_u++ ))
		local reponumber=0
		for repo in ${repositories[@]}; do
			[[ "$repo" == "${data[1]}" ]] && (( ++repos_packages[$reponumber] )) && break
			(( reponumber++ ))
		done
	done
	unset IFS
	# Construction de la liste des paquets ignorés/noupgrade/holdpkg
	eval $(LC_ALL=C pacman --debug | sed -n 's/debug: config: \([a-zA-Z]\+\): \(.*\)/\1+=(\2)/p')
}

showpackagestats(){
	echo_fill "$COL_BLUE" - "$NO_COLOR"
	printf "${COL_BLUE}%${COLUMNS}s\r|${NO_COLOR}${COL_BOLD}%*s ${COL_GREEN}%s${NO_COLOR}\n" \
	  "|" $((COLUMNS/2)) "Archlinux " "($NAME $VERSION)"
	echo_fill "$COL_BLUE" - "$NO_COLOR"
	echo; echo_fill "$COL_BLUE" - "$NO_COLOR"
	echo -e "${COL_GREEN}$(gettext 'Total installed packages:')  ${COL_YELLOW}$pkgs_nb"	
	echo -e "${COL_GREEN}$(gettext 'Explicitly installed packages:')  ${NO_COLOR}${COL_YELLOW}$pkgs_nb_e"	
	echo -e "${COL_GREEN}$(gettext 'Packages installed as dependencies to run other packages:')  ${COL_YELLOW}$pkgs_nb_d"   
	echo -e "${COL_GREEN}$(gettext 'Packages out of date:')  ${COL_YELLOW}$pkgs_nb_u"   
	if (( pkgs_nb_dt )); then
		echo -e "${COL_RED}$(eval_gettext 'Where $pkgs_nb_dt packages seems no more used by any package:')${NO_COLOR}"
		str_wrap 4 "${orphans[*]}"
		echo -e "$strwrap"; echo
	fi
	echo -e "${COL_GREEN}$(gettext 'Hold packages:') (${#HoldPkg[@]}) ${NO_COLOR}${COL_YELLOW}${HoldPkg[@]}"
	echo -e "${COL_GREEN}$(gettext 'Ignored packages:') (${#IgnorePkg[@]}) ${NO_COLOR}${COL_YELLOW}${IgnorePkg[@]}"
	echo -e "${COL_GREEN}$(gettext 'Ignored groups:') (${#IgnoreGroup[@]}) ${NO_COLOR}${COL_YELLOW}${IgnoreGroup[@]}"
	echo; echo_fill "$COL_BLUE" - "$NO_COLOR"
}

showrepostats(){
	local NBCOLMAX=4
	local nbcol=1
	echo -e "${COL_GREEN}$(gettext 'Number of configured repositories:')  ${NO_COLOR}${COL_YELLOW}${#repositories[@]}"
	echo -e "${COL_GREEN}$(gettext 'Packages by repositories (ordered by pacman''s priority)')${NO_COLOR}:"
	local reponumber=0 pkgs_l=0
	for repo in ${repositories[@]}; do
		[[ ${repos_packages[$reponumber]} ]] || repos_packages[$reponumber]=0
		(( pkgs_l+=repos_packages[$reponumber] ))
		echo -en "${NO_COLOR}${repo}${COL_YELLOW}(${repos_packages[$reponumber]})${NO_COLOR}, "
		(( reponumber++ ))
		(( nbcol++ ))
		(( nbcol % NBCOLMAX )) || echo
	done
	echo -e " ${NO_COLOR}$(gettext 'others')*${COL_YELLOW}($((pkgs_nb-pkgs_l)))${NO_COLOR}"
	echo
	echo -e "${NO_COLOR}"*$(gettext 'others')" $(gettext 'are packages from local build or AUR Unsupported')${NO_COLOR}"
	echo; echo_fill "$COL_BLUE" - "$NO_COLOR"
}

showdiskusage()
{
	local cachedir size_t=0 size_r=0 i=1 _msg_label _msg_prog

	# Get space used by installed package (from info in alpm db)
	_msg_label=$(gettext 'Theorical - Real space used by packages:')
	_msg_prog=$(gettext 'progression:')
	package-query -Qf "%2 %3" | while read s_t s_r; do
		(( size_t+=s_t ))
		(( size_r+=s_r ))
		echo -ne "\r${COL_GREEN} $_msg_label ${COL_YELLOW}$(($size_t/1048576))M -  $(($size_r/1048576))M $_msg_prog $i/$pkgs_nb" >&2
		(( i++ ))
		if (( i > $pkgs_nb )); then
			echo -en "\r"; echo_fill "" " " ""
			echo -e "${COL_GREEN}$(gettext 'Theorical space used by packages:') ${COL_YELLOW}$(($size_t/1048576))M"
			echo -e "${COL_GREEN}$(gettext 'Real space used by packages:') ${COL_YELLOW}$(($size_r/1048576))M"
		fi
	done
	# Get cachedir
	cachedir=(`LC_ALL=C pacman --debug 2>/dev/null | grep "^debug: option 'cachedir'" |awk '{print $5}'`)
	# space used by download packages or sources in cache
	echo -e "${COL_GREEN}$(gettext 'Space used by pkg downloaded in cache (cachedir):') ${COL_YELLOW} $(du -sh $cachedir 2>/dev/null|awk '{print $1}')"
	[[ "$SRCDEST" ]] && srcdestsize=`du -sh $SRCDEST 2>/dev/null|awk '{print $1}'` || srcdestsize=null
	echo -e "${COL_GREEN}$(gettext 'Space used by src downloaded in cache:') ${COL_YELLOW} $srcdestsize"
}

