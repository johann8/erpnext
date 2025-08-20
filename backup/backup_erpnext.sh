#!/bin/bash

# Abort on all errors, set -x
set -o errexit
#set -x

# Set vars
_DATUM="$(date '+%Y-%m-%d %Hh:%Mm:%Ss')"
TIMESTAMP=$(date +\%Y-\%m-\%d);
BACKUPDIR="/mnt/storage1/pbs01/backup_erpnext"
# 7 days = 7 x 4 = 28
NUMBER_BACKED_UP_FILES=28
TMP_FILE=$(cat /dev/urandom | tr -cd 'a-f0-9' | head -c 6)

# CUSTOM - script
SCRIPT_NAME="backup_erpnext.sh"
BASENAME=${SCRIPT_NAME}
SCRIPT_VERSION="0.1.2"
SCRIPT_START_TIME=$SECONDS                          # Script start time

# CUSTOM - logs
FILE_LAST_LOG='/tmp/'${SCRIPT_NAME}'.log'
FILE_MAIL='/tmp/'${SCRIPT_NAME}'.mail'

# CUSTOM - Send mail
MAIL_STATUS='Y'                                                                 # Send Status-Mail [Y|N]
PROG_SENDMAIL='/sbin/sendmail'
VAR_HOSTNAME=$(hostname -f)
VAR_SENDER='root@'${VAR_HOSTNAME}
VAR_EMAILDATE=$(date '+%a, %d.%m.%Y %H:%M:%S (%Z)')

# CUSTOM - Mail-Recipient.
MAIL_RECIPIENT='admin@myfirma.de'

##############################################################################
# >>> Normaly there is no need to change anything below this comment line. ! #
##############################################################################

DOCKER_COMMAND=$(command -v docker)
FIND_COMMAND=$(command -v find)

# Function: send mail
function sendmail() {
     case "$1" in
     'STATUS')
               MAIL_SUBJECT='Status execution '${SCRIPT_NAME}' script.'
              ;;
            *)
               MAIL_SUBJECT='ERROR while execution '${SCRIPT_NAME}' script !!!'
               ;;
     esac

cat <<EOF >$FILE_MAIL
Subject: $MAIL_SUBJECT
Date: $VAR_EMAILDATE
From: $VAR_SENDER
To: $MAIL_RECIPIENT
EOF

# sed: Remove color and move sequences
echo -e "\n" >> $FILE_MAIL
cat $FILE_LAST_LOG  >> $FILE_MAIL
${PROG_SENDMAIL} -f ${VAR_SENDER} -t ${MAIL_RECIPIENT} < ${FILE_MAIL}
rm -f ${FILE_MAIL}
}

#
### ============= Main script ============
#

echo -e "\n" 2>&1 > ${FILE_LAST_LOG}
echo -e "Started on \"$(hostname -f)\" at \"${_DATUM}\"" 2>&1 | tee -a ${FILE_LAST_LOG}
echo -e "Script version is: \"${SCRIPT_VERSION}\"" 2>&1 | tee -a ${FILE_LAST_LOG}
# echo -e "Datum: $(date "+%Y-%m-%d")" 2>&1 | tee -a ${FILE_LAST_LOG}
echo -e "===========================" 2>&1 | tee -a ${FILE_LAST_LOG}
echo -e "  Run backup of ERPNext"     2>&1 | tee -a ${FILE_LAST_LOG}
echo -e "===========================" 2>&1 | tee -a ${FILE_LAST_LOG}
echo " " 2>&1 | tee -a ${FILE_LAST_LOG}

# Switch to the folder
cd /opt/erpnext

# Creare ernext Backup
echo "Info: \"erpnext\"container backup is being created... " 2>&1 | tee -a ${FILE_LAST_LOG}
if ${DOCKER_COMMAND} compose -p erpnext-one exec backend bench --site all backup --with-files --compress --backup-path /backup/${TIMESTAMP} > /dev/null; then
  echo "Info: Backup of \"erpnext\"container is created." 2>&1 | tee -a ${FILE_LAST_LOG}
else
  echo "Error: Backup of \"erpnext\"container could not be createded." 2>&1 | tee -a ${FILE_LAST_LOG}
  exit 1
fi

# Count backed up files
COUNT_FILES=$(${FIND_COMMAND} ${BACKUPDIR} -type f -print0 | xargs -0 ls -t | uniq -u | wc -l)
# echo ${COUNT_FILES}

# Always the required number +1 ; 28 + 1 = 29
# ${FIND_COMMAND} . -type f | xargs ls -t -la | uniq -u | tail -n  +$(expr ${NUMBER_BACKED_UP_FILES} + 1)

