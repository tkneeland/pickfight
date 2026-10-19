# Pickfight Launch Digest

Oct 17, 2026 · @Tommy

## The 10 things that matter most

1. **Wishlists before launch decide the launch.** Aim for 30–50k. Median first-week sales are about 0.10–0.20 per wishlist (GameDiscoverCo: 0.15× for 25k+ wishlist games, 0.10× above $10).
2. **The store page sells more than the demo does.** Most Next Fest wishlists come from people who never play the demo. The capsule art and the first 5 seconds of the trailer matter most.
3. **Lead with the phones:** "8 players, no controllers, just scan the QR." No competitor can say it.
4. **Solo with bots must be fun.** Most demo players and streamers start alone.
5. **The first match must just work.** First-session bugs cause most bad reviews in party games. The biggest risk is phones failing to join on guest Wi-Fi, so route them through the relay.
6. **Build for clips:** hit-stop, flailing ragdolls, a slow-motion final KO, and a clip that saves automatically.
7. **Creators beat press.** Pitch 200–400 small creators (10–100k followers). Expect about 1 in 4 to make a video.
8. **Price at $9.99 (decided Oct 18).** $19.99 from an unknown studio reviews worst.
9. **Party games grow slowly.** The big spikes come months or years later, from sales, free weekends and updates. Plan for 12+ months of updates.
10. **PC first.** Port to Switch 6–12 months later, and only if the game is selling.

## Timeline

**Decided (Oct 17): do Next Fest, the June 2027 one, then launch in late July 2027.** Next Fest is worth it. Gains vary widely, and the Popular Upcoming list is now out of reach (about 80-150k wishlists since June 2026). But each game gets only one Next Fest, and results scale with polish and with how many wishlists you bring in. February would mean a placeholder-art demo and only about 3 months of wishlists, so June gives the one shot its best chance.

| When | What |
| --- | --- |
| **Oct–Dec 2026** | Publish the Steam page. Get capsule art and a mascot ($500–1,200). Owner's main theme for the trailer due Nov 30 (#684). Start the Discord and a mailing list. Enter the IGF. Post one short gameplay clip a week. Start code-signing sign-up (Microsoft Artifact Signing, $9.99/month; the ID check takes up to 20 business days). Steam requires notarized Mac builds. |
| **Jan–Feb 2027** | Replace the placeholder art. Run a Steam Playtest with friend invites. Be listed as "upcoming" in Valve's **Couch Co-Op Fest (Feb 8–15)** to collect wishlists. **Have the store page public by early December**, tagged Local Co-Op and Party Game. Valve emails the sign-up link about 2 months before the fest; Dec 28 is the latest safe date. |
| **Mar–Apr 2027** | Release the demo early, with Solo-with-bots as its default path. Add a "phones can't connect?" help screen. Cut a 70-second trailer. Translate into Chinese, Russian, German and Japanese. List 200–400 creators. Start Steamworks signup now (tax check takes up to 30 days). **Register for June Next Fest by Apr 25.** |
| **May 2027** | Trailer to Steam by May 3 and demo build by May 17 (Valve's press-preview deadline; all fest items due May 31) to be in the press preview. Skip Mountaineering Fest (it's for mountain-climbing games) unless Valve says Pickfight counts. Aim for 2,000+ wishlists, plus 2,000 more in the two weeks before the fest. |
| **Jun 14–21, 2027** | **Next Fest.** Pitch creators the week before. |
| **Thu Jul 22, 2027** | **Launch**, two weeks after the Summer Sale ends (Jul 8). Swap in the launch trailer. Send creator keys. Take 10–15% off at launch. |
| **First year** | Patch monthly. Ship a big update 2–3 months after launch. Run one free weekend. Take 40–50% off in the Winter Sale. |
| **+6–12 months** | If it's selling, port to Switch with W4 Games. |

## Do this month

- [ ] Pay the $100 Steam Direct fee and **publish the Coming Soon page**. Wishlists only start counting once the page exists, and first-time devs can request keys only 3 weeks after the app ID is created.
- [ ] Check that the name "Pickfight" is clear to trademark, and grab the matching social handles.
- [ ] Commission the capsule art. Use 20 tags: party, local multiplayer, physics, and similar.
- [ ] Open a Discord and add a mailing-list signup.
- [ ] Run a friends-and-Discord playtest: 20–40 people, 3 scheduled evenings, and watch 2–3 people join by QR.
- [ ] Register on the Nintendo Developer Portal. It's free and approval is slow.
- [ ] Enter the IGF (November deadline).

## Built overnight (Oct 18–19)

Ten PRs merged and installed. Still waiting on the owner: the achievement list (#689), the Sentry DSN (#681) and the Austin items (#685).

| PR | What shipped |
| --- | --- |
| #699 | Russian count strings no longer need plural forms |
| #698 | Opt-out crash reports (Sentry), dormant until a DSN is pasted (#681) |
| #697 | Steam readiness doc follows the Oct 18 decisions |
| #696 | Dormant Steam wrapper (GodotSteam fetched, never committed) (#428) |
| #695 | Phones can join a Local match over the relay when Wi-Fi blocks them (#683) |
| #694 | 36 more strings translated (#693) |
| #692 | 8 languages plus a Language setting (#688) |
| #691 | Lava, spikes and saw art (#687) |
| #690 | Bot difficulty: easy, normal, hard (#682) |
| #686 | "Phones can't join?" help popup (#680) |

## Biggest bets for Pickfight

Each of these builds on something already in the game.

- **Play of the round.** After each round, replay the best 8 seconds in slow motion with the player's name. This builds on the F9 replay. It gives streamers a payoff moment and makes clips automatically.
- **Steam Timeline markers.** Mark every KO and round win so Steam's built-in recorder offers them as one-click clips. It takes about 1–2 days once the game is on Steam.
- **Ghosts that can change the outcome.** Ghost grab and boo already exist. Jackbox learned that knocked-out players stay engaged only if they can still affect who wins.
- **About 30 funny, room-wide achievements.** Examples: "Friendly Fire", "Photo Finish", "World Tour (all 43 stages)". They go to the host's account. **Keep everything unlocked** so couch guests never feel locked out.
- **Sell "one room, one screen" as a feature,** the way Sportsfriends sold "local only". Market the breadth as a pack: "43 stages, 15 weapons, 6 modes."
- **Steam Playtest with Friend Invites.** Each tester brings their own group, which suits a party game.
- **A small couch bundle** with 2–3 peers at launch, such as SpiderHeck, Bopl Battle and Boomerang Fu. That is the pattern Bopl Battle used.
- **Remote Play Together switches on automatically.** Test it before release. Phones can't use it, so it's a way to try the game, not a source of revenue.
- **On console, phones join through the online relay,** the way Jackbox works on console.

## Where the detail lives

Every claim here comes from the full **[Indie Steam Launch Playbook](https://claude.ai/artifact/H44aKHzdMAHNxZ65tKw75m)**. It has 50+ sections with sources: store page, trailers, creators, pricing, Next Fest, consoles, legal, achievements, replays, sales calendar and more. Research continues there, and this digest is updated as the big picture changes.
