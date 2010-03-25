#!/bin/bash
# Julien MISCHKOWITZ <wain@archlinux.fr>
# Ce programme permet de rechercher les fichiers pacsave et pacnew, de supprimer les fichiers inutiles et d'éditer les différences entre les fichiers.
export TEXTDOMAINDIR=/usr/share/locale
export TEXTDOMAIN=yaourt
type gettext.sh > /dev/null 2>&1 && { . gettext.sh; } || eval_gettext () { echo "$1"; }
if [ `type -p colordiff` ]; then
       	showdiff="colordiff"
else
	showdiff="diff"
fi
DIFFOPTS="--text --ignore-space-change --ignore-blank-lines -u"

program_version=0.3.6
DEBUG=1
dbg(){
	! [ $DEBUG ] && return
	echo -e "$*" >> $YAOURTTMPDIR/pacdiffviewer.log
}

merge_files(){
	msg $(eval_gettext '$systemfile: difference between $originalversionprevious and $originalversioncurrent')
	eval $showdiff $DIFFOPTS $savedir/$pkgname/$originalversionprevious$systemfile \
	$savedir/$pkgname/$originalversioncurrent$systemfile
	msg $(eval_gettext 'Do you really want to apply the above patch ?') $(yes_no 1)
	msg "----------------------------------------------"
	promptlight
	[[ "`userinput`" = "N" ]] && return 0
	
       	diff $DIFFOPTS $savedir/$pkgname/$originalversionprevious$systemfile \
	$savedir/$pkgname/$originalversioncurrent$systemfile | patch --dry-run -sp0 "$systemfile" >/dev/null
	if [ $? -eq 0 ]; then
		msg $(eval_gettext 'Applying patch')
       		diff $DIFFOPTS $savedir/$pkgname/$originalversionprevious$systemfile \
		$savedir/$pkgname/$originalversioncurrent$systemfile | patch -sp0 "$systemfile"
		if [ $? -ne 0 ]; then
			error "$(eval_gettext 'Patch not applied correctly')"
		else
			msg "$(eval_gettext 'File patched ok')"
		fi
	else
		warning "$(eval_gettext 'This patch can not be applied automatically')"
		patchsaved="$YAOURTTMPDIR/`basename $systemfile`.diff"
		diff $DIFFOPTS $savedir/$pkgname/$originalversionprevious$systemfile \
	$savedir/$pkgname/$originalversioncurrent$systemfile > $patchsaved
		msg "$(eval_gettext 'Saving patch in $patchsaved')"
	fi
	list "$(eval_gettext 'Press a key to continue')"
	read
}


#           COMPARER LES VERSIONS ET TROUVER CE QUI EST MERGEABLE
# Pour chaque fichier .pacnew, vérifier qu'on ait la bonne version en sauvegarde
# Pour chaque fichier .pacnew correct, regarder si la version du package installé correspond
# Pour chaque fichier .pacnew correct chercher la version précédente de la sauvegarde
# , regarder si la version du package installé correspond
is_mergeable(){
	systemcurrentfile=$1
	currentversion=`LC_ALL=C pacman -Qo $systemcurrentfile | awk '{print $5"-"$6}'`
	pkgname=`echo $currentversion | sed 's/-[^-]*-[^-]*$//'`
	currentversionfile="$savedir/$pkgname/${currentversion}${systemcurrentfile}"
	unset previousversion
	dbg $(eval_gettext 'Searching in backupfiles for $systemcurrentfile original files for possible merge')
	if [ ! -f "$currentversionfile" ]; then
		dbg $(eval_gettext 'Current version not found ($currentversion). Unable to merge')
		return 1
	fi
	dbg $(eval_gettext 'Searching for previous version of $systemcurrentfile ($currentversion) for possible merge')
	for candidate in `ls "$savedir/$pkgname" | grep -v "$currentversion"`; do
		[ ! -f "$savedir/$pkgname/$candidate${systemcurrentfile}" ] && continue
		#if `is_x_gt_y $currentversion $version`; then
		#	echo "1 current:$currentversion > version:$version"
		#else
		#	echo "1 current:$currentversion < version:$version"
		#	continue
		#fi
		if [ -z "$previousversion" ]; then
			dbg "control1 ($systemcurrentfile): is_x_gt_y ${currentversion#$pkgname-} ${candidate#$pkgname-}"
			if `is_x_gt_y ${currentversion#$pkgname-} ${candidate#$pkgname}`; then
				previousversion=$candidate
				dbg $(eval_gettext 'canditate found: $candidate')
			fi
			continue
		fi
			dbg "control2 ($systemcurrentfile): is_x_gt_y ${candidate#$pkgname-} ${previousversion#$pkgname-}"
		if `is_x_gt_y ${candidate#$pkgname-} ${previousversion#$pkgname-}`; then
			dbg "control3 ($systemcurrentfile): is_x_gt_y ${currentversion#$pkgname-} ${candidate#$pkgname-}"
			if `is_x_gt_y ${currentversion#$pkgname-} ${candidate#$pkgname-}`; then
				dbg $(eval_gettext 'best canditate than $previousversion found: candidate:$candidate > $previousversion')
				previousversion=$candidate
			fi
		else
			dbg $(eval_gettext 'debug: not better: candidate:$candidate < $previousversion')
			continue
		fi
	done
	if [ ! -z "$previousversion" ] && ! diff $DIFFOPTS $savedir/$pkgname/$previousversion$systemcurrentfile\
	      	$savedir/$pkgname/$currentversion$systemcurrentfile >/dev/null; then
		dbg $(eval_gettext 'Version $previousversion before $currentversion')
		dbg "systemcurrentfile=$systemcurrentfile pkgname=$pkgname currentversion=$currentversion previousversion=$previousversion"
			echo "$systemcurrentfile $pkgname $currentversion $previousversion" >> $tmp_files/mergeable_files
		return 0
	else
		dbg $(eval_gettext 'Version before $currentversion not found')
		return 1
	fi
}