# Count files and delete unnecessary ones
if [ ${COUNT_FILES} -le ${NUMBER_BACKED_UP_FILES} ]; then
  #
  echo "SKIP: There are too few files to delete: \"${COUNT_FILES}\"" 2>&1 | tee -a ${FILE_LAST_LOG}
  #echo ""
else
  COUNT_FILES_TO_DELETE=$(expr ${COUNT_FILES} - ${NUMBER_BACKED_UP_FILES})
  echo "Info: They are \"${COUNT_FILES_TO_DELETE}\" old files to delete." 2>&1 | tee -a ${FILE_LAST_LOG}
  # Always the required number +1 ; 28 + 1 = 29
  #${FIND_COMMAND} ${BACKUPDIR} -type f -print0 | xargs -0 ls -t | uniq -u | tail -n  +$(expr ${NUMBER_BACKED_UP_FILES} + 1) | xargs -0 rm -f > /dev/null

  # find files und put them into file
  ${FIND_COMMAND} ${BACKUPDIR} -type f -print0 | xargs -0 ls -t | uniq -u | tail -n  +$(expr ${NUMBER_BACKED_UP_FILES} + 1) > /tmp/${TMP_FILE}.txt

  #check if tmp file exist
  if [ -f "/tmp/${TMP_FILE}.txt" ];then

    # chek if file is empty
    if [ -s "/tmp/${TMP_FILE}.txt" ];then
      echo "Info: File \"/tmp/${TMP_FILE}.txt\" exists and not empty" 2>&1 | tee -a ${FILE_LAST_LOG}

      #delete files from tmp file
      echo "Info: old files will be deleted." 2>&1 | tee -a ${FILE_LAST_LOG}
      xargs -I{} rm -r "{}" < /tmp/${TMP_FILE}.txt
      RES1=$?
    else
      echo "File \"/tmp/${TMP_FILE}.txt\" exists but empty." 2>&1 | tee -a ${FILE_LAST_LOG}
      rm -rf /tmp/${TMP_FILE}.txt > /dev/null
    fi

  else
    echo "File \"/tmp/${TMP_FILE}.txt\" not exists." 2>&1 | tee -a ${FILE_LAST_LOG}
  fi

  # Check result
  if [ "$RES1" = "0" ]; then
    echo "Info: ${COUNT_FILES_TO_DELETE} old files were deleted!" 2>&1 | tee -a ${FILE_LAST_LOG}
    echo "--------------------------" 2>&1 | tee -a ${FILE_LAST_LOG}

    # delete tmp file
    rm -rf /tmp/${TMP_FILE}.txt > /dev/null
  else
    echo "Error: Old files could not be deleted!" 2>&1 | tee -a ${FILE_LAST_LOG}
    exit 1
  fi
fi

# Delete empty folders
COUNT_EMPTY_DIRECTORIES=$(${FIND_COMMAND} ${BACKUPDIR} -type d -empty -print |wc -l)
if [ ${COUNT_EMPTY_DIRECTORIES} -gt 0 ]; then
  echo "Info: Empty directories will be deleted... " 2>&1 | tee -a ${FILE_LAST_LOG}

  if ${FIND_COMMAND} ${BACKUPDIR} -type d -empty -print -delete; then
    echo "Info: Empty directories are deleted." 2>&1 | tee -a ${FILE_LAST_LOG}
  else
    echo "Error: Empty directories could not be deleted." 2>&1 | tee -a ${FILE_LAST_LOG}
  fi

else
  echo "Info: There are no empty directories." 2>&1 | tee -a ${FILE_LAST_LOG}
fi

# show all folders
(
echo " "
echo -e "======= Show all backup directories  ======="
#tree -i -d -L 1 ${BACKUPDIR} | sed '/director/d'
tree -ah --du ${BACKUPDIR}
) 2>&1 | tee -a ${FILE_LAST_LOG}

# print "end of script"
echo -e "/------------ Script ended at: \"${_DATUM}\" ------------/" 2>&1 | tee -a ${FILE_LAST_LOG}

# Script run time calculate
#
#SCRIPT_START_TIME=$SECONDS
SCRIPT_END_TIME=$SECONDS
let deltatime=SCRIPT_END_TIME-SCRIPT_START_TIME
let hours=deltatime/3600
let minutes=(deltatime/60)%60
let seconds=deltatime%60
printf "Time elapsed: %d:%02d:%02d\n" $hours $minutes $seconds 2>&1 | tee -a ${FILE_LAST_LOG}
echo -e " " 2>&1 | tee -a ${FILE_LAST_LOG}

### Send status e-mail
if [ ${MAIL_STATUS} = 'Y' ]; then
   echo -e "Sending staus mail ... " 2>&1 | tee -a ${FILE_LAST_LOG}
   sendmail STATUS
fi

