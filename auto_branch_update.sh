#!/bin/bash 

: '
******* DESCRIZIONE SCRIPT ********
Agomenti da passare allo script:
1. Directory del repo
2. Nome del branch principale da cui fare marge.(senza origin/) -> esempio master oppure main
3. Path del file che contiene tutti i branch da ignorare

!!!! OBBLIGATORIO PASSARE IL FILE INGORED_BRANCH !!!!

ESEMPIO
./auto_branch_update.sh ./roomless-server master ignored_branch.txt

ESEMPIO FILE ignored_branch:
feature/f1
feature/f2
bugfix/b1
'

PROJECT_DIRECTORY=$(realpath "$1")
WORKING_DIRECTORY=$(realpath $(pwd))
REPO_MASTER_BRANCH="$2"
IGNORED_BRANCH_FILE=$(realpath "$3")
TELEGRAM_CHANNEL_ID="your-telegram-channel-id"
BOT_TOKEN="your-telegram-bot-token"
TELEGRAM_SEND_URL="https://api.telegram.org/bot${BOT_TOKEN}/sendMessage"

merged_branch=""
unmerged_branch=""
num_merged=0
num_unmerged=0

if [ $# -ne 3 ]; then
	echo "Missing argument. arg1: project folder, arg2: repo master branch (master or main)"
	exit -1
fi

echo "Updating active branch for the git project in ${PROJECT_DIRECTORY}"

cd "${PROJECT_DIRECTORY}"

PROJECT_NAME="${PWD##*/}" # get the current folder name, should be the project name

git fetch -p

# get the list of all active branch not merged yet
active_branch=$(git branch -r --no-merged)

echo ""
echo "ACTIVE BRANCH:"
echo "${active_branch}"
echo ""
echo "IGNORED BRANCH:"
cat "${IGNORED_BRANCH_FILE}"
echo ""

# loop all the branch
while IFS= read -r branch; do

	branch=$(echo ${branch} | xargs) # trim the whitespace at the begginning of the string
	
	# IGNORE origin/master,origin/main and origin/head branch
	if [[ "$branch" == *"origin/${REPO_MASTER_BRANCH}"* ]]; then
		continue
	fi

	if [[ "$branch" == *"origin/HEAD"* ]]; then
		continue
	fi

	branch=${branch//"origin/"} # Remove the origin/ at the beginning of the branch name
	echo "Trying to merge origin/${REPO_MASTER_BRANCH} in ${branch}"
	
	cat "$IGNORED_BRANCH_FILE" | grep "$branch" > /dev/null
	grep_status_code=$? # 0 if the branch is present in the file

	if [ $grep_status_code -eq 0 ]; then
		echo "IGNORING BRANCH ${branch}"
               	continue
        fi

	git checkout "$branch"
	git pull
	
	res=$(git merge origin/${REPO_MASTER_BRANCH})
	merge_status_code=$?
	out=$(echo "${res}" | grep "Già aggiornato.\|Already updated.\|Everything up-to-date")
		
	# If the branch is already updated with the master branch skip
	if [ $? -eq -1 ]; then
		echo ""
                continue
        fi
	
	if [ $merge_status_code -ne 0 ]; then
		echo "Error while merging, ABORT"
		git merge --abort
		unmerged_branch="${unmerged_branch}${branch}\n"
		num_unmerged=$((num_unmerged+1))

	else
		echo "Merged ${REPO_MASTER_BRANCH} into ${branch}"
		merged_branch="${merged_branch}${branch}\n"
		git push
		num_merged=$((num_merged+1))
	fi

	echo ""

done <<< "$active_branch"

# sending summary message only if there is somothing to communicate
echo "MERGED: ${num_merged}, UNMERGED: ${num_unmerged}"

if [ $num_merged -ne 0 ] || [ $num_unmerged -ne 0 ]; then

	message="${PROJECT_NAME} MERGE SUMMARY\n\n"
	
	if [ $num_merged -ne 0 ]; then
		message="${message}\nMASTER MERGED INTO:\n${merged_branch}\n"
	fi

	if [ $num_unmerged -ne 0 ]; then
		message="${message}\nNOT MERGED:\n${unmerged_branch}"
	fi

	body="{\"chat_id\": \"${TELEGRAM_CHANNEL_ID}\",\"text\":\"${message}\" }"
	
	# send message to telegram
	curl -s -X POST "${TELEGRAM_SEND_URL}" -H 'Content-Type: application/json' -d "${body}" 2>&1 > /dev/null

fi


