# The rules, extended

Every entry below names the core line in `PRINCIPLES.md` it serves and says why. If you have read only
the core, nothing here should surprise you; if something does, that is a bug in one of the two files,
and the bot's consistency review is there to catch it.

## Under P-ours

- **P-who: name who you mean.** Humans and agents share the same channels, so "you", "I", "the AI",
  and "the system" are ambiguous. Every page, prompt, skill, issue template, and bot comment says which
  of these it addresses: *teammate* (a human on the team), *Erik*, *agent* (a Claude Code or OpenCode
  session a teammate is running), *bot* (the CI reviewer or the pain-review run), *gateway*, *model*,
  *kit*. Instructions for agents start with "Agent:".
- **Changing P-ours itself, or who the owners are, takes two owners**, not one.
- **The ruleset is honour system at the top.** The repo admin could edit the branch ruleset outside
  git. We are saying so rather than pretending otherwise.
- **Rule feedback goes in one place**: the `Rule-feedback:` line of your PR, or `/rule-feedback` when
  there is no PR. We look at the pile for five minutes at the 18:00 checkpoint and again at the retro.
  Per rule there are three outcomes: keep it, change it by PR, or bring the exceptions back in line.
  Three sightings of the same rule mean we review that rule as a whole, not each exception.

## Under P-fix-once

- **P-comms: agents can talk to the team as easily as teammates do.** Whatever channel we pick at idea
  lock gets an agent path on day one: `/notify <message>` posts to it, the dev container can reach it,
  and the pain-review recommendation lands there too. Which tools are easy for agents: GitHub issues
  and PR comments are structured and already permitted; Discord takes a webhook for posting in one
  line, and a bot token if agents must also read; Slack needs an app; anything phone-based is for
  humans only.
- **P-fix-once/claude-md: write the workaround down.** `CLAUDE.md` records every workaround anyone
  finds, so no agent rediscovers it.
- **P-skills: done twice, it becomes a skill.** Shared ones go into the kit plugin by PR;
  repo-specific ones go in `.claude/skills/`.

## Under P-two-gates

- **P-contracts: where there is an API, the spec is the source.** Types are generated from it and
  boundaries validate against it, so a mismatch fails loudly instead of in the demo.
- **P-evals: if we ship an LLM feature and touch its prompt more than twice, the eval comes first.**
- **P-real-url: a real URL by 13:00.** Everything after that is iteration on something people can open.

## Under P-simple

- **Why: every piece is something the next person has to read.** Every file, layer, and option is
  something the next teammate or agent must understand before changing anything, often overnight and
  often on the shared model, which does best on scoped tasks. Fewer moving parts make each later
  change quicker and safer, and that is worth a slower start.
- **P-simple/second-use: small means few moving parts, not many files.** Split a piece when it does
  two jobs, not to make it shorter. Add a helper, layer, interface, or config option only when a
  second real use needs it.
- **P-simple/moving-parts: a new moving part says why.** A queue, a cache, a second database, or a
  background worker gets one sentence in the PR on why the plain version fails.
- **P-simple/pushback: pushing back is a proposal, not a veto.** The agent names the simpler option
  and what it gives up, and the teammate picks. An agent never quietly drops part of what was asked,
  and "build it as asked" ends the discussion.
- **The bot's review lists unrequested complexity** (an abstraction with one caller, an option
  nothing sets, a layer that only forwards calls) under probable rule exceptions. It advises; it never
  blocks a merge.

## Under P-off-switch

- **P-no-clickops: if it can be code, it's code.** Console work gets a `Rule-feedback:` line so it can
  be imported or destroyed later.

## Under P-wheel

- **P-clock: bots hold the clock.** Freeze reminders and pain ranking come from automation, not from
  whoever is most awake.

## Under P-public

- **P-public/commit**: commit code, templates, and placeholders only. Account IDs, zone IDs, keys,
  phones, and emails go in gitignored files, SSM, or Codespaces secrets. Push protection and `gitleaks`
  catch the rest; a false positive gets a `Rule-feedback:` line, never a bypass.
- **P-public/site**: the kit site shows only what a stranger may see, and its build fails on anything
  that looks like an ID, a portal URL, a phone number, or an unlisted email.
- **P-public/contacts**: contact details stay on paper or in a private channel and are deleted a week
  after the retro.
- **P-public/leak**: a leaked key is an incident, not a mistake to hide. Post it, run
  `scripts/rotate-key.sh`, then fix the path that leaked it, once.
- **P-public/agents**: agents may post summaries, diffs, in-repo paths, and redacted errors. They never
  paste environment variables, tokens, transcripts, or logs with emails or IP addresses into an issue
  or PR, and a teammate confirms before `/pain` or `/rule-feedback` posts anything.
- **P-public/ci**: no workflow runs with secrets or cloud access on content from outside the team.

## How the rules reach you

- Your Claude Code session in the dev container starts with the core rules already in its context.
- Only `make check` and shutdown coverage block a merge.
- Exceptions go in the `Rule-feedback:` line of your PR or in `/rule-feedback`, and we look at the pile
  at 18:00 and at the retro.