#!/bin/sh
POSIXLY_CORRECT=yes

# Shows possible inputs
help(){
	echo
	echo "-h - for help"
	echo "-g - to set group, either to edit or list"
	echo "-m - opens the most frequently opened file"
	echo "Examples:"
	echo 'mole -h'
	echo 'mole [-g GROUP] FILE' - to see last edited
	echo 'mole [-m] [FILTERS] [DIRECTORY]' - to see most edited
	echo 'mole list [FILTERS] [DIRECTORY]'
	echo
}

if [ "$1" = "-h" ];
then
	help
	exit 0
fi


# Choose the correct editor according to set variables.
# If neither is set, the default editor vi will be run.
# $1 - Name of file to be opened in the select editor

set_editor(){
	if [ "$EDITOR" ];
	then
		if [ "$(command -v "$EDITOR")" ];
		then
			LOCAL_EDITOR=$EDITOR
		fi

	else
			LOCAL_EDITOR=${VISUAL:-vi}
	fi
} 
set_editor

check_date(){
if [ "$(uname)" = "FreeBSD" ]; 
then
	if ! gdate "+%Y-%m-%d" -d "$1" > /dev/null 2>&1; then
		echo "Invalid date set." >&2
		exit 1
	fi		
else
	if ! date "+%Y-%m-%d" -d "$1" > /dev/null 2>&1; then
		echo "Invalid date set." >&2
		exit 1
	fi
fi
}

# Saves information about the current file editation into the file specified by $MOLE_RC 
# save_edit_info $file $group
save_edit_info(){
	if [ "$(uname)" = "Linux" ] 
        then	
			now=$(date +'%Y-%m-%d %H-%M-%S')
        else
        	now=$(gdate +'%Y-%m-%d %H-%M-%S')
	fi

	path=$(realpath "$1" )

	#if we open a file without any group, we check if it was logged before, and if no, we create log "group [filename]: [name_of_the_group]"
	if [ "$#" = "1" ]; then
		if ! grep "$path" "$MOLE_RC" > /dev/null; then
			echo "group ${path}:" >> "$MOLE_RC"
		fi
	# two args
	else
		if grep "$path" "$MOLE_RC" > /dev/null; then
			#checks if file already logged, and if it is, then append to the end of line that has groups (finds line number where this file in MOLE_RC is)
			num=$(grep -n "group ${path}:" "$MOLE_RC" | cut -d":" -f1)

			#check if this group already exists
			if ! sed -n "${num}p" "$MOLE_RC" | grep -q " ${2}"
			then
				echo not exist yet
				sed -i "${num}s/$/ ${2}/" "$MOLE_RC"
			fi
		else
			#if file was not logged yet	
			echo "group ${path}: $2" >> "$MOLE_RC"     #check if exist and then just append time and group if available and check if is group
		fi
	fi

	#log time in any case
	echo "$path $now" >> "$MOLE_RC"
}



# Checks if the command realpath is available, if not, the script ends. 
if [ -z "$(command -v realpath)" ];
then
	echo "Command \'realpath\' not available." >&2
	exit 1
fi

# Checks if the $MOLE_RC variable is set, if not, the script ends.
if [ -z "$MOLE_RC" ];
then
	echo "MOLE_RC variable not set." >&2
	exit 1
fi

# Checks if the molerc file set in MOLE_RC variable exists, if not, creates it and its path.
if [ ! -f "$MOLE_RC" ];
then
	echo "The $MOLE_RC file was not found. Creating it now."
	mkdir -p "$(dirname "$MOLE_RC")"
	touch "$MOLE_RC"
fi

# list is not a flag because does not start from hyphen, so we remember it, but shift. getopts doesn't work this way
if [ "$1" = "list" ]; then
	list=1
	shift 1
fi

if [ "$1" = "secret-log" ]; then
	secret_log=1
	shift 1
fi

#opens (or creates and open) explicitly entered file (with group if -g is passed) and log this opening
#doesn't do lookup in MOLE_RC file, just write to it
if [ "$#" = "1" ] && [ ! -d "$1" ];
then
	if [ "$1" != "-a" ] && [ "$1" != "-b" ] && [ "$1" != "-m" ] && [ "$list" != "1" ] && [ "$1" != "-g" ] && [ "$1" != "secret-log" ]; then
  		$LOCAL_EDITOR "$1"
  		save_edit_info "$1"
		exit 0
	fi