# Save files marked as backup in packages for later merge
##########################################################
backupfiles(){
##########################################################
	need_root
	local packagelist=`grep -srl --line-regexp --include="files" '%BACKUP%' "$PACMANROOT/local"`
	for file in ${packagelist[@]};do
		package=`echo $file | awk -F "/" '{print $(NF-1)}' `
		pkgname=`echo $package | sed 's/-[^-]*-[^-]*$//'`
		cat $file | sed -e '1,/%BACKUP%/d' -e '/^$/d'| while read line; do
			backupfilepath=`echo $line | awk '{print $1}'`
			if [ ! -f "$savedir/$pkgname/$package/$backupfilepath" ]; then
				backupfiledir=`dirname $backupfilepath`
				#backupfilename=`basename $backupfilepath`
				backupfilemd5=`echo $line | awk '{print $2}'`
				for currentfile in "/$backupfilepath" "/$backupfilepath.pacnew"; do
					#echo "     recherche $currentfile"
					[ ! -f "$currentfile" ] && continue
					#echo "        calcul md5 $currentfile"
					pacnewfilemd5=`md5sum "$currentfile" | awk '{print $1}'`
					if [ "$pacnewfilemd5" = "$backupfilemd5" ]; then
						#echo "-*- creation du dossier $savedir/$package/$backupfiledir"
						mkdir -p "$savedir/$pkgname/$package/$backupfiledir"
						echo "  -> $(eval_gettext 'saving $currentfile')"
						cp -a "$currentfile" "$savedir/$pkgname/$package/$backupfilepath" || return 1
						break
					fi
		       		done
			fi
		done
	done
	exit
}


##########################################################
SUPPRESS_ORPHANS()
##########################################################
{
# Affichage et suppression des fichiers orphelins
list "-------------------------------------------------------"
plain $(eval_gettext '        Following files are orphans:')
plain $(eval_gettext '    (Packages are no longer installed)')
list "-------------------------------------------------------"
sleep 1
list "$(cat $tmp_files/pacfile.obsolete)"
msg $(eval_gettext 'Do you want to remove these obsolete files ?')
msg "$(eval_gettext ' (to be confirmed for each file) : ') $(yes_no 2)"
msg "----------------------------------------------"
promptlight
suppress=$(userinput)
echo
if [ "$suppress" = "Y" ]; then
	for file in `cat $tmp_files/pacfile.obsolete`; do
		if [ -w "$file" ]; then
			echo -n "$(eval_gettext '=> Delete file $file ? ') $(yes_no 2) -> "
			if [ "`userinput`" = "Y" ]; then rm "$file"; fi
		else
			error $(eval_gettext '${file}: You don''t have write access')
		fi
	done
fi
}

