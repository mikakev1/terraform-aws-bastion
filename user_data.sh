#!/usr/bin/env bash 
set -x
yum -y update --security
##########################
##    INPUTS / CONFIG   ##
##########################

declare -r BASTION_LOGDIR=/var/log/bastion
declare -r EC2_USER="ec2-user"
# TODO should be EC2 GROUP
declare -r EC2_GROUP="ec2-user"


function setup_logdir() {
  # Create a new folder for the log files
  [ -d "${BASTION_LOGDIR}" ] || mkdir "${BASTION_LOGDIR}"

  # Allow ec2-user only to access this folder and its content
  chown ${EC2_USER}:${EC2_GROUP} "${BASTION_LOGDIR}"
  chmod -R 770 "${BASTION_LOGDIR}"
  setfacl -Rdm other:0 "${BASTION_LOGDIR}"
}

function newscript() {
  set -r script_name=${1}
  echo "#/usr/bin/env bash" > "${script_name}"
  echo "LOG_DIR="${BASTION_LOGDIR}" > ${script_name}"
  chmod 700 "${script_name}"
}


##########################
## ENABLE SSH RECORDING ##
##########################

# Setup bastion's log sink
setup_logdir

# Make OpenSSH execute a custom script on logins
# TODO : Should ensure that SSH key is only used for login and restrict to command usage on client too
(echo; echo "ForceCommand /usr/bin/bastion/shell") >> /etc/ssh/sshd_config


# Block some SSH features that bastion host users could use to circumvent the solution

TEMP_SSHCONFIG=$(mktemp)

grep -vi "X11Forwarding" /etc/ssh/sshd_config > ${TEMP_SSHCONFIG} && mv ${TEMP_SSHCONFIG} /etc/ssh/sshd_config
echo "X11Forwarding no" >> /etc/ssh/sshd_config

[ -d "/usr/bin/bastion" ] || mkdir /usr/bin/bastion

newscript /usr/bin/bastion/shell
cat >> /usr/bin/bastion/shell << 'EOF'

# Check that the SSH client did not supply a command
if [[ -z "${SSH_ORIGINAL_COMMAND}" ]]; then

  # The format of log files is /var/log/bastion/YYYY-MM-DD_HH-MM-SS_user
  LOG_FILE="$(date --date="today" "+%Y-%m-%d_%H-%M-%S")_$(whoami)"
  # HERE-DOC should use global variable anytime unless...
  
  # Print a welcome message
  echo ""
  echo "NOTE: This SSH session will be recorded"
  echo "AUDIT KEY: $LOG_FILE"
  echo ""

  # I suffix the log file name with a random string. I explain why later on.
  SUFFIX=`mktemp -u _XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX`

  # Wrap an interactive shell into "script" to record the SSH session
  script -qf --timing=$LOG_DIR$LOG_FILE$SUFFIX.time $LOG_DIR$LOG_FILE$SUFFIX.data --command=/bin/bash

else

  # The "script" program could be circumvented with some commands (e.g. bash, nc).
  # Therefore, I intentionally prevent users from supplying commands.

  echo "This bastion supports interactive sessions only. Do not supply a command"
  exit 1

fi

EOF

# Make the custom script executable
chmod a+x /usr/bin/bastion/shell

# Bastion host users could overwrite and tamper with an existing log file using "script" if
# they knew the exact file name. I take several measures to obfuscate the file name:
# 1. Add a random suffix to the log file name.
# 2. Prevent bastion host users from listing the folder containing log files. This is done
#    by changing the group owner of "script" and setting GID.
chown root:${EC2_GROUP} /usr/bin/script
chmod g+s /usr/bin/script

# 3. Prevent bastion host users from viewing processes owned by other users, because the log
#    file name is one of the "script" execution parameters.
awk '!/proc/' /etc/fstab > temp && mv temp /etc/fstab
echo "proc /proc proc defaults,hidepid=2 0 0" >> /etc/fstab
mount -o remount /proc

# Restart the SSH service to apply /etc/ssh/sshd_config modifications.
service sshd restart

############################
## EXPORT LOG FILES TO S3 ##
############################
newscript /usr/bin/bastion/sync_s3