elif [ "$#" = "3" ] && [ "$1" = "-g" ] && [ ! -d "$3" ];
then
	if [ "$2" != "-a" ] && [ "$2" != "-b" ] && [ "$2" != "-m" ] && [ "1" != "$list" ] && [ "$2" != "-g" ]; then    #should be check for $2 and $3 (same) ######$2=list redundand
		$LOCAL_EDITOR "$3"
  		save_edit_info "$3" "$2"
		exit 0
	else
  		echo "Invalid argument"
		exit 1
  	fi
fi

#set directory to search and checking if last argument is folder
for last; do true; done
if [ -d "$last" ];
then
	dir_set=1
	DIR=$last
elif [ "$last" = "-a" ] || [ "$last" = "-b" ] || [ "$last" = "-g" ]; then
	echo "Flag is not set but declared"
	exit 1
else
	DIR=./
fi

#Setting default values that in any case works correctly
start_date=1000-01-01 # by default set very old date in order to use it in any case.
end_date=2500-01-01 # by default set far away date in order to use it in any case.
g=""

# Read all filter flags
while getopts ":g:a:b:" o; do
    case "${o}" in
        g)
			g=${OPTARG}
            ;;
        a)
			start_date=${OPTARG}
			check_date "$start_date"
            ;;
        b)
			end_date=${OPTARG}
			check_date "$end_date"
			;;
		*)	
            ;;
    esac
done

# convert to numbers to check if dates are correct
numeric_start_date=$(echo "$start_date" | sed "s/-//g")
numeric_end_date=$(echo "$end_date" | sed "s/-//g")

if [ $numeric_end_date -lt $numeric_start_date ]; then
	echo "End date can not be older than start date"
	exit 1
fi

##### APPLYING GROUP AND DATE FILTERS TO MOLE_RC FILE
setdate=$(echo "$start_date" | sed "s/-//g")
setpath=$(realpath "$DIR")
from_this_line=$(grep "^$setpath/[^/]*$" "$MOLE_RC" | sort -k2 -k3 | awk '{print $2}' | sed "s/-//g" | awk -v setdate="$setdate" '{if ($1 >= setdate) {print NR; exit} }' )

#if no files in here
if [ -z "$from_this_line" ]; then
	echo "No files for that period"
	exit 1
fi

setdate=$(echo "$end_date" | sed "s/-//g")
to_this_line=$(grep "^$setpath/[^/]*$" "$MOLE_RC" | sort -k2 -k3 | awk '{print $2}' | sed "s/-//g" | awk -v setdate="$setdate" '{if ($1 > setdate) {print NR; exit} }' )

if [ "$to_this_line" != "0" ] && [ ! -z "$to_this_line" ] ; then
	to_this_line=$((to_this_line-1)) #because we need to check excuding that line
fi

 if [ "$to_this_line" = "0" ]; then
	echo "No files for that period"
	exit 1
fi

if [ "$end_date" = 2500-01-01 ] || [ -z $to_this_line ]; then
	to_this_line=999999999
fi

if [ $from_this_line -gt $to_this_line ]; then
	echo "Bad period"
	exit 1
fi

#selects only files related to selected groups
while read line; do
		if [ -z "$g" ]; then
			this_file_from_group=$(echo "$line" | grep "^group " | awk '{print $2}' | sed 's/.$//')     #CHECK ALL GROUPS
			all_files_from_group="${all_files_from_group} ${this_file_from_group}"
		else
			#loop to go through all groups
			if echo "$g" | grep "," > /dev/null															 #CHECK MULTIPLE GROUPS SEPARATED BY COMMA
			then
				group_remove_coma=$(echo "$g" | tr ',' ' ')
				#echo group_remove_coma $group_remove_coma

				for individual_group in $group_remove_coma; do
					if_first_file_from_group=$(echo "$line" | grep "^group " | grep " ${individual_group} " | awk '{print $2}' | sed 's/.$//') #if first in raw
					if_last_file_from_group=$(echo "$line" | grep "^group " | grep " ${individual_group}$" | awk '{print $2}' | sed 's/.$//') #if last in raw
					all_files_from_group="${all_files_from_group} ${if_first_file_from_group}${if_last_file_from_group}"
				done
			else																						 #CHECK ONLY ONE GROUP
				group_remove_coma=$g
				#echo  READ GROUPS
				if_first_file_from_one_group=$(echo "$line" | grep "^group" | grep " ${g} " | awk '{print $2}' | sed 's/.$//') #if first in raw
				if_last_file_from_one_group=$(echo "$line" | grep "^group" | grep " ${g}$" | awk '{print $2}' | sed 's/.$//') #if last in raw
				all_files_from_group="${all_files_from_group} ${if_first_file_from_one_group}${if_last_file_from_one_group}"
			fi
		fi
