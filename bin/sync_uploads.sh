#!/bin/bash
# Resolve the directory where the script is located
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
# echo "SCRIPT_DIR: $SCRIPT_DIR"



# Check if the script is running within the 'vendor' directory
if [[ $SCRIPT_DIR == *"/vendor/"* ]]; then
    # We are in the 'vendor' directory (script used as a dependency)
    ROOT_DIR="${SCRIPT_DIR}/../../../.."
else
    # We are in the package's own directory (script used by the maintainer)
    ROOT_DIR="${SCRIPT_DIR}/.."
fi
ROOT_DIR=$(realpath $ROOT_DIR)
ENV_LOCAL="${ROOT_DIR}/.env"
# echo $ROOT_DIR


# Now source the .env file if it exists
if [ -f "$ENV_LOCAL" ]; then
    source "$ENV_LOCAL"
else
    echo "Warning: .env file not found at $ENV_LOCAL"
    exit 1
fi


if ! command -v rsync &> /dev/null
then
    echo "rsync could not be found, please install"
    exit
fi



# remotes dans le fichier de conf
REMOTES=`cat $ENV_LOCAL | grep REMOTES |  cut -d "=" -f2-`
if [ -z "$REMOTES" ]
then
    echo "\$REMOTES is empty"
    exit 1
fi

PS3="Select a remote from your .env: "
REMOTES=`echo $REMOTES | tr -d '"'`
select REMOTE in $REMOTES
do
    echo "Selected remote: $REMOTE"
    # echo "Selected number: $REPLY ${REMOTES[$REPLY]}"
    break
done

VARS=("DIR" "HOST" "PORT" "USER" "PHP" "SYNC")
for VAR in ${VARS[@]}; do
    declare "SSH_${VAR}"=`cat $ENV_LOCAL | grep "${REMOTE}_SSH_${VAR}" |  cut -d "=" -f2-`
done
echo "SSH_DIR  : $SSH_DIR"
echo "SSH_HOST : $SSH_HOST"
echo "SSH_PORT : $SSH_PORT"
echo "SSH_USER : $SSH_USER"
echo "SSH_SYNC : $SSH_SYNC"

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
# echo "SCRIPT_DIR : $SCRIPT_DIR"

RSYNC_PARAMS="-azu --progress --info=NAME1"
RSYNC_LOCAL="${ROOT_DIR}${SSH_SYNC}"
RSYNC_REMOTE="${SSH_USER}@${SSH_HOST}:${SSH_DIR}${SSH_SYNC}"
RSYNC_SSH="-e 'ssh -p ${SSH_PORT}'"


# TODO: catch rsync connection error
echo ""
echo "Do you want to download or upload? (d/u)"

read du
if [ "$du" != "${du#[Dd]}" ] ;then
  # download
  RSYNC_CMD="$RSYNC_PARAMS $RSYNC_SSH $RSYNC_REMOTE/ $RSYNC_LOCAL"
else
  # upload
  RSYNC_CMD="$RSYNC_PARAMS $RSYNC_SSH $RSYNC_LOCAL/ $RSYNC_REMOTE"
fi

# echo ""
# echo "I will perform:"
# echo "rsync $RSYNC_CMD"

echo ""
echo "Preview (simulating transfer):"
echo "rsync $RSYNC_PARAMS --dry-run $RSYNC_CMD"
eval "rsync $RSYNC_PARAMS --dry-run $RSYNC_CMD"

echo ""
echo "Do you want to proceed with transfer? (y/n)"

read yn
if [ "$yn" != "${yn#[Yy]}" ] ;then
  eval "rsync $RSYNC_PARAMS $RSYNC_CMD"
else
  exit 1
fi

echo "End of script."
