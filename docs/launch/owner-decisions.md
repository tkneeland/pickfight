# Owner decisions log (launch planning)

Every product and business answer the owner gave in the Oct 2026 grills, in one place. When a decision changes, edit it here and say when. Open items that need Austin live in the pinned issue **#685**, not here.

Earlier decisions (Sep–early Oct) are in the ADRs (`docs/adr/`), `docs/steam-readiness.md` and the issues they came from. Where something below contradicts an older note, this file wins (newest first).

## Studio and business
- **Studio:** SQL Monkey Studios (the owner and Austin, no LLC). It is both developer and publisher on Steam. (Oct 18)
- **Steamworks signup entity:** reopened Oct 18. The Oct 1 answer was the owner as an individual. Decide with Austin before the Nov 2026 signup (#685, #540).
- **Budget:** tentative $1,000, $500 each from the owner and Austin (#685).
- **Trademark:** run a clearance search only; don't file. (Oct 18)
- **Publishers:** pitch them anyway, with the Playtest build in Feb–Mar 2027. You can always turn an offer down. (Oct 18)
- **Consoles:** none until 10,000 copies sold (#268). (Oct 18)
- **Brand accounts:** yes. Handle (`pickfight` vs `sqlmonkeystudios`) is pending Austin (#685).
- **Domain and site:** buy a domain and put up a one-page site with a mailing-list signup by early Dec 2026. (Oct 18)

## Release plan
- **Format:** full 1.0, no Early Access. (Oct 18)
- **Launch date:** Thu Jul 22 2027. Two weeks after the Steam Summer Sale ends. (Decided Oct 17, confirmed Oct 18)
- **Next Fest:** June 2027 (Jun 14–21). Register by Apr 25, trailer by May 3, demo build by May 17. (Oct 17)
- **Demo content:** still open, with Austin, by mid-April 2027 (#448).
- **Steam Playtest:** during the Couch Co-Op Fest, Feb 2027. Register by about Dec 28 2026. (Oct 18)
- **Coming Soon page:** live mid-Dec 2026 (#540). (Oct 18)
- **Platforms:** Windows, macOS, Linux. Aim for Steam Deck Verified. (Oct 18)
- **Online play:** in launch scope. No public matchmaking at launch; revisit after launch if the numbers justify it (#357). (Oct 18)
- **Remote Play Together:** off at launch. (Oct 18)
- **Steam features at launch:** SDK, friend invites, persona names (#428 done dormant; #298, #538 parked until after Next Fest per the owner on Oct 3). 15–20 achievements (#689; the draft list awaits owner approval). (Oct 18)
- **Windows code signing:** skip unless it would really bite. (Oct 18)
- **Crash reports:** opt-out (on by default, with a Settings checkbox). Shipped in #681; the owner pastes the Sentry DSN. (Oct 18)

## Price and money
- **Price:** $9.99 USD, with Steam's recommended regional prices. On Oct 2 the owner wanted to confirm price with Austin (#685). (Oct 18)
- **Launch discount:** 20% in launch week. (Oct 18)
- **DLC:** soundtrack DLC $4.99 on launch day. No other paid DLC; updates are free (at least 6 months of free updates). (Oct 18)

## Content and art
- **Art:** keep the square characters. Claude polishes hazards and the like (#687 shipped). Capsule art and logo: budget decision with Austin (#685). (Oct 18)
- **Title and logo:** the title text is "PickFight", with an all-caps logo. (Oct 18)
- **Music:** the owner is a composer and writes the whole soundtrack. Never suggest commissioning music. Brief, track list and deadlines (Nov 30 2026, Jan 31 2027, Apr 1 2027) are in #684. (Oct 18)
- **Trailer:** the owner edits it from Claude's shot list. (Oct 18)
- **Translations:** Claude translates and volunteers proofread, credited in-game. 8 languages by Next Fest: zh-Hans, ru, es-419, pt-BR, de, fr, ja, ko (shipped in #688). No paid agency. (Oct 18)
- **AI disclosure on Steam:** disclose the AI-assisted translations only. The owner leaned toward disclosing nothing; Claude advised disclosing. (Oct 18)

## Marketing
- **Short clips:** TikTok, YouTube Shorts, Reddit, Instagram Reels. Facebook/Instagram paid ads are a budget question (#685). (Oct 18)
- **Discord:** a public server from early Dec 2026. (Oct 18)
- **Outreach:** Claude drafts the emails; the owner and Austin send as many as they can. Keys go out via Curator Connect and Keymailer. (Oct 18)
- **Festival livestreams:** yes, pending Austin; the schedule is in #685. (Oct 18)

## How the owner wants agents to work
- Decide ticket priority yourself (p1/p2/p3); don't ask.
- Never ask what the code or `docs/FEATURES.md` already answers.
- Every "talk to Austin" answer goes onto #685 right away.
- The repo is public: no secrets in commits or issues.