done < "$MOLE_RC"

#check if there are any files with such name of a group
all_files_from_group_str=$(echo "$all_files_from_group" | sed 's/ //g')
if [ -z "$all_files_from_group_str" ]; then
	echo "There are no files belonging to those group"
	exit 1
fi

# Getting quantity of lines to be checked after date filter is applied
nums_selected=$(grep "^$setpath/[^/]*$" "$MOLE_RC" | sort -k2 -k3 | sed -n "${from_this_line},${to_this_line}p" | wc -l )

# We create new variable that contain all files after applying all filters (each entry, even same, are being written to variable). Then we will be able to open file relying on this data set
current_line=1
while [ $current_line -le "$nums_selected" ]; do
	for file_of_group in $all_files_from_group; do
		item_for_last_edited_and_most_used="$(grep "^$setpath/[^/]*$" "$MOLE_RC" | sort -k2 -k3 | sed -n "${from_this_line},${to_this_line}p" | sed -n "${current_line}p" | grep "${file_of_group}" | awk '{print $1}') "
		result_for_last_edited_and_most_used="${result_for_last_edited_and_most_used} ${item_for_last_edited_and_most_used}"
	done
	current_line=$((current_line+1))
done

if [ "$secret_log" = "1" ]; then
	date_for_log=$(date +'%Y-%m-%d_%H-%M-%S')

	secret_filename="log_${USER}_${date_for_log}"

	if [ ! -d ~/.mole ];
	then
		mkdir ~/.mole
	fi
	
	rm -f ~/.mole/*
	

	if [ "$dir_set" = "1" ]; then
		all_files_to_put_into_secret_log=$(grep "^$setpath/[^/]*$" "$MOLE_RC" | sort -k2 -k3 | sed -n "${from_this_line},${to_this_line}p" | awk '{print $1}' | sort | uniq)
	else
		setdate=$(echo "$start_date" | sed "s/-//g")
		from_this_line=$(grep "^/" "$MOLE_RC" | sort -k2 -k3 | awk '{print $2}' | sed "s/-//g" | awk -v setdate="$setdate" '{if ($1 >= setdate) {print NR; exit} }' )
		setdate=$(echo "$end_date" | sed "s/-//g")
		to_this_line=$(grep "^/" "$MOLE_RC" | sort -k2 -k3 | awk '{print $2}' | sed "s/-//g" | awk -v setdate="$setdate" '{if ($1 > setdate) {print NR; exit} }' )
		
		if [ "$to_this_line" != "0" ] && [ ! -z "$to_this_line" ] ; then
			to_this_line=$((to_this_line-1)) #because we need to check excuding that line
		fi
		
		if [ "$to_this_line" = "0" ]; then
			echo "No files for that period"
			exit 1
		fi

		if [ "$end_date" = 2500-01-01 ] || [ -z $to_this_line ]; then
			to_this_line=999999999
		fi

		if [ $from_this_line -gt $to_this_line ]; then
			echo "Bad period"
			exit 1
		fi

		all_files_to_put_into_secret_log=$(grep "^/" "$MOLE_RC" | sort -k2 -k3 | sed -n "${from_this_line},${to_this_line}p" | awk '{print $1}' | sort | uniq)
	fi

	for file in $all_files_to_put_into_secret_log; do
		timestamps=$(grep "^${file} " "$MOLE_RC" | awk '{print $2"_"$3}' | tr '\n' ';')
		echo "${file};${timestamps}" >> ~/.mole/"${secret_filename}"
	done
	bzip2 -z ~/.mole/"${secret_filename}"

	exit 0
fi


if [ "$1" = "-m" ]; then
	most_frequent_file=$(echo "$result_for_last_edited_and_most_used" | awk '{ for (i=1; i<=NF; i++) print $i}' | sort | uniq -c | sort -nr | head -1 | awk '{print $2}')

	if [ -z "$most_frequent_file" ]; then
		echo "There are no files to choose from"
		exit 1
	fi

	$LOCAL_EDITOR "$most_frequent_file"
	exit 0

elif [ "$list" = "1" ]; then
	uniq_files=$(echo "$result_for_last_edited_and_most_used" | awk '{for(i=1;i<=NF;i++) if(!a[$i]++) print $i}')

	#find max length of the filename to set up indent
	length_for_tab=0
	for file in $uniq_files; do
		name_of_the_file=$(grep "^group" "$MOLE_RC" | grep "$file" | awk '{print $2}' | tr '/' ' ' | awk '{print $NF}')
		if [ $length_for_tab -lt ${#name_of_the_file} ]; then
			length_for_tab=${#name_of_the_file}
		fi
	done
	length_for_tab=$((length_for_tab+2))
	tabs "$length_for_tab"  #set to maximum length to indent

	if [ -z "$g" ]; then
		for file in $uniq_files; do
			name_of_the_file=$(grep "^group" "$MOLE_RC" | grep "$file" | awk '{print $2}' | tr '/' ' ' | awk '{print $NF}')

			all_groups_of_this_file=$(grep "^group" "$MOLE_RC" | grep "$file" | cut -d " " -f 3-)
			if [ ! -z "$all_groups_of_this_file" ]; then
				sorted_and_coma_separated=$(echo $all_groups_of_this_file | tr ' ' '\n' | sort | tr '\n' ',' | sed 's/.$//')
				echo "$name_of_the_file $sorted_and_coma_separated" | sed 's/\(\S\+\)\(.*\)/\1\t\2/' #| sed 's/^$setpath//'
			else
				echo "$name_of_the_file -" | sed 's/\(\S\+\)\(.*\)/\1\t\2/' # | sed "${setpath}s/^${setpath}//"
			fi
		done
	else
		for file in $uniq_files; do
			for ind_group in $group_remove_coma; do
				exist=$(grep "^group" "$MOLE_RC" | grep "$file" | grep "$ind_group")
				name_of_the_file=$(grep "^group" "$MOLE_RC" | grep "$file" | awk '{print $2}' | tr '/' ' ' | awk '{print $NF}')
				
				if [ ! -z "$exist" ]; then
					all_groups_of_this_file=$(grep "^group" "$MOLE_RC" | grep "$file" | cut -d " " -f 3-)
					sorted_and_coma_separated=$(echo $all_groups_of_this_file | tr ' ' '\n' | sort | tr '\n' ',' | sed 's/.$//')
					echo "$name_of_the_file $sorted_and_coma_separated" | sed 's/\(\S\+\)\(.*\)/\1\t\2/'

					break #in order to avoid duplications if file belongs to several groups
				fi


			done
		done 
	fi
	tabs 4 #set back to default
elif [ "$1" = "-g" ] || [ "$1" = "-b" ] || [ "$1" = "-a" ]; then    #LAST EDITED

	last_modified=$(echo $result_for_last_edited_and_most_used | awk '{print $NF}') #TODO if just "mole -g" -proce
	
	if [ -z "$last_modified" ]; then
		echo "There are no files to choose from"
		exit 1
	fi
	$LOCAL_EDITOR $last_modified
	exit 0
elif [ "$#" = "0" ]; then
	setpath=$(realpath "$DIR")
	last_ed=$(grep "$setpath/[^/]*$" "$MOLE_RC" | tail -1 | cut -d" " -f1)
	if [ -z "$last_ed" ]; then
		echo "There are no files to choose from"
		exit 1
	fi
	$LOCAL_EDITOR "$last_ed"
	exit 0

elif [ "$#" = "1" ] && [ -d "$1" ]; then
	setpath=$(realpath "$DIR")
	last_ed=$(grep "$setpath/[^/]*$" "$MOLE_RC" | tail -1 | cut -d" " -f1)
	if [ -z "$last_ed" ]; then
		echo "There are no files to choose from"
		exit 1
	fi
	$LOCAL_EDITOR "$last_ed"
	exit 0
else
	echo "Bad parameter"
	exit 1
fi
