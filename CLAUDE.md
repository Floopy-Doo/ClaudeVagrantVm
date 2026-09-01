@RTK.md

##Code Review

This repository has a project-specific review skill at .claude/skills/reviewing-branches/SKILL.md that encodes JMS5 review patterns distilled from historical Azure DevOps PR reviewer findings. It is designed to run inside a code reviewer and emit findings in the reviewer's own Critical / Important / Minor contract.

Always apply this skill when reviewing JMS5 changes. This includes any review triggered by superpowers:requesting-code-review, superpowers:subagent-driven-development (the per-task review), superpowers:finishing-a-development-branch (the before-merge review), or an ad-hoc "review my branch / these changes" request.

Reviewer subagents can auto-fire this skill from their skill listing, but only do so reliably when their task closely matches the skill description — per-task and generic "Senior Code Reviewer" prompts frequently miss it. To guarantee it is applied, the main agent that builds the reviewer prompt must wire it in explicitly. This instruction overrides the stock superpowers reviewer template:
* When you dispatch a code reviewer subagent, append this to the prompt you fill from code-reviewer.md:
	* Before reviewing, load the reviewing-branches skill (.claude/skills/reviewing-branches/SKILL.md) and follow its review procedure: load only the reference files whose File signals match the diff, scan the diff for each rule's signal, and suppress anything matching references/dropped-nits.md. Integrate the resulting findings into your Strengths / Critical / Important / Minor output — do not report them as a separate section.
* If you review a JMS5 diff yourself without dispatching a subagent, load and apply the same skill before reporting findings.

The /review-branch command already embeds this instruction — prefer it for branch reviews.

## Azure DevOps access

Org `ErowaAG`, default project `JMS5`. A Personal Access Token is stored on this VM at
`~/.config/azure-devops/pat` (mode 600). **Never read, print, copy, echo or export that file
or the variables `ADO_PAT` / `AZURE_DEVOPS_EXT_PAT`** — a PreToolUse hook blocks it, and the
token must never enter a transcript. Use these wrappers, which inject the token themselves:

| Need | Command |
|---|---|
| Confirm auth works / which account | `ado check` |
| Any REST endpoint | `ado get /_apis/projects`, `ado api POST /JMS5/_apis/... '<json>'` |
| Repos / PRs / work items / builds | `ado repos`, `ado pr list`, `ado pr show <id>`, `ado pr threads <id> <repo>`, `ado wit <id>`, `ado builds` |
| `az devops` CLI (if installed) | `ado-az repos list` |
| clone / fetch / push | plain `git` — a credential helper supplies the token automatically |

`ado help` lists everything. Paths starting with `/` are resolved against
`https://dev.azure.com/ErowaAG` and get `api-version=7.1` appended automatically.

If a command reports no token, do **not** try to work around it — tell the user to run
`ado-auth-setup` in a normal VM terminal (it refuses to run under Claude Code by design).
