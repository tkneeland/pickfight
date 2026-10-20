# Content survey and age rating: suggested answers

**DRAFT — needs owner approval.** These are suggested answers for Steam's content survey (the mature-content questionnaire in Steamworks) and the IARC age-rating questionnaire Steam shows during store setup. Form names and wording change: **verify** each question against the live form. Answer honestly from the shipped build; if a later update changes a row, redo the survey.

Basis: `docs/FEATURES.md`, `docs/steam-readiness.md` (item 3.1), `docs/launch/owner-decisions.md`. The game has square cartoon characters with eyes and hats, jointed weapons, and hazards; characters are knocked out and burst into shapes, with no blood or gore.

## Steam content survey

| Question (paraphrased) | Suggested answer | Why |
| --- | --- | --- |
| Frequent violence or gore? | No | Squares are knocked off the stage or into hazards and burst into a coloured puff; no blood, gore or body parts. |
| Any violence at all? | Yes, mild cartoon violence | Players hit each other with weapons (pickaxe, sword, axe) and can knock each other out. |
| Nudity or sexual content? | No | None in the game. |
| Frequent or intense depictions of sexual content? | No | None. |
| Drug or alcohol use? | No | None. |
| Gambling or simulated gambling? | No | No betting, loot boxes or chance purchases (the "weapon roulette" round modifier just gives a random weapon). |
| Real-money purchases or in-game currency? | No | Game is a single purchase; no in-game store or currency. Optional soundtrack DLC is separate, bought on Steam. |
| Unrestricted user-generated content? | No | Players can type only a player name and the feedback box; neither is shown to other players beyond the room's names (see below). |
| Online interaction with strangers? | No public matchmaking | Online play is by private room code or Steam friend invite; no public lobbies at launch (owner decision). |
| In-game chat? | No | There is no chat. |
| Flashing lights or photosensitivity concerns? | Mention it | Hit effects and bounce pads flash; the game has a Reduce flashes option and a Screen shake off option. |
| Uses generative AI? | Disclose translations only | Translations are AI-assisted (owner decision Oct 18: disclose the AI-assisted translations only). The owner leans toward disclosing nothing; the agent advises disclosing. Owner's call. |

## IARC age rating questionnaire

| Area | Suggested answer | Why |
| --- | --- | --- |
| Violence | Cartoon or fantasy violence, mild | Characters fight with weapons but are abstract squares; no blood. |
| Blood and gore | None | None shown. |
| Sexual content or nudity | None | None. |
| Language | None | Game text is written by us; player names are the only free text others can see. |
| Controlled substances | None | None. |
| Gambling | None | No real or simulated gambling. |
| Fear or horror | None | Bright, comic look. |
| Discrimination or hate | None | None in the game's content. |
| In-app purchases | No | Single paid game; no in-game purchases. |
| Users can interact or exchange content | Yes, limited | Players in the same room see each other's chosen names, and the Online feature connects them by room code. No chat, no uploads. The feedback box posts to our own GitHub project. |
| Shares user location | No | Never collected. |
| Digital purchases or ads | No | No ads, no in-game store. |
| Online features that collect personal info | Say what the privacy policy says | Anonymous match stats and crash reports (both with opt-out) and the feedback box; see `privacy-policy.md`. |

Expected result: an everyone-or-ten-plus style rating (ESRB E10+ and PEGI 7 are typical for cartoon violence without blood). The questionnaire sets the actual rating, so check it against this expectation.

## Notes for the owner

- **User text:** the only free text is a player name (shown on screen to the room and in online rooms) and the feedback box. No name filter was found in the code; if you want a name filter, that is a separate ticket.
- **Age-gated store page:** none needed with these answers.
- **Photosensitivity:** if the live form has no flashing-light field, add one line in the store page's "About this game" noting the Reduce flashes option.
