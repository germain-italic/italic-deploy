#!/bin/bash

# Check jq cli
if ! command -v jq &> /dev/null
then
    echo "jq could not be found, please install."
    exit
fi



# Configuration
GITLAB_API_URL=`cat $ENV_LOCAL | grep GITLAB_API_URL |  cut -d "=" -f2-`
GITLAB_API_TOKEN=`cat $ENV_LOCAL | grep GITLAB_API_TOKEN |  cut -d "=" -f2-`
SCOPE=`cat $ENV_LOCAL | grep SCOPE |  cut -d "=" -f2-`
STATE=`cat $ENV_LOCAL | grep STATE |  cut -d "=" -f2-`
LABEL=`cat $ENV_LOCAL | grep LABEL |  cut -d "=" -f2-`
LIMIT=`cat $ENV_LOCAL | grep LIMIT |  cut -d "=" -f2-`
ORDER=`cat $ENV_LOCAL | grep ORDER |  cut -d "=" -f2-`
SORT=`cat $ENV_LOCAL | grep SORT |  cut -d "=" -f2-`
GITLAB_PROJECT_IDS=`cat $ENV_LOCAL | grep GITLAB_PROJECT_IDS |  cut -d "=" -f2-`
IFS=',' read -r -a GITLAB_PROJECT_IDS_ARRAY <<< "$GITLAB_PROJECT_IDS"
# echo "${GITLAB_PROJECT_IDS_ARRAY[0]}"
# echo "${GITLAB_PROJECT_IDS_ARRAY[1]}"


# Fetch issues from GitLab
fetch_gitlab_issues() {
    local GITLAB_PROJECT_ID=$1
    endpoint="$GITLAB_API_URL/projects/$GITLAB_PROJECT_ID/issues"
    params="labels=$LABEL&state=$STATE&scope=$SCOPE&per_page=$LIMIT&order_by=$ORDER&sort=$SORT"
    request="${endpoint}?${params}"
    # echo "Request: $request"
    curl -s --header "PRIVATE-TOKEN: $GITLAB_API_TOKEN" "$request"
}



# Handle mandatory commit message input
COMMIT_MESSAGE=""
get_commit_message() {
    local message=""
    while true; do
        read -p "$1" message
        if [[ ! -z "$message" ]]; then
            COMMIT_MESSAGE="$message"
            break  # Exit the loop after getting a custom message
        else
            echo "Commit message cannot be empty."
        fi
    done
}



# Select a GitLab issue and form a commit message
select_gitlab_issue() {
    while true; do
        # Fetch issues and present a selection to the user
        echo "Fetching issues from GitLab..."

        ISSUES=""
        error_message=""

        # Iterate through each project ID
        for project_id in "${GITLAB_PROJECT_IDS_ARRAY[@]}"; do
            project_issues=$(fetch_gitlab_issues "$project_id")

            # Append the fetched issues to the cumulative list
            ISSUES+="$project_issues"
            ISSUES+=$'\n' # Add a newline between issues from different projects

            if jq -e 'type == "object" and has("error")' <<< "$json_string" > /dev/null; then
                error_message=$(jq -r '.error' <<< "$project_issues")
                if [ -n "$error_message" ] && [ "$error_message" != "null" ]; then
                    echo "GitLab API returned error: $error_message"
                fi
            fi
        done

        # echo "Raw JSON Data:"
        # echo "$ISSUES"
        # echo "Processed JSON with jq:"
        # echo "$ISSUES" | jq -r '.[] | .web_url'


        while true; do
            if [[ -z "$error_message" ]]; then
                echo "Select an issue for the commit message:"

                # Display issues in a formatted table
                printf "\n%3s | %-80s | %s\n" "ID" "Title" "URL"
                printf "%s\n" "------------------------------------------------------------------------------------------------------------------"

                # Parse JSON and display issues in a table format
                echo "$ISSUES" | jq -r '.[] | "\(.iid) \(.title|gsub("[éèêë]";"e")|gsub("[î]";"i")|gsub("[àâä]";"a")|gsub("[ûüù]";"u")|gsub("[ôö]";"o")|gsub("[ç]";"c")) \(.web_url)"' | while IFS= read -r line
                do
                    ID=$(echo "$line" | awk '{print $1}')
                    URL=$(echo "$line" | awk '{print $NF}')
                    TITLE=$(echo "$line" | awk '{$1=""; $NF=""; print $0}' | sed 's/^[ \t]*//')

                    # Use printf to format the columns correctly
                    printf "%-3s | %-80.80s | %s\n" "$ID" "${TITLE:0:78}" "$URL"
                done

                # Capture user selection
                read -p "Enter issue number or type a custom message: " issue_number
            else
                # Capture user selection
                read -p "Type a custom message: " issue_number
            fi



            # Check if input is empty
            if [[ -z "$issue_number" ]]; then
                # Prompt for a custom message if the input is empty
                get_commit_message "Enter a custom commit message: "
                echo "Custom commit message set to: $COMMIT_MESSAGE"
                break  # Exit the loop after getting a custom message
            else
                if [[ $issue_number =~ ^[0-9]+$ ]]; then
                    # Check if the input is a valid issue number
                    issue_title=$(echo "$ISSUES" | jq -r --arg num "$issue_number" '.[] | select(.iid == ($num | tonumber)) | .title')

                    if [[ ! -z "$issue_title" ]]; then
                        echo "You selected issue number #${issue_number} - $issue_title"
                        get_commit_message "Enter additional message to append to the commit message: "
                        COMMIT_MESSAGE="#${issue_number} - ${issue_title} - ${COMMIT_MESSAGE}"
                        break  # Exit the loop after processing a valid issue number
                    else
                    echo ""
                        echo "Issue $issue_number is not valid. Enter an issue number from the list or a custom commit message."
                        echo "If you don't see the issue you are working on, make sure that the ticket is assigned to you."
                    fi
                else
                    # Treat non-empty input as a custom message
                    COMMIT_MESSAGE="$issue_number"
                    break  # Exit the loop as the user has entered a custom message
                fi
            fi


        done

        # Output the final commit message for confirmation
        echo "Final commit message will be: $COMMIT_MESSAGE"

        # Ask user to confirm or restart
        echo "Do you want to commit with this message or edit? (commit/edit) [commit]"
        read -r action_choice

        if [[ -z "$action_choice" ]] || [[ "$action_choice" == "commit" ]]; then
            break
        elif [[ "$action_choice" == "edit" ]]; then
            echo "Restarting the process..."
            continue
        else
            echo "Invalid input. Defaulting to commit."
            break
        fi
    done

    # Proceed with the commit
    echo "Committing changes..."
    git commit -m "$COMMIT_MESSAGE"
    echo "Changes committed."
}