##########################################################
SEARCH_ORPHANS()
##########################################################
{
# Rechercher les fichiers pacsave/pacnew orphelins
rm $tmp_files/$extension.tmp
cat < $tmp_files/$extension | while true
do
	read ligne
  	if [ "$ligne" = "" ]; then break; fi
	file=`echo $ligne | cut -d " " -f 5`
	if ! [ -f $file ]
	then
		echo $file.$extension >> $tmp_files/pacfile.obsolete
	else
		echo $ligne >> $tmp_files/$extension.tmp
	fi
done 
[ -f "$tmp_files/$extension.tmp" ] && cp $tmp_files/$extension.tmp $tmp_files/$extension
}

##########################################################
CREATE_DB()
##########################################################
{
# Création de la liste des fichiers .pacsave et .pacnew
rm -rf $tmp_files/
#msg "Please wait..."
mkdir -p $tmp_files
find /boot/ /etc/ /opt/ /usr/share/ /usr/lib/ \( -name "*.pacsave" -o -name "*.pacnew" \) > $tmp_files/pacbase 

#Recherche des fichiers pacsave/pacnew
for extension in "pacsave" "pacnew"; do
	SEARCH_FOR_PACFILES
done
}

##########################################################
SEARCH_FOR_PACFILES()
##########################################################
{
# Recherche des fichiers pacsave/pacnew + tri des résultats par date
for file in `grep ".$extension" $tmp_files/pacbase`; do
	echo `date +%s -r $file` $(eval_gettext "The ")`date +%m/%d/%Y"$(eval_gettext ' at ')"%T -r $file`": "$file>>$tmp_files/$extension.tmp
done
if [ -f $tmp_files/$extension.tmp ]; then
	sort -r "$tmp_files/$extension.tmp" | cut -d " " -f 2-6 | sed -e s/.$extension//g>$tmp_files/$extension
	nbresultats=`wc -l $tmp_files/$extension.tmp | cut -d " " -f 1`
	if [ "$extension" = "pacsave" ]; then pacsave_num=$nbresultats; fi
	if [ "$extension" = "pacnew" ]; then pacnew_num=$nbresultats; fi
	plain $(eval_gettext '$nbresultats .$extension files found')
	SEARCH_ORPHANS
else
	nbresultats=0
fi
}

##########################################################
VIEW_DIFF_LIST()
##########################################################
{
# A partir des fichiers pacsave/pacnew trouvés, cherche les fichiers identiques
# affiche les fichiers avec un numéro, et mémorise ces index dans le tableau file[]

# Recherche des fichiers .pacsave/.pacnew non modifiés
num=0
while read line; do
	num=$(($num+1))
	fichier[$num]=$line
done < $tmp_files/$extension

echo $(eval_gettext 'File to merge             Current Version      Previous Version') > $tmp_files/meargeable_files

for i in `seq 1 $num`; do
	file[$i]=$(echo ${fichier[$i]} | cut -d " " -f 5)
	show_file_line="$i. ${fichier[$i]}[.$extension]"
	#previous_version_for_merge[$i]=`mergeable_with ${file[$i]}`
	if diff $DIFFOPTS ${file[$i]} ${file[$i]}.$extension > /dev/null; then
		show_file_line="$show_file_line $(eval_gettext '**same files**')"
	elif [ "$extension" = "pacnew" ] && `is_mergeable ${file[$i]}`; then
		#if [ ! -w ${file[$i]} ]; then show_file_line=$(echo $show_file_line" (readonly)"); fi
		show_file_line="$show_file_line $COL_RED$COL_BLINK$(eval_gettext '**automerge is possible**')"
	fi
	list "$show_file_line"
done 
}