cat >> /usr/bin/bastion/sync_s3 << 'EOF'
# Copy log files to S3 with server-side encryption enabled.
# Then, if successful, delete log files that are older than a day.

aws s3 cp $LOG_DIR s3://${bucket_name}/logs/ --sse --region ${aws_region} --recursive && find $LOG_DIR* -mtime +1 -exec rm {} \;

EOF

#######################################
## SYNCHRONIZE USERS AND PUBLIC KEYS ##
#######################################

# Bastion host users should log in to the bastion host with their personal SSH key pair.
# The public keys are stored on S3 with the following naming convention: "username.pub".
# This script retrieves the public keys, creates or deletes local user accounts as needed,
# and copies the public key to /home/username/.ssh/authorized_keys

newscript /usr/bin/bastion/sync_users
cat >> /usr/bin/bastion/sync_users << 'EOF'
# The file will log user changes
LOG_FILE="${LOG_DIR}/users_changelog.txt"

# The function returns the user name from the public key file name.
# Example: public-keys/sshuser.pub => sshuser
get_user_name () {
  echo "$1" | sed -e "s/.*\///g" | sed -e "s/\.pub//g"
}

# For each public key available in the S3 bucket
aws s3api list-objects --bucket ${bucket_name} --prefix public-keys/ --region ${aws_region} --output text --query 'Contents[?Size>`0`].Key' | tr '\t' '\n' > ~/keys_retrieved_from_s3
while read line; do
  USER_NAME="`get_user_name "$line"`"

  # Make sure the user name is alphanumeric
  if [[ "$USER_NAME" =~ ^[a-z][-a-z0-9]*$ ]]; then

    # Create a user account if it does not already exist
    cut -d: -f1 /etc/passwd | grep -qx $USER_NAME
    if [ $? -eq 1 ]; then
      /usr/sbin/adduser $USER_NAME && \
      mkdir -m 700 /home/$USER_NAME/.ssh && \
      chown $USER_NAME:$USER_NAME /home/$USER_NAME/.ssh && \
      echo "$line" >> ~/keys_installed && \
      echo "`date --date="today" "+%Y-%m-%d %H-%M-%S"`: Creating user account for $USER_NAME ($line)" >> $LOG_FILE
    fi

    # Copy the public key from S3, if an user account was created from this key
    if [ -f ~/keys_installed ]; then
      grep -qx "$line" ~/keys_installed
      if [ $? -eq 0 ]; then
        aws s3 cp s3://${bucket_name}/$line /home/$USER_NAME/.ssh/authorized_keys --region ${aws_region}
        chmod 600 /home/$USER_NAME/.ssh/authorized_keys
        chown $USER_NAME:$USER_NAME /home/$USER_NAME/.ssh/authorized_keys
      fi
    fi

  fi
done < ~/keys_retrieved_from_s3

# Remove user accounts whose public key was deleted from S3
if [ -f ~/keys_installed ]; then
  sort -uo ~/keys_installed ~/keys_installed
  sort -uo ~/keys_retrieved_from_s3 ~/keys_retrieved_from_s3
  comm -13 ~/keys_retrieved_from_s3 ~/keys_installed | sed "s/\t//g" > ~/keys_to_remove
  while read line; do
    USER_NAME="`get_user_name "$line"`"
    echo "`date --date="today" "+%Y-%m-%d %H-%M-%S"`: Removing user account for $USER_NAME ($line)" >> $LOG_FILE
    /usr/sbin/userdel -r -f $USER_NAME
  done < ~/keys_to_remove
  comm -3 ~/keys_installed ~/keys_to_remove | sed "s/\t//g" > ~/tmp && mv ~/tmp ~/keys_installed
fi

EOF

###########################################
## SCHEDULE SCRIPTS AND SECURITY UPDATES ##
###########################################

CRONFILE=${mktemp}

cat > ${CRONFILE} << EOF
*/5 * * * * /usr/bin/bastion/sync_s3
*/5 * * * * /usr/bin/bastion/sync_users
0 0 * * * yum -y update --security
EOF
crontab ${CRONFILE}
rm ${CRONFILE}
