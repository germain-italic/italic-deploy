#!/bin/bash -i


#############################
#                           #
#    Default temp folder    #
#                           #
#############################

TMP="/scripts/tmp"
DEST="$(pwd)/..${TMP}"



#########################
#                       #
#    Read local .env    #
#                       #
#########################

# fichier de conf local
ENV_LOCAL="$(pwd)/../.env"
[[ ! -f $ENV_LOCAL ]] && echo "Error: missing .env local file in $ENV_LOCAL" && exit 1



#################################
#                               #
#    Custom execution values    #
#                               #
#################################

# Function to prompt for confirmation with a default value
prompt_confirm() {
    local default=$1
    local prompt=$2
    local choice

    while true; do
        read -r -p "$prompt ($default) : " choice
        case "$choice" in
            [yY]) return 1 ;;
            [nN]) return 0 ;;
            "") [ "$default" = "y" ] && return 1 || return 0 ;;
            *) echo "Invalid input";;
        esac
    done
}

# Associative array for storing variables, default values, and questions
declare -A config=(
    [CREATE_DUMP]="y:Create local dump?"
    [UPLOAD_DUMP]="y:Upload dump to remote?"
    [IMPORT_DUMP]="y:Import dump on remote?"
    [DROP_REMOTE_TABLES]="n:Drop remote tables?"
    [SHOW_DROPPED_LIST]="y:Show dropped tables?"
    [DELETE_REMOTE_DUMP]="y:Delete remote dump?"
    [DELETE_LOCAL_DUMP]="n:Delete local dump?"
    [REBUILD_CACHE]="n:Rebuild remote cache?"
)

# Indexed array to define the order of the keys
order=("CREATE_DUMP" "UPLOAD_DUMP" "IMPORT_DUMP" "DROP_REMOTE_TABLES" "SHOW_DROPPED_LIST" "DELETE_REMOTE_DUMP" "DELETE_LOCAL_DUMP" "REBUILD_CACHE")

echo "Please confirm or change the default execution values (y/n):"

# Loop through the ordered array
for key in "${order[@]}"; do
    # Split value into default value and question
    IFS=":" read -r default_value question <<< "${config[$key]}"
    # Prompt for confirmation
    prompt_confirm "$default_value" "$question" && eval "$key=0" || eval "$key=1"
done

# Optional: Display the updated values
echo ""
echo "Execution values:"
for key in "${order[@]}"; do
    echo "$key : ${!key}"
done


# confirm values
prompt_confirm "y" "Continue?" && exit 1




#################################
#                               #
#    select a remote target     #
#                               #
#################################

# remotes dans le fichier de conf
# IFS=' '
REMOTES=`cat $ENV_LOCAL | grep REMOTES |  cut -d "=" -f2-`
REMOTES=`echo $REMOTES | tr -d '"'`
if [ -z "$REMOTES" ]
then
    echo "$ENV_LOCAL has not remote"
    exit 1
fi

echo ""
echo "Remotes found in your .env:"
PS3="Please enter remote number: "
select REMOTE in $REMOTES
do
    echo "Selected remote: $REMOTE"
    # echo "Selected number: $REPLY ${REMOTES[$REPLY]}"
    break
done

[[ -z "$REMOTE" ]] && echo "Error: remote not found (please type a suggested number)" && exit 1

VARS=("DIR" "HOST" "PORT" "USER" "PHP")
for VAR in ${VARS[@]}; do
    VARNAME="SSH_${VAR}"
    eval "$VARNAME"=`cat $ENV_LOCAL | grep "${REMOTE}_SSH_${VAR}" |  cut -d "=" -f2-`
    # echo "$VARNAME : ${!VARNAME}"
    [ -z "${!VARNAME}" ] && echo "Error: detected empty SSH ${VAR} in remote '$REMOTE'" && exit 1
done
echo ""



################################
#                              #
#    Are we in a GIT repo ?    #
#                              #
################################

GIT_INFO="unversionned"

# Check if the current directory is part of a Git repository
if git rev-parse --git-dir > /dev/null 2>&1; then
    # Get the current branch name
    branch_name=$(git rev-parse --abbrev-ref HEAD)

    # Get the latest commit ID
    latest_commit=$(git rev-parse --short HEAD)

    # Combine the branch name and commit ID
    GIT_INFO="${branch_name}-${latest_commit}"
fi

# Display the information or indicate that it's not a Git repository
if [ -n "$GIT_INFO" ]; then
    echo "You are on branch ${branch_name} and the latest commit is ${latest_commit}, appending suffix to export name."
else
    echo "Not in a Git repository, using current date as suffix to export name."
fi



###########################
#                         #
#    Create local dump    #
#                         #
###########################


