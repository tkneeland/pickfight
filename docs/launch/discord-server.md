# Public Discord server plan (DRAFT)

DRAFT for the owner and Austin to review (#744). The owner decided on a public server from early Dec 2026 (Oct 18, see [owner-decisions.md](owner-decisions.md)). Background: the "Discord server and mailing list: setup" section of [playbook.md](playbook.md).

Dates this plan must match:

- Steam Playtest: Feb 2027, during the Couch Co-Op Fest.
- Next Fest: Jun 14 to 21 2027.
- Launch: Thu Jul 22 2027.
- Proofreaders are credited in-game.

Playtests are informal. The owner and Austin run them when they can. So there is no fixed weekly playtest night. Post a Scheduled Event only when one is real.

Placeholders to fill in: `[INVITE_URL]`, `[SITE_URL]`, `[STEAM_PAGE_URL]`, `[PLAYTEST_SIGNUP_URL]`, `[FEEDBACK_FORM_URL]`, `[OWNER_HANDLE]`, `[AUSTIN_HANDLE]`.

## Setup steps (about 30 minutes)

Do these in order.

1. **Create the server (2 min).** Discord, then "Create My Own", then "For a club or community". Name it "PickFight". Upload the logo as the icon when you have one.
2. **Turn on Community (3 min).** Server Settings, then Enable Community. Set the rules channel and the updates channel when it asks. Pick them after step 4 if they do not exist yet.
3. **Set safety first (3 min).** Server Settings, then Safety Setup.
   - Verification level: Medium (verified email, account older than 5 minutes). Use High if bots show up.
   - Explicit media filter: scan all members.
   - Turn on DM and raid protection if offered.
4. **Make the channels (6 min).** Use the list below. Make the categories first, then the channels in them.
5. **Make the roles (3 min).** Server Settings, then Roles. Use the table below. Do not give anyone Administrator except the owner and Austin.
6. **Set channel permissions (3 min).** See "Permissions" below.
7. **Switch on AutoMod (3 min).** Server Settings, then AutoMod. Use the settings below.
8. **Write the onboarding flow (4 min).** Server Settings, then Onboarding. Use the questions below.
9. **Post the welcome message and rules (2 min).** Paste them into `#welcome-and-rules`. Pin nothing else there.
10. **Save the invite (1 min).** Create a permanent invite that never expires and has no use limit. Put it in `[INVITE_URL]` everywhere this plan says so.

## Channels

About 12 channels. Keep it small. Empty channels make a server look dead.

**Info**

| Channel | Purpose |
| --- | --- |
| `#welcome-and-rules` | Welcome message and rules. Read-only. |
| `#announcements` | Builds, playtests, sales, launch news. Make it an Announcement channel so other servers can follow it. Only Dev posts. |
| `#devlog` | Weekly devlog: a GIF and what changed from your feedback. Only Dev posts. Replies in threads. |

**Play**

| Channel | Purpose |
| --- | --- |
| `#general` | Chat about the game. |
| `#find-a-match` | Looking for group. Post an Online room code, your region and how many players you need. Close the post when the room is full. |
| `#clips-and-screenshots` | Share funny moments. Clips under 3 MB show inline. |

**Feedback**

| Channel | Purpose |
| --- | --- |
| `#bug-reports` | Forum channel. Tags: crash, join problem, online lag, other. Ask for build, mode (Local or Online) and steps. Pinned note: the in-game Feedback button already files GitHub issues. |
| `#balance-and-ideas` | Forum channel. Tags: weapon, stage, balance, idea. |
| `#playtest-signup` | How to join the Steam Playtest. Pinned: `[PLAYTEST_SIGNUP_URL]`. Dev posts when slots open. |

**Translations**

| Channel | Purpose |
| --- | --- |
| `#translations-proofreading` | Proofreaders fix the machine translations. One thread per language: zh-Hans, ru, es-419, pt-BR, de, fr, ja, ko. Pinned: how to send a fix and how credit works. |

**Staff** (hidden from everyone except Dev)

| Channel | Purpose |
| --- | --- |
| `#mod-log` | AutoMod alerts and ban notes. |

## Roles

| Role | Who | Notes |
| --- | --- | --- |
| Dev | Owner and Austin | Administrator. Colour set apart. Shown separately in the member list. |
| Playtester | People who got into a Steam Playtest or a hosted playtest | Given by hand. Sees `#playtest-notes` if you add it later. Not pinged. |
| Proofreader | Volunteers who fixed translations | Given by hand. Only people who want credit in-game should be asked for a name to credit. |
| Muted | People on a time-out | No send, no react, no voice. Use Discord's own timeout for short cases. |
| Playtest notify | Opt-in from onboarding | The only role anyone pings. Used for playtest news. |
| Couch player / Online player | Opt-in from onboarding | Cosmetic. Helps `#find-a-match`. |

## Permissions

- `@everyone`: read and chat in Play, read and post in Feedback, read Info. No `@everyone` or `@here` mentions. No external links or embeds in their first week if bots appear.
- Info channels: only Dev can post.
- `#mod-log`: only Dev can see it.
- Muted: deny send, react and speak in every channel.

## Rules

Paste these as the rules. Five lines. Anything past a warning is a ban.

1. Be kind. No slurs, hate or harassment.
2. No spam, ads or self-promotion without asking a Dev.
3. Keep it safe for work. No explicit or gory content.
4. Post bugs in `#bug-reports` and room codes in `#find-a-match`.
5. Never share a stranger's private details. The Devs will never DM you for a password or payment.

## Welcome message

Paste this into `#welcome-and-rules`. Edit the dates when they move.

> **Welcome to PickFight.**
> A same-room fighting game. One PC, up to eight players, and everyone joins with a phone by scanning a QR code. Swing your pickaxe, grab weapons, knock your friends off the stage. You can also play Online with a room code.
>
> **Start here**
> - Want to play online? Post your room code in `#find-a-match`.
> - Found a bug? Use `#bug-reports`.
> - Want to try early builds? See `#playtest-signup`. The Steam Playtest is planned for Feb 2027.
> - Speak another language? Help proofread in `#translations-proofreading`. We credit proofreaders in the game.
> - Wishlist on Steam: `[STEAM_PAGE_URL]`. Site: `[SITE_URL]`.
>
> The demo is planned for Steam Next Fest in June 2027, and the full game on Jul 22 2027. Dates can move. We post changes in `#announcements`.
>
> Read the rules below, then say hello.

## AutoMod

Server Settings, then AutoMod. Send every alert to `#mod-log`.

| Rule | Setting |
| --- | --- |
| Block spam content | On. Block the message and time out the member for 10 minutes. |
| Block mention spam | On. Limit 5 mentions in one message. Block it and time out for 1 hour. |
| Block profanity and slurs | Turn on all three Discord presets (profanity, sexual content, slurs). Block the message. |
| Custom keywords | Add `discord.gg/*` and `free nitro` so other invites and common scams are blocked. Let Dev bypass. |
| Block suspected spam accounts | On if offered. |
| Members who join and post links | Block links from members in their first 10 minutes. |

Also hold new members for 10 minutes (the Medium verification level does most of this). Moderate against bots from day one.

## Onboarding question flow

Server Settings, then Onboarding. Make every question optional. Set default channels to `#welcome-and-rules`, `#announcements`, `#general`, `#find-a-match` and `#bug-reports`.

1. **How will you mostly play?** (pick one)
   - Same room with friends: give Couch player.
   - Online with a room code: give Online player.
   - Not sure yet: no role.
2. **What do you want from this server?** (pick any)
   - Playtest news: give Playtest notify.
   - Find an online match: show `#find-a-match`.
   - Help translate: show `#translations-proofreading`.
   - Report bugs or share ideas: show `#bug-reports` and `#balance-and-ideas`.
3. **Which language do you read best?** (pick any, for the translation threads)
   - English, Chinese (Simplified), Russian, Spanish (Latin America), Portuguese (Brazil), German, French, Japanese, Korean. No role. It only shows the matching thread.

## Weekly routine for two people

- A devlog post on `#devlog`: a GIF and what changed from feedback. Aim for weekly while there is news.
- A clip of the week in `#clips-and-screenshots` when there is a good one.
- Reply to bug reports first. Balance feedback from a small group can conflict, so act on bugs before opinions.
- Split cover by day. Promise no response time.
- When an informal playtest is planned, post a Scheduled Event at least 24 hours ahead and ping Playtest notify once.

## Room-code posting (later)

The playbook suggests a Discord webhook from the relay that posts Online rooms to `#find-a-match`. That is not part of this setup. Until it exists, hosts paste codes by hand. If it is built later: use a webhook, send `allowed_mentions: {parse: []}`, rate limit each host, and keep the webhook URL in secrets, never in this public repo.

## Launch checklist

Order of dates, earliest first.

- [ ] Early Dec 2026: server set up with the steps above and opened to the public.
- [ ] Add `[INVITE_URL]` to the site footer (`[SITE_URL]`).
- [ ] Add `[INVITE_URL]` to the Steam Coming Soon page as soon as it exists, and to the title screen.
- [ ] Vanity URL: this needs the server to reach a boost or Partner level. Check Discord's current requirement. Until then, use the permanent invite. Claim the name "pickfight" the day it is available.
- [ ] Dec 2026 to Jan 2027: grow the server from clips, the mailing list and the Steam wishlist page. Add a few Playtesters by hand.
- [ ] By about Dec 28 2026: Steam Playtest is registered. Add the sign-up link to `#playtest-signup` and the welcome message.
- [ ] Feb 2027: Steam Playtest during the Couch Co-Op Fest. Post in `#announcements`. Ask playtesters to report bugs in `#bug-reports`, and invite them to join the server.
- [ ] Feb to May 2027: proofreaders finish the 8 languages. Collect credit names, then add them to the in-game credits.
- [ ] Jun 14 to 21 2027: Next Fest. Add the invite to the demo's end card. Run a Discord event on days 1 and 2.
- [ ] Jul 22 2027: launch. Post in `#announcements`, spend the day in the server, and fix crashes within hours.
- [ ] After launch: keep `#bug-reports` the first thing you read each day.

## Open questions

- Who is the second moderator when one Dev is away? (Owner and Austin to decide, see #685.)
- Will the server stay English-first in `#general`? Suggested: yes, with language threads only in the translation channel.
