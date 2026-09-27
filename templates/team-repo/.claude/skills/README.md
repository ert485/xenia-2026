# Repo skills

Teammate: a skill is a short instruction file that Claude Code loads when its description matches the task.
Anything the team does twice becomes one (P-skills).

- **Repo-specific skills go here**, one folder each: `.claude/skills/<name>/SKILL.md`. They load only in this
  repo. `example-repo-skill/` is a working example to copy.
- **Skills every team could use go to the kit plugin** (`plugin/skills/` in https://github.com/ert485/xenia-2026)
  by PR. The vendored copy in this repo's `plugin/` is refreshed by the kit, so don't edit it here.

A `SKILL.md` starts with front matter:

    ---
    name: <folder name>
    description: Use when <the situation, in the words a teammate would use>
    ---

Then the body. Start instructions for agents with "Agent:" and call the human "the teammate" (P-who). Keep it
under a page; link to files in the repo rather than copying them.

`.claude/skills/` is a normal folder, so changes go through PRs like any other file.