##########################################################
DIFFEDITOR()
##########################################################
{
clear
_file=${file[$numero]}
msg  $(eval_gettext 'What do you want to do with $_file[.$extension] ?')
plain $(eval_gettext '  1: Show diffs with gvim in expert mode')
plain $(eval_gettext '  2: Show diffs with vimdiff (in console)')
plain $(eval_gettext '  3: Show diffs with kompare')
plain $(eval_gettext '  4: Show diffs with kdiff3')
plain $(eval_gettext '  5: gvim in EASY mode')
plain $(eval_gettext '  6: Enter a command to edit')
plain $(eval_gettext '  S: suppress .$extension file')
plain $(eval_gettext '  R: replace actual file by .$extension')
if [ -f "$tmp_files/mergeable_files" ]; then
	line=`grep "$_file" $tmp_files/mergeable_files`
	if [ ! -z "$line" ]; then 
		systemfile=`echo $line | awk '{print $1}'`
		pkgname=`echo $line | awk '{print $2}'`
		originalversioncurrent=`echo $line | awk '{print $3}'`
		originalversionprevious=`echo $line | awk '{print $4}'`
		mergeable=1 
		plain "  ${COL_BLINK}$(eval_gettext 'A: Automatically merge with .$extension (use a diff between $originalversioncurrent and $originalversionprevious)')"
	else
		mergeable=0 
	fi
fi
msg $(eval_gettext ' Press ENTER to return to menu')
msg "----------------------------------------------"
promptlight
action=$(userinput "ASR")
echo
case "$action" in
	"A") 
	# Auto merge
	if [ "$mergeable" -eq 1 ]; then
       		merge_files
	fi
	DIFFEDITOR;;
	"1" )
	# Voir les différences avec GVIM
	gvim -d ${file[numero]} ${file[numero]}.$extension
	DIFFEDITOR
	;;
	
	"2" )
	# Voir les différences avec VIMDIFF
	vim -d ${file[numero]} ${file[numero]}.$extension
	DIFFEDITOR
	;;
	
	"3" )
	# Voir les différences avec KOMPARE
	kompare -c ${file[numero]} ${file[numero]}.$extension >/dev/null
	DIFFEDITOR
	;;

	"4" )
	# Voir les différences avec KDIFF3
	kdiff3 ${file[numero]} ${file[numero]}.$extension >/dev/null

	DIFFEDITOR
	;;
	
	"5" )
	# Voir les différences avec GVIM
	gvim -dy ${file[numero]} ${file[numero]}.$extension
	DIFFEDITOR
	;;
	
	"6" )
	# Voir les différences avec une commande donnée
	echo
	echo
	msg $(eval_gettext ' Enter the name of the program to use')
  	echo "    ($(eval_gettext 'without') ${file[numero]} ${file[numero]}.$extension)"
	msg "----------------------------------------------"
	promptlight
	read commanddiffview
	( $commanddiffview ${file[numero]} ${file[numero]}.$extension )
	wait
	DIFFEDITOR
	;;


	"S" )
	# Supprimer le fichier .pacsave ou .pacnew
	rm -i ${file[numero]}.$extension
	extension_old=$extension
	CREATE_DB
	extension=$extension_old
	;;
	
	"R" )
	# Remplacer le fichier actuel par le fichier .pacsave ou .pacnew
	cp ${file[numero]}.$extension ${file[numero]}
	_file=${file[numero]}
	msg $(eval_gettext '$_file file has been replaced')
	rm -i ${file[numero]}.$extension
	extension_old=$extension
	CREATE_DB
	extension=$extension_old
	;;
esac
}


##########################################################
SHOWHELP()
##########################################################
{
echo "pacdiffviewer $program_version"
echo "ecrit par wain <wain@archlinux.fr>"
echo ""
echo $(eval_gettext 'usage:')
echo "         pacdiffviewer -c, clean:    $(eval_gettext 'Delete all pacsave, pacnew found')"
echo "         pacdiffviewer -h, help:     $(eval_gettext 'Show this help')"
echo "         pacdiffviewer -v, version:  $(eval_gettext 'Show version number')"
echo ""
echo "--------------------------------------------------------"


echo $(eval_gettext 'HANDLING CONFIG FILES')
echo $(eval_gettext 'pacman uses the same logic as rpm to determine action against files that are designated to be backed up.')
echo $(eval_gettext 'During an upgrade, it uses 3 md5 hashes for each backup file to determine the required action: one for the original file installed, one for the new file that''s about to be installed, and one for the actual file existing on the filesystem.')
echo $(eval_gettext 'After comparing these 3 hashes, the follow scenarios can result:')
echo $(eval_gettext 'original=X, current=X, new=X: All three files are the same, so we win either way. Install the new file.')
echo $(eval_gettext 'original=X, current=X, new=Y: The current file is un-altered from the original but the new one is different. Since the user did not ever modify the file, and the new one may contain improvements/bugfixes, we install the new file.')
echo $(eval_gettext 'original=X, current=Y, new=X: Both package versions contain the exact same file, but the one on the filesystem has been modified since. In this case, we leave the current file in place.')
echo $(eval_gettext 'original=X, current=Y, new=Y: The new one is identical to the current one. Win win. Install the new file.')
echo $(eval_gettext 'original=X, current=Y, new=Z: All three files are different, so we install the new file with a .pacnew extension and warn the user, so she can manually move the file into place after making any necessary customizations.')
echo "--------------------------------------------------------"
echo "http://wiki.archlinux.fr/doku.php?id=howto:archlinux:gerer_pacsave_pacnew"
exit 0
}