# pas de nom de fichier passé en paramètre ?
if [ -z "$1" ]
then

    if [ $CREATE_DUMP -eq 1 ]
    then

        echo "Creating local dump, please be patient..."

        # check required dependency
        if ! command -v gzip &> /dev/null
        then
            echo "Error: gzip could not be found, please install locally"
            exit 1
        fi

        # export dump db locale
        LOCAL_DB_NAME=`cat $ENV_LOCAL | grep DB_NAME |  cut -d "=" -f2-`
        LOCAL_DB_USER=`cat $ENV_LOCAL | grep DB_USER |  cut -d "=" -f2-`
        LOCAL_DB_PASSWORD=`cat $ENV_LOCAL | grep DB_PASSWORD |  cut -d "=" -f2-`
        LOCAL_DB_HOST=`cat $ENV_LOCAL | grep DB_HOST |  cut -d "=" -f2-`
        LOCAL_DB_PORT=`cat $ENV_LOCAL | grep DB_PORT |  cut -d "=" -f2-`
        LOCAL_MYSQLDUMP_PATH=`cat $ENV_LOCAL | grep MYSQLDUMP_PATH |  cut -d "=" -f2-`
        export MYSQL_PWD=${LOCAL_DB_PASSWORD}

        FILENAME=${LOCAL_DB_NAME}-$(date +"%Y_%m_%d-%H_%M_%S")-${GIT_INFO}.sql

        CMD="${LOCAL_MYSQLDUMP_PATH}/mysqldump --add-drop-table -h $LOCAL_DB_HOST -u $LOCAL_DB_USER -P $LOCAL_DB_PORT $LOCAL_DB_NAME > ${DEST}/$FILENAME"
        echo $CMD
        eval "$CMD"

        if [ $? -eq 0 ]
        then
            gzip "${DEST}/$FILENAME"

            if [ $? -eq 0 ]
            then
                FILENAME="${FILENAME}.gz"
                FZ=`du -sh ${DEST}/$FILENAME`
                echo "Info: dumped local database: $FZ"
            else
                echo "Error: dumped local database $FILENAME but gzip failed."
                exit 1
            fi
        else
            echo "Error: failed to export mysql dump (check credentials?)"
            exit 1
        fi
    fi
    echo ""
fi



##############################
#                            #
#    Re-use existing dump    #
#                            #
##############################

if [ ! -z "$1" ]
then

    # chemin du fichier à importer passé en paramètre
    echo "Info: using file $1 for import, ignoring CREATE_DUMP=y"

    # on regarde si le fichier est absolu
    if [[ -f $1 ]]
    then
        DEST=
        FILENAME=$1
    else

    # on regarde s'il est dans le dossier tmp du script
        if [[ ! -f ${DEST}/$1 ]]
        then
            echo "Error: local file $1 not found"
            exit 1
        else
            FILENAME=$1
        fi
    fi
    echo ""
fi



#################################
#                               #
#    Check dump availability    #
#                               #
#################################

# Function to list files in $DEST ordered by date (newest first)
list_files() {
    ls -lt ${DEST} | awk 'NR>1 {print $9}' # List only filenames
}

