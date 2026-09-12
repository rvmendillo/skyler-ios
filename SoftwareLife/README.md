# Software Life

**Software Life** is an original 3D iOS board/life/economy game inspired by the strategic feel of classic property-and-wealth games, Philippine *Millionaires Game*, and life-simulation board games, while using original rules, characters, board layout, progression, art direction, and events.

## Target
- iOS 27
- Swift / SwiftUI
- RealityKit 3D board + human-like procedural characters
- Local single-player MVP first; multiplayer architecture later

## Core fantasy
Start as a student or junior developer and build a life through a volatile software economy. Players can become engineers, founders, executives, investors, indie developers, open-source maintainers, or financially independent generalists.

## Win condition
The game ends after a configurable number of career eras. Final score is intentionally broader than cash:

`Legacy Score = Net Worth + Career Capital + Reputation + Wellbeing + Ownership + Major Achievements`

This allows different winning strategies instead of making bankruptcy the only endgame.

## Unique systems
- Career ladder, interviews, promotions, job hopping, and layoffs
- Salary, bonus, startup equity, vesting, and dilution
- Startups, funding rounds, acquisitions, IPOs, and shutdowns
- Public-market investing and private startup stakes
- Housing/property as one asset class rather than the entire economy
- Skills that unlock roles and improve event outcomes
- Side projects, SaaS, indie apps, and passive recurring revenue
- Open-source reputation and community influence
- Burnout, wellbeing, time, and work-life tradeoffs
- Technical debt, outages, cyber incidents, and product quality
- AI booms, funding winters, recessions, platform shifts, outsourcing waves, regulation, and market bubbles
- Negotiation and asset trading between players
- Fictionalized event cards inspired by real software-industry dynamics without copying real companies or people

## Turn loop
1. Roll / advance on the 3D career-city board.
2. Resolve the destination tile.
3. Choose among contextual actions rather than receiving an automatic outcome.
4. Resolve market / industry events.
5. Update salary, recurring income, equity value, wellbeing, skills, and reputation.
6. Advance the era clock.

## Board districts
- **Campus Row** — education, certifications, internships
- **Startup Alley** — funding, founder opportunities, equity risk
- **Enterprise District** — stable salaries, promotions, bureaucracy
- **Open Source Commons** — reputation and community power
- **Market Exchange** — public shares and macro events
- **Creator Quarter** — indie apps, SaaS, content, side projects
- **Cloud Heights** — infrastructure, scale, outages, platform risk
- **AI Frontier** — automation booms, model shifts, disruption
- **Residential Loop** — rent, mortgages, property, lifestyle costs
- **Reset Point** — sabbaticals, layoffs, pivots, career reinvention

## Key twist: industry eras
The board itself changes over time. An `IndustryEra` modifies salaries, company valuations, startup failure odds, hiring, and event probabilities. A great strategy in one era may fail in another.

## MVP scope
- 1 human player + 3 AI rivals
- Procedural 3D board and human-like pawns
- Dice movement
- Career / salary / cash / wellbeing / reputation stats
- 30+ software-industry event templates
- Jobs, startups, investing, property, side-project and skill tiles
- Era modifiers
- Local save state
- End-of-game Legacy Score

## Next milestones
1. Compileable standalone Tuist project under `SoftwareLife/`
2. Core game-state engine and deterministic turn resolution
3. RealityKit board renderer and animated characters
4. Event / decision UI
5. AI rivals
6. Sound, haptics, animations, polish
7. GitHub Actions/macOS signing pipeline for IPA export
