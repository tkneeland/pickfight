# Proof of work: issue #59, existing stages slightly easier to traverse

Cleared and recaptured per `docs/agents/testing.md`: this root holds only the latest work package's evidence.

| Stage | Change | Evidence |
| --- | --- | --- |
| Pillars | Gap between column tops 240 → 180 px (columns 120 → 140 wide, outer ones ±360 → ±320) | `issue-59/Pillars/` |
| Highrise | Rungs 200 → 240 wide, pulled toward the middle; hand-offs 233–295 → 156–170 px | `issue-59/Highrise/` |
| Flatlands | Left platform 24 px lower (172 → 148 px above the floor) | `issue-59/Flatlands/` |
| Erosion | Crumbling ledges 200 → 160 wide, warning 0.8 → 1.0 s | `issue-59/Erosion/` |
| Ferry | Barge runs 30 px in under each dock, same speed | `issue-59/Ferry/` |
| Islands, Cascade, Slant, Bowl, Furnace | Already traversable, left as is | probe notes and before shots |

Full suite: `issue-59/scenario-suite.txt`, 97/98. The one failure, `axe_head_holds_side_near_vertical`, is pre-existing on `main`: it depends on test order and passes alone. Fresh-clone boot: clean.
