#!/bin/bash
# Resolve the directory where the script is located
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
echo "SCRIPT_DIR: $SCRIPT_DIR"



# Check if the script is running within the 'vendor' directory
if [[ $SCRIPT_DIR == *"/vendor/"* ]]; then
    # We are in the 'vendor' directory (script used as a dependency)
    ENV_LOCAL="${SCRIPT_DIR}/../../../../.env"  # Go two levels up
else
    # We are in the package's own directory (script used by the maintainer)
    ENV_LOCAL="${SCRIPT_DIR}/../.env"
fi



# Now source the .env file if it exists
if [ -f "$ENV_LOCAL" ]; then
    source "$ENV_LOCAL"
else
    echo "Warning: .env file not found at $ENV_LOCAL"
    exit 1
fi



# Source the gitlab_functions.sh script using the resolved path
source "${SCRIPT_DIR}/gitlab_functions.sh"
# select_gitlab_issue



# Determine the root directory of the Git repository
REPO_ROOT=$(git rev-parse --show-toplevel)

if [[ -z "$REPO_ROOT" ]]; then
    echo "Error: This script must be run within a Git repository."
    exit 1
else
    cd "$REPO_ROOT"
fi



# Check git cli
if ! command -v git &> /dev/null
then
    echo "git could not be found, please install."
    exit
fi



# Ask for confirmation of the branch
current_branch=$(git rev-parse --abbrev-ref HEAD)
echo "You are currently on branch: $current_branch"
echo "Is this the branch you want to deploy? (Y/n) [y]"
read -r branch_confirmation

# If no input (enter pressed), set the default to 'y'
if [[ -z "$branch_confirmation" ]]; then
    branch_confirmation="y"
fi

if [[ "$branch_confirmation" != "y" ]]; then
    echo "Please switch to the correct branch and run the script again (git checkout branch_name)."
    exit 1
fi



# Review current status
echo "Do you want to review your pending (uncommitted) changes? (Y/n) [y]"
read -r pending_confirmation

# If no input (enter pressed), set the default to 'y'
if [[ -z "$pending_confirmation" ]]; then
    pending_confirmation="y"
fi

if [[ "$pending_confirmation" == "y" ]]; then
    git config --global core.autocrlf true

    # List uncommitted changes
    echo "Checking for uncommitted changes..."
    UNCOMMITTED_FILES=$(git status --porcelain)

    if [[ -z "$UNCOMMITTED_FILES" ]]; then
        echo "No uncommitted changes found."
    else
        echo "Uncommitted changes found:"
        echo "$UNCOMMITTED_FILES"

        # Ask the user for each file if they want to add it to the index
        IFS=$'\n'
        for file in $UNCOMMITTED_FILES; do
            file_path=$(echo $file | awk '{print $2}')
            read -p "Do you want to add $file_path to the index? (y/n) [n] " add_confirm
            add_confirm=${add_confirm:-n}

            if [[ "$add_confirm" == "y" ]]; then
                git add "$file_path"
                echo "$file_path added to index."
            fi
        done
        unset IFS

        # Check if anything was added to the index
        if git diff --cached --quiet; then
            echo "No changes added to index for commit."
        else
            echo "Refreshing git index..."
            git status
            select_gitlab_issue
        fi

    fi
fi