if [ -z "$FILENAME" ]
then
    # Listing files
    echo "Checking for available dumps in ${DEST}:"
    FILE_LIST=($(list_files)) # Store files in an array
    if [[ ${#FILE_LIST[@]} -eq 0 ]]; then
        echo "No dumps available."
        exit 1
    else
        # Display files with numbers
        for i in "${!FILE_LIST[@]}"; do
            echo "$((i+1)) - ${FILE_LIST[$i]}"
        done

        # Prompting user to choose a file
        echo "Please select a dump file by number:"
        read -p "Enter number: " file_number
        file_index=$((file_number-1)) # Array index adjustment

        # Validation
        if ! [[ "$file_number" =~ ^[0-9]+$ ]] || [ $file_index -lt 0 ] || [ $file_index -ge ${#FILE_LIST[@]} ]; then
            echo "Invalid selection. Please enter a valid number."
            exit 1
        fi

        FILENAME=${FILE_LIST[$file_index]}
        BASENAME=$(basename ${FILENAME})
    fi
else
    BASENAME=$(basename ${FILENAME})
fi



#########################
#                       #
#    Get remote .env    #
#                       #
#########################

# fichier .env remote
REMOTE_ENV=`ssh -p $SSH_PORT ${SSH_USER}@${SSH_HOST} "cat $SSH_DIR/.env"`
if [ $? -ne 0 ]
then
    echo "Error: cannot find .env remote file on $SSH_HOST"
    exit 1
fi

VARS=("DB_NAME" "DB_USER" "DB_PASSWORD" "DB_HOST" "DB_PORT")
for VAR in ${VARS[@]}; do
    VARNAME="REMOTE_${VAR}"
    eval "$VARNAME"=`echo "$REMOTE_ENV" | grep "${VAR}" |  cut -d "=" -f2-`
    # echo "$VARNAME : ${!VARNAME}"
    [ -z "${!VARNAME}" ] && echo "Error: detected empty ${VAR} in $SSH_DIR/.env on remote $REMOTE" && exit 1
done



############################
#                          #
#    Drop remote tables    #
#                          #
############################

if [ $DROP_REMOTE_TABLES -eq 1 ]
then
    # TODO: create mysql backup on remote host

    echo "Fetching tables list from $REMOTE_DB_NAME"

    export MYSQL_PWD=${REMOTE_DB_PASSWORD}
    CMD="mysql -h $REMOTE_DB_HOST -u $REMOTE_DB_USER -P $REMOTE_DB_PORT -Nse 'SHOW TABLES' $REMOTE_DB_NAME"
    # echo $CMD
    TABLES=$(eval "$CMD")

    if [ $? -ne 0 ]
    then
        echo "Error: failed fetch remote tables list"
        exit 1
    else
        NONEMPTYLINES=`echo $TABLES | grep -v ^$ | wc -l`
        if [ $NONEMPTYLINES -gt 0 ]
        then
            LINES=`echo "$TABLES" | wc -l`
            echo "Found $LINES tables: dropping, please be patient..."

            QRY="SET autocommit = 0; SET @OLD_FOREIGN_KEY_CHECKS=@@FOREIGN_KEY_CHECKS, FOREIGN_KEY_CHECKS=0; "
            LIST=""
            for TABLE in $TABLES; do
                CLEAN=${TABLE//$'\r'/}
                QRY+="DROP TABLE \`$CLEAN\`; "
                LIST+="$CLEAN  "
            done

            QRY+="SET autocommit = 1; SET FOREIGN_KEY_CHECKS=@OLD_FOREIGN_KEY_CHECKS;"
            # echo "$QRY"
            # echo "$LIST"
            mysql -h $REMOTE_DB_HOST -u $REMOTE_DB_USER -P $REMOTE_DB_PORT -e "$QRY" $REMOTE_DB_NAME
            if [ "$?" -eq 0 ];
            then
                if [ $SHOW_DROPPED_LIST -eq 1 ]
                then
                    echo "  Dropped tables: $LIST"
                else
                    echo "  Dropped all tables."
                fi
            else
                echo "  Error: tables could not be dropped."
                exit 1
            fi
        else
            echo "  Info: no tables found in $REMOTE_DB_NAME"
        fi
    fi
    echo ""
fi



#####################################
#                                   #
#    Upload local dump to remote    #
#                                   #
#####################################

if [ $UPLOAD_DUMP -eq 1 ]
then
    echo "Info: uploading $BASENAME to remote ${SSH_DIR}$TMP"
    ssh -p $SSH_PORT ${SSH_USER}@${SSH_HOST} "mkdir -p ${SSH_DIR}$TMP"

    scp -O -P $SSH_PORT ${DEST}/$FILENAME ${SSH_USER}@${SSH_HOST}:${SSH_DIR}${TMP}/${BASENAME}
    echo ""
fi



###############################
#                             #
#    Import dump on remote    #
#                             #
###############################

if [ $IMPORT_DUMP -eq 1 ]
then

    # TODO: check required dependencies on remote host
    # if ! command -v pv &> /dev/null
    # then
    #     echo "pv could not be found, please install: https://www.ivarch.com/programs/pv.shtml"
    #     exit
    # fi

    # if ! command -v gunzip &> /dev/null
    # then
    #     echo "gunzip could not be found, please install"
    #     exit
    # fi

    echo "Info: importing $BASENAME into $REMOTE_DB_NAME, please be patient..."
    CMD="export MYSQL_PWD=${REMOTE_DB_PASSWORD}; gunzip -c ${SSH_DIR}${TMP}/${BASENAME} | pv -f -cN gunzip -c | mysql -h $REMOTE_DB_HOST -u $REMOTE_DB_USER -P $REMOTE_DB_PORT $REMOTE_DB_NAME"
    ssh -p $SSH_PORT ${SSH_USER}@${SSH_HOST} $CMD
    if [ $? -ne 0 ]
    then
        echo "Error: importing mysql dump failed."
        exit 1
    else
        echo "  Success: dump was imported."
    fi
    echo ""
fi



###############################
#                             #
#    Delete dump on remote    #
#                             #
###############################

if [ $DELETE_REMOTE_DUMP -eq 1 ]
then
    echo "Info: deleting $BASENAME from the remote (keeping a local copy)"
    ssh -p $SSH_PORT ${SSH_USER}@${SSH_HOST} "rm ${SSH_DIR}${TMP}/${BASENAME}"
    echo ""
fi



###########################
#                         #
#    Delete local dump    #
#                         #
###########################

if [ $DELETE_LOCAL_DUMP -eq 1 ]
then
    echo "Info: deleting local dump ${DEST}/$FILENAME"
    rm ${DEST}/$FILENAME
    echo ""
fi



###################################
#                                 #
#    Rebuild cache using drush    #
#                                 #
###################################

# TODO: check if website is drupal or not
# TODO: check if drush is available on remote

# if [ $REBUILD_CACHE -eq 1 ]
# then
#     echo "Info: rebuilding cache"
#     ssh -p $SSH_PORT ${SSH_USER}@${SSH_HOST} "${SSH_PHP} ${SSH_DIR}/www/vendor/bin/drush cr"
#     echo ""
# fi

echo "End of script."
