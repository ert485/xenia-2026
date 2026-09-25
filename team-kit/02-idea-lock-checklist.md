# Idea-lock checklist

Teammate: ten minutes, spoken, right after the idea vote. One person reads each question aloud and everyone answers. The answers are recorded as one line per person **in a private Discord channel, never in a repo**, and that channel is deleted a week after the retro.

Money, IP, and roles are asked out loud and answered by each person, yes or no. Silence is not a yes.

| # | Question | Default if everyone agrees | How it's answered |
|---|---|---|---|
| 1 | Stack: TypeScript or Python? | none: asked, not defaulted | the team picks one |
| 2 | Prize split | equal among everyone registered at idea lock; leaving early keeps your share if you say goodbye in Discord | each person: yes or no, aloud |
| 3 | License and IP | MIT, co-owned by everyone who contributes | each person: yes or no, aloud |
| 4 | Are you free to contribute? | students and employees may be bound by a school or employer IP policy; check before you say yes | each person confirms, aloud |
| 5 | Repo public? | yes | the team decides |
| 6 | Product owner | whoever pitched the winning idea | the team decides |
| 7 | Owners of PRINCIPLES.md (two or three) | people who volunteer | the team names them |
| 8 | Area ownership (frontend, API, data, demo) | one owner per area, from the sign-up sheet's skills | the team decides |
| 9 | Night-shift slots (23:00 to 07:00, three-hour blocks) | drawn from the sign-up sheet's sleep plans | each named person: yes or no |
| 10 | Team channel | Discord (text and voice), tasks as GitHub issues | the team decides |

## Row 10: which channels agents can use

Agents run inside the dev container and should reach the team as easily as teammates do.

| Option | For agents |
|---|---|
| GitHub issues and PR comments | structured and already permitted |
| Discord | a webhook for posting (one line, `/notify`); a bot token if agents must also read |
| Slack | needs an app installed in the workspace |
| Anything phone-based | humans only |

## What gets recorded

One line per person in the private channel, for example: `Alex: split yes, MIT yes, free to contribute yes, night slot 02:00 yes`. Nothing from this page goes into the repo, an issue, or a PR.