# Get local Git remotes
# echo "Fetching local Git remotes..."
LOCAL_REMOTES=($(git remote))
if [[ ${#LOCAL_REMOTES[@]} -eq 0 ]]; then
    echo "No Git remotes found."
    exit 1
fi



# Select a remote
echo ""
echo "Available Git remotes to push to:"
PS3="Select a remote to push to (enter the number): "
select selected_remote in "${LOCAL_REMOTES[@]}"
do
    if [[ -n "$selected_remote" ]]; then
        break
    else
        echo "Invalid selection. Please try again."
    fi
done



# Check for unpushed commits
echo "Checking for pending commits to send to $selected_remote..."
PENDING_COMMITS=$(git log $selected_remote/$(git rev-parse --abbrev-ref HEAD)..HEAD --oneline)
if [[ -z "$PENDING_COMMITS" ]]
then
    echo "No pending commits found to push."

    # Get the details of the last commit
    LAST_COMMIT_DETAILS=$(git log -1 --format="%cd %h %ae %s" --date=format:'%Y-%m-%d %H:%M:%S')
    echo "Current state: $LAST_COMMIT_DETAILS"
    echo ""
    echo "Do you want to deploy it to a remote server (y/n) [y]?"
    read -r deploy_confirmation

    # If no input (enter pressed), set the default to 'y'
    if [[ -z "$deploy_confirmation" ]]; then
        deploy_confirmation="y"
    fi

    if [[ "$deploy_confirmation" != "y" ]]; then
        exit 1
    fi
else
    echo "Pending commits to be pushed:"
    echo "$PENDING_COMMITS"
    echo "Do you want to continue and push these commits to $selected_remote? (y/n) [y]"
    read user_confirm

    if [[ -z "$user_confirm" ]]; then
        user_confirm="y"
    fi

    if [[ "$user_confirm" != "y" ]]; then
        echo "Push cancelled."
        exit 1
    else
        echo "Executing git push to $selected_remote..."
        git push $selected_remote $(git rev-parse --abbrev-ref HEAD)
        echo "Push operation completed."
        echo ""
    fi
fi



# Remotes listed in the config file
echo "Select the remote host from your .env where you want to deploy ${selected_remote}/${current_branch}"

REMOTES=`cat $ENV_LOCAL | grep REMOTES |  cut -d "=" -f2-`
if [[ -z "$REMOTES" ]]
then
    echo "\$REMOTES is empty"
    exit 1
fi

PS3="Choice number: "
REMOTES=`echo $REMOTES | tr -d '"'`
select REMOTE in $REMOTES
do
    echo "Selected remote: $REMOTE"
    break
done



# Get the variables for the selected remote
VARS=("DIR" "HOST" "PORT" "USER")

for VAR in ${VARS[@]}; do
    declare "SSH_${VAR}"=`cat $ENV_LOCAL | grep "${REMOTE}_SSH_${VAR}" |  cut -d "=" -f2-`
done

echo ""
echo "SSH_DIR  : $SSH_DIR"
echo "SSH_HOST : $SSH_HOST"
echo "SSH_PORT : $SSH_PORT"
echo "SSH_USER : $SSH_USER"

echo ""
while true; do
    echo "Do you want to continue and pull ${selected_remote}/${current_branch} on ${SSH_HOST} in ${SSH_DIR}? (y/n) [y]"
    read -r direction_confirmation

    # If no input (enter pressed), set the default to 'y'
    if [[ -z "$direction_confirmation" ]]; then
        direction_confirmation="y"
    fi

    # Check if the input is either 'y' or 'n'
    if [[ "$direction_confirmation" == "y" ]]; then
        echo "Deploying..."
        break
    elif [[ "$direction_confirmation" == "n" ]]; then
        echo "Deployment cancelled."
        exit 1
    else
        echo "Invalid input. Please enter 'y' for yes or 'n' for no."
    fi
done



# Define the SSH server and path details
SSH_SERVER="${SSH_USER}@${SSH_HOST}"

# Simply test the connexion
# SSH to the server and execute commands
# ssh -t -p $SSH_PORT $SSH_SERVER "
#     echo 'Changing to directory: $SSH_DIR';
#     cd $SSH_DIR;
#     echo 'Reading from remote server...';
#     whoami;
#     pwd;
# "



# Proceed to deployment using git
ssh -t -p $SSH_PORT $SSH_SERVER "
    echo 'Connected to ${SSH_SERVER}...';
    cd $SSH_DIR;
    echo 'Performing remote git pull in ${SSH_DIR}...';
    git pull;
    exit;
"


# End of script
echo "End of script."
