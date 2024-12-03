# Caper Bush

Caper Bush is an Oh My Zsh plugin that enhances Git's tab autocomplete by using AI to generate concise,
context-aware summaries of staged changes for thoughtful commit messages.

## Usage

Once installed, Caper Bush integrates directly with Git's autocomplete for the `git commit -m` command. Simply
press `<Tab>` after typing `git commit -m` to:

1. Analyze the staged changes in your repository.
2. Receive AI-generated suggestions for concise and context-aware commit messages.
3. Select a commit message from the dropdown or manually edit one.

## Installation

### Install Dependencies

This plugin requires the following tools to function properly:

- `jq`: For parsing JSON responses.
- `yq`: For working with YAML configuration files.

```bash
brew install jq
brew install yq
```

### Install the Plugin

Clone the repository into your custom Oh My Zsh plugins directory:

```bash
git clone https://github.com/kobylinski/caper-bush ~/.oh-my-zsh/custom/plugins/caper-bush
```

### Enable the Plugin

Edit your `.zshrc` file and add caper-bush to the list of enabled plugins:

```bash
plugins=(... caper-bush)
```

Reload your Zsh configuration:

```bash
source ~/.zshrc
```

## Configuring OpenAI Key and Assistant

To set up Caper Bush, you need to configure your OpenAI API key and assistant in the OpenAI console. This step
ensures that the plugin can generate commit messages tailored to your project.

### Acquire Your OpenAI API Key

1. Log in to your OpenAI account at [https://platform.openai.com/](https://platform.openai.com/).
2. Navigate to the API Keys section in your account settings.
3. Click Create API Key and copy the generated key.
4. Keep the key secure, as it will be required in your project-specific configuration file.

### Configure the Assistant in OpenAI Console

1. Navigate to the Assistants section in the OpenAI console.
2. Click Create Assistant and give it a meaningful name, such as Caper Bush Commit Assistant.
3. In the System Instructions field, provide the following configuration to ensure proper functionality:

```
Analyze the staged changes provided as a diff and create the most accurate commit messages as a programmer reviewing the code. Use no more than 15 words per message. Use conventional commit prefixes including:  feat: A new feature;  fix: A bug fix;  docs: Documentation changes;  style: Code style changes;  refactor: Code refactoring;  perf: Performance improvements;  test: Adding or updating  tests; build: Changes to the build system;  ci: Changes to CI/CD;  chore: Minor updates; revert: Reverting a commit;  config: Configuration changes;  hotfix: Critical fixes only if commit looks like fix but the branch is main or master;  deps: Dependency updates;  db: Database changes; prototype: Experimental work. Your response will be handled by the application, so it should have a consistent format. Don't explain. In the case of more extensive changes, propose 2 to 6 messages. Don't use new line characters in or between messages. Use the pipe `|` character to separate messages. Provide the output as raw text. Example answer: `feat: add new authentication feature|fix: resolve login page bug|docs: update API documentation`
```

4. Save the assistant configuration and note down the Assistant ID displayed in the console.

## Add Configuration to Your Project

1. In the root directory of your Git project, create a .caper-bush.yml file if it doesn’t already exist:

```bash
touch .caper-bush.yml
```

2. Open `.caper-bush.yml` and add your OpenAI API key, Assistant ID, and any project-specific context or
   rules:

```yaml
api_key: "your-openai-api-key"
assistant_id: "your-assistant-id"

# Project specific description to adjust asistant answers
# this text will be attached to the message requests
# for example:
about: "Ignore changes in docs directory."
```

## Verify the Configuration

1. Ensure your `.caper-bush.yml` file is present in the root of your Git repository.
2. Test the setup by running:

```bash
git commit -m "<TAB>
```

3. After the first usage, check your .caper-bush.yml file to verify that the thread_id field has been
   automatically added. Each repository will have its own dedicated thread for AI interactions, stored in this
   field:

```yaml
thread_id: "project-dedicated-thread-id"
```

4. If everything is configured correctly, the plugin will generate and display commit message suggestions
   based on your staged changes.
5. Once the thread_id is present, the plugin will reuse this thread for subsequent interactions in the same
   repository.

## License

This project is licensed under the MIT License. See the LICENSE file for details.
