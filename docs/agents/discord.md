# Discord setup

How to set up, join and check the project's Discord server for the hive (`DISCORD=1`; rules 18-21 in [hive.md](hive.md)).
This note holds no secrets. The server and channel ids are public in `hive.conf` (`DISCORD_GUILD`,
`DISCORD_BUGS_CHANNEL`, `DISCORD_DEV_CHANNEL`); read them there.

## Server and channels

- One project server (`DISCORD_GUILD`) with two report channels:
  - `#change-requests` (`DISCORD_BUGS_CHANNEL`): public. Anyone reports bugs and change requests; a dev's ✅ approves one.
  - `#hive` (`DISCORD_DEV_CHANNEL`): private, for devs. Reports there are already approved, and the hive answers here (rule 21).
- The display names are `DISCORD_BUGS_NAME` and `DISCORD_DEV_NAME` in `hive.conf`.

## Dev role and the bot

- The `Dev` role (`DISCORD_DEV_ROLE`) is what separates devs from everyone else. A member with it sees `#hive`, and their
  ✅ on a public report approves it.
- Give a new dev the role once they have joined: `bash tools/agents/hive-discord.sh role-add <user id> Dev`. Needs the
  user's yes (rule 20).
- The bot has the role too, so it sees `#hive`. It never reacts ✅; its "handled" reaction is ☑️, which is not an approval.
- Private channels go behind the role (`hive-discord.sh create text <name> private`, or `create text <name> <category> private`), never per person. Never add or
  change a per-user overwrite, and never touch `@everyone`, the `Dev` role itself or Administrator rights without the user's
  explicit yes for that action.
- The bot needs View Channel, Send Messages and Read Message History in both channels; Add Reactions is also wanted, so
  acks are visible to a new triagemaster.

## Bot intents

In the Discord developer portal, Bot tab, turn on both:

- **Message Content**: without it every report reads as blank.
- **Server Members**: needed by `hive-discord.sh members`.

## Bot token

- The token lives only in `$HIVE_STATE/discord.conf` on each machine that can become triagemaster, as one line:
  `HIVE_DISCORD_TOKEN=<bot token>`.
- It reaches each machine out of band, handed over by the owner. Never commit it, and never paste it in GitHub, Discord or
  the private channel.
- Without the file the watcher skips Discord and `hive-tm-check.sh` reports FAIL. Ask the owner; do not work around it.

## Check it works

Run these on each machine, with `HIVE_ACCOUNT=<you>`:

1. `bash tools/agents/hive-discord-bugs.sh status` checks `#change-requests`: token valid, bot sees the channel, can read
   history, may read and reply, message text visible (Message Content on), and the unread count.
2. `bash tools/agents/hive-discord-bugs.sh --dev status` runs the same checks on `#hive`.
3. `bash tools/agents/hive-tm-check.sh` prints the Discord lines among the triagemaster duties. It runs only the
   `#change-requests` status (step 1), not `--dev`, so `#hive` is verified by step 2 alone.

Every line should be PASS or INFO; a FAIL names the fix. If the bot was removed from the server, the owner adds it again.

## Optional: pings

By default nothing pings a person. A dev who wants `DEV_IDLE` and similar alerts to ping them adds one line to their own
`$HIVE_STATE/discord.conf`: `HIVE_DISCORD_ID_<account>=<discord user id>` (non-alphanumerics in the account name become
`_`). Keep it out of the repo. Only ids listed this way can be pinged; ids in reports never are.
