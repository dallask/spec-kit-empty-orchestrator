# spec-kit-empty-orchestrator

## Description

Specify extension. It reads BACKLOG.md file, goes through the full flow (/speckit.specify -> /speckit.clarify -> /speckit.plan -> /speckit.tasks -> /speckit.analyze -> /speckit.implement). Extension should treat every item in the BACKLOG.md as a separate feature and work with it in the separate worktree. Extension should implement hub-and-spoke agent architecture with the Lead agent as an orchestrator, BA subagent as a speck creator (/speckit.specify -> /speckit.clarify -> /speckit.plan -> /speckit.tasks -> /speckit.analyze) and Dev subagent as developer (/speckit.implement). All coordination between agents should go through orchestrator. Agents should pass the data in the structured JSON format (not prose). Only Orchestrator can spawn subagents. Use the https://github.com/GenieRobot/spec-kit-maqa-ext as an example. Extension should have configuration in yaml format, and state storage in json format (just like maqa extension does). Flow should look like this: User start Lead agent -> Lead reads BACKLOG.md -> Lead spins as many worktrees as many parallel agents it can spawn according settings -> Lead spawns BA subagents -> each BA subagent works with its own feature in its own worktree and runs full flow (/speckit.specify-> /speckit.clarify -> /speckit.plan -> /speckit.tasks -> /speckit.analyze) only stops when it needs clarification from user during clarify and analyze phase -> BA subagent return results to Lead as soon as full feature flow done or errors -> Lead check that feature speck is completed -> Lead spawn Dev subagents for each feature separately (amount of subagents according settings) -> Each dev proceed with feature development according speck -> Dev returns result to LEad -> lead merges feature to dev branch.

## Requirements
- System agmostic
- sh scripts as a helpers scripts approach

## References
- https://github.com/github/spec-kit
- https://code.claude.com/docs
- https://speckit-community.github.io/extensions/