##########################################################
SHOWVERSION()
##########################################################
{
echo "pacdiffviewer $program_version"
echo "$(eval_gettext 'Author:') Julien MISCHKOWITZ <wain@archlinux.fr>"
exit 0
}

##########################################################
SUPPRESSAUTO()
##########################################################
{
echo
msg $(eval_gettext 'Do you want to delete following files ?')
for file in `cat $tmp_files/pacbase`; do
	list $file "($(eval_gettext 'created ')"`date +%m/%d/%Y"$(eval_gettext ' at ')"%T -r $file`")"
done
msg $(eval_gettext 'Yes (to be confirmed for each file), All, No')
msg "----------------------------------------------"
promptlight
action=$(userinput "YAN")
echo
case "$action" in

	"Y" )
	# oui/yes demande confirmation
	msg $(eval_gettext 'deleting files one bye one')
	for file in `cat $tmp_files/pacbase`;
	do
		rm -i $file
	done
	;;
	
	"A" )
	# tous/all supprime tout sans confirmation
	msg $(eval_gettext 'Deleting all files')
	for file in `cat $tmp_files/pacbase`;
	do
		rm $file
	done
	;;

	*)
	msg $(eval_gettext 'Cancelled')
	;;
esac

rm -rf $tmp_files/
exit 0
}

need_root(){
if [ "$UID" -ne "0" ]; then
	echo $(eval_gettext 'Requires root user')
	echo
	echo $(eval_gettext 'Login root:')
	echo "   # su"
	echo $(eval_gettext '   # <root password>')
	echo
	echo $(eval_gettext 'Or add this line to sudoers:')
	echo "`id -un` ALL=NOPASSWD: /usr/bin/pacdiffviewer"
	exit
fi
}


########################################################################
###              MAIN PROGRAM                                        ###
########################################################################
savedir=/var/lib/yaourt/backupfiles

# Basic init and libs in common with yaourt
source /usr/lib/yaourt/basicfunctions.sh || exit 1 
initpath
initcolor
tmp_files="$YAOURTTMPDIR/pacdiffviewer.$$"



case $1 in
  -h|--help) SHOWHELP;;
  -v|--version) SHOWVERSION;;
  --backup) backupfiles;;
esac

# Initialisation de la liste des fichiers pacsave/pacnew
need_root
dbg `date +%D" "%Hh%Mm%Ss`
CREATE_DB

# Affichage des résultats de la recherche et sortie si pas de résultats
if [[ "$pacsave_num" -eq "0" && "$pacnew_num" -eq "0" ]]; then
	msg $(eval_gettext 'no file found.')
	rm -rf $tmp_files/
	exit 0
fi
sleep 1

# Mode suppression automatique et sortie
if [ "$1" = "-c" ]; then SUPPRESSAUTO; fi

# Suppression des fichiers orphelins si nécessaires 
if [ -f "$tmp_files/pacfile.obsolete" ]; then SUPPRESS_ORPHANS; fi

# Recherche des différences sur les pacsave
if [[ "$pacsave_num" -gt "0" ]]
then
	clear
	modif="o"
	extension="pacsave"
	while true; do
		if [ ! -f $tmp_files/pacsave ]; then break; fi
		clear
		list "--------------------------------------------"
		plain $(eval_gettext '              .pacsave files')
		list "--------------------------------------------"
		plain $(eval_gettext 'Maybe you have changed these files, but they have been')
		plain $(eval_gettext 'replaced during packages update:')
		VIEW_DIFF_LIST
		msg $(eval_gettext 'Enter the number of the file to be modified or press ENTER to cancel')
		msg "----------------------------------------------"
		promptlight
		read numero
		if [ -z $numero ]; then break; fi
		DIFFEDITOR
	done
fi

# Recherche des différences sur les pacnew
if [[ "$pacnew_num" -gt "0" ]]
then
	clear
	modif="o"
	extension="pacnew"
	while true; do
		if [ ! -f $tmp_files/pacnew ]; then break; fi
		clear
		list "--------------------------------------------"
		plain $(eval_gettext '               .pacnew files')
		list "--------------------------------------------"
		plain $(eval_gettext 'New version of these files are available')
		plain $(eval_gettext 'These .pacnew files may contain enhancements')
		VIEW_DIFF_LIST
		msg $(eval_gettext 'Enter the number of the file to be modified or press ENTER to cancel')
		msg "----------------------------------------------"
		promptlight
		read numero
		if [ -z $numero ]; then break; fi
		DIFFEDITOR
	done
fi

# Fin du programme
rm -rf $tmp_files/
exit 0
