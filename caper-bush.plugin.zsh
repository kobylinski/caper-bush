# CaperBush Zsh Plugin

caper_bush_get_messages() {

  local project_root=$(git rev-parse --show-toplevel 2>/dev/null)
  if [[ -z $project_root ]]; then
    return 1
  fi
  local rules_file="$project_root/.caper-bush.yml"

  # No rules file found in project root directory, no need to proceed
  if [[ ! -f $rules_file ]]; then
    return 1
  fi

  local api_key=$(yq ".api_key" $rules_file)
  local assistant_id=$(yq ".assistant_id" $rules_file)
  local thread_id=$(yq ".thread_id" $rules_file)
  local about=$(yq ".about" $rules_file)
  local debug_file=$(yq ".debug" $rules_file | sed 's|^~|'"$HOME"'|')
  local debug=false
  
  if [[ -z $debug || $debug == "null" ]]; then
    debug=false
  else 
    debug=true
    if [[ ! -f $debug_file ]]; then
      touch $debug_file
    fi
    echo "---------------------------------------------------------" >> $debug_file
    echo "Project: ${project_root##*/}" >> $debug_file
    echo " * API Key: $api_key" >> $debug_file
    echo " * Assistant ID: $assistant_id" >> $debug_file
    echo " * Thread ID: $thread_id" >> $debug_file
    echo " * About: $about" >> $debug_file
  fi
  
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

    if [[ $debug == true ]]; then
      echo "Thread Response: $thread_response" >> $debug_file
    fi

    thread_id=$(echo "$thread_response" | jq -r '.id')

    # Check if thread was created successfully
    if [[ -z $thread_id || $thread_id == "null" ]]; then
      echo "\n\n\033[0;31m✘ Unable to create thread. Please check your API key and assistant ID.\033[0m\n\n"
      return 1
    fi

    yq -i '.thread_id = "'"$thread_id"'"' $rules_file
  fi

  # Check for staged changes
  local current_commit=$(git rev-parse HEAD)
  local staged_files=$(git diff --cached --name-only)
  if [[ -z $staged_files ]]; then
    return 1
  fi

  # Generate diff of staged changes
  local git_diff=$(git diff --cached)

  # Combine the commit hash and the staged diff
  local combined_state="${current_commit}\n${git_diff}"
  local unique_state=$(echo -n "${combined_state}" | shasum | awk '{print $1}')
  local cache_file="$ZSH_CACHE_DIR/caper-bush/$unique_state"

  if [[ -d "$ZSH_CACHE_DIR/caper-bush" ]]; then
    if [[ -f $cache_file ]]; then
      cat $cache_file
      return 0
    fi
  else
    mkdir -p "$ZSH_CACHE_DIR/caper-bush"
  fi

  # Create cache file
  touch $cache_file

  # Prepare message to send to OpenAI API
  local initial_message="### Additional Project Information:\n$about\n\n### Diff:\n$git_diff"
  local escaped_message=$(printf "%s" "$initial_message" | jq -Rs '.')

  # Send the message to the OpenAI API thread
  curl -s -X POST https://api.openai.com/v1/threads/$thread_id/messages \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer $api_key" \
    -H "OpenAI-Beta: assistants=v2" \
    -d '{
        "role": "user",
        "content": '"$escaped_message"'
      }' > /dev/null

  # Trigger assistant run
  local create_run_response=$(curl -s -X POST https://api.openai.com/v1/threads/$thread_id/runs \
    -H "Authorization: Bearer $api_key" \
    -H "Content-Type: application/json" \
    -H "OpenAI-Beta: assistants=v2" \
    -d '{
      "assistant_id": "'"$assistant_id"'"
    }')

  if [[ $debug == true ]]; then
    echo "Create Run Response: $create_run_response" >> $debug_file
  fi

  # Extract run ID
  local run_id=$(echo "$create_run_response" | jq -r '.id')

  # Poll for the assistant's response
  local response_status=""
  local counter=0
  while true; do
    local response=$(curl -s -X GET https://api.openai.com/v1/threads/$thread_id/runs/$run_id \
      -H "Content-Type: application/json" \
      -H "Authorization: Bearer $api_key" \
      -H "OpenAI-Beta: assistants=v2")

    if [[ $debug == true ]]; then
      echo "Pool response: $response" >> $debug_file
    fi

    response_status=$(echo "$response" | jq -r '.status')
    if [[ "$response_status" == "completed" ]]; then
      break
    fi
    if (( counter > 10 )); then
      return 1
    fi
    sleep 2
    (( counter++ ))
  done

  # Fetch the messages
  local messages_response=$(curl -s -X GET "https://api.openai.com/v1/threads/$thread_id/messages?run_id=$run_id" \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer $api_key" \
    -H "OpenAI-Beta: assistants=v2")

  if [[ $debug == true ]]; then
    echo "Messages Response: $messages_response" >> $debug_file
  fi

  local messages=$(echo "$messages_response" | jq -r '.data[0].content[0]?.text.value')

  if [[ -z $messages ]]; then
    return 1
  fi

  messages=$(echo "$messages" | sed 's/```//g' | tr -d '\n')
  local splited_messages=(${(@s:|:)messages})
  for message in $splited_messages; do
    local trimmed_message=$(echo "$message" | sed 's/^[ \t]*//;s/[ \t]*$//')
    local word_count=$(echo "$trimmed_message" | wc -w)
    if (( word_count <= 10 )); then
      echo "$trimmed_message"
      echo "$trimmed_message" >> $cache_file
    fi
  done

  return 0
}

# Function triggered by autocompletion for `git commit -m "<tab>`
_caper_bush_command() {
    _arguments -C \
      "1: :(commit)" \
      '-m[Specify commit message]:message:->message'

    case $state in
      (message)
        local -a messages
        messages=("${(@f)$(caper_bush_get_messages)}")
        if [[ $? -ne 0 ]]; then
          return 1
        fi
        messages=("${(@)messages//:/\\:}")
        _describe -t messages 'Choose your message' messages
        return 0
      ;;
    esac

    # Fallback to default git completion for other commands
    _git && return 0
}
compdef _caper_bush_command git



