You are starting a new jira story $ARGUMENTS. before coming up with a plan for the story. YOU MUST follow the steps below strictly in order.
1. update the base to latest
2. create a new worktree in the directory .worktrees/ with the name of the jira story id. ASK ME before running this command
3. use summoner to find an available dev environment. do not offer staging or intergration. if one is avaiable ASK ME before claiming it. if there is not one available ASK ME to choose an env to assign this story too with the expectation to claim this env at a later point.
4. run `aws-vault exec cvr-dev` and wait till this command has completed
5. run the script write_env_config with the param on the chosen env
6. .env.production to .env

once you have completed this list. read the jira ticket and come up with a suggestion to resolve this story.