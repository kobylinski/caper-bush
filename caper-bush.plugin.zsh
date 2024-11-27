# CaperBush Zsh Plugin

# Function triggered by autocompletion for `git commit -m "<tab>`
_caper_bush_command() {

  # Provide the array to compadd  
  local git_command=${words[2]}
  local git_flag=${words[3]}

  # Check if the command is `git commit --message=`
  if [[ $git_command != "commit" || $git_flag != "-m"*  ]]; then
    return 1
  fi

  local project_root=$(git rev-parse --show-toplevel)
  local rules_file="$project_root/.caper-bush.yml"

  # No rules file found in project root directory, no need to proceed
  if [[ ! -f $rules_file ]]; then
    return 1
  fi

  local api_key=$(yq ".api_key" $rules_file)
  local assistant_id=$(yq ".assistant_id" $rules_file)
  local thread_id=$(yq ".thread_id" $rules_file)
  local about=$(yq ".about" $rules_file)
  
  # Check if required fields are set, if not, return error
  if [[ -z $api_key || -z $assistant_id || $api_key == "null" || $assistant_id == "null" ]]; then
    echo "\n\n\033[0;31m✘ API key and assistant ID are required in .caper-bush.yml\033[0m\n\n"
    return 1
  fi

  if [[ -z $thread_id || "$thread_id" == "null" ]]; then
    local thread_response=$(curl -s -X POST https://api.openai.com/v1/threads \
      -H "Content-Type: application/json" \
      -H "Authorization: Bearer $api_key" \
      -H "OpenAI-Beta: assistants=v2" \
      -d '{
        "metadata": { "project": "'"${project_root##*/}"'" }
      }')

    thread_id=$(echo "$thread_response" | jq -r '.id')

    # Check if thread was created successfully
    if [[ -z $thread_id || $thread_id == "null" ]]; then
      echo "\n\n\033[0;31m✘ Unable to create thread. Please check your API key and assistant ID.\033[0m\n\n"
      return 1
    fi

    yq -i '.thread_id = "'"$thread_id"'"' $rules_file
  fi
  
  # Extract the message from the command
  local command="${git_command#--message=}"
    
  # Check for staged changes
  local staged_files=$(git diff --cached --name-only)
  if [[ -z $staged_files ]]; then
    printf "No staged changes found."
    return 1
  fi

  # Generate diff of staged changes
  local git_diff=$(git diff --cached)


  # Prompt to send to OpenAI API
  local initial_message="### Additional Project Information:\n$about\n\n### Diff:\n$git_diff"
  local escaped_message=$(printf "%s" "$initial_message" | jq -Rs '.')

  # Send the message to the OpenAI API thread
  local message_response=$(curl -s -X POST https://api.openai.com/v1/threads/$thread_id/messages \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer $api_key" \
    -H "OpenAI-Beta: assistants=v2" \
    -d '{
        "role": "user",
        "content": '"$escaped_message"'
      }')
  
  # Call assistant to generate a response to the message
  local create_run_response=$(curl -s -X POST https://api.openai.com/v1/threads/$thread_id/runs \
    -H "Authorization: Bearer $OPENAI_API_KEY" \
    -H "Content-Type: application/json" \
    -H "OpenAI-Beta: assistants=v2" \
    -d '{
      "assistant_id": "'"$assistant_id"'"
    }')

  # Extract the run ID from the response
  local run_id=$(printf "%s" "$create_run_response" | jq -r '.id')

   # Poll for the assistant's response
  local response=""
  local response_status=""
  local counter=0
  while true; do
    response=$(curl -s -X GET https://api.openai.com/v1/threads/$thread_id/runs/$run_id \
      -H "Content-Type: application/json" \
      -H "Authorization: Bearer $api_key" \
      -H "OpenAI-Beta: assistants=v2")

    response_status=$(printf '%s' "$response" | jq -r '.status')
    if [[ "$response_status" == "completed" ]]; then
      break
    fi
    if (( counter > 10 )); then
      return 1
    fi
    sleep 2
    (( counter++ ))
  done

  # Fetch the the latest message from the thread to get the assistant's response
  local messages=$(curl -s -X GET "https://api.openai.com/v1/threads/$thread_id/messages?limit=1&run_id=$run_id" \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer $api_key" \
    -H "OpenAI-Beta: assistants=v2")

  # Extract the assistant's response from the messages
  local assistant_reply=$(printf "%s" "$messages" | jq -r '.data[0].content[0].text.value' | sed 's/```//g' | tr -d "\n")

  # Output assistant's response as an autocomplete suggestion
  if [[ -n "$assistant_reply" ]]; then

    # Split the messages into an array using | as a delimiter
    local -a messages_array=(${(s:|:)assistant_reply})
    compadd -X 'Choose your message' -- "${messages_array[@]}"
  else
    return 1
  fi

  return 0
}

# Add autocompletion for `git commit --message=`
compdef _caper_bush_command git

