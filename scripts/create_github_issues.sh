#!/usr/bin/env bash
# create_github_issues.sh
# ────────────────────────────────────────────────────────────────
# Syncs investment idea issues to GitHub. Idempotent:
#   - Issue doesn't exist yet  → create it
#   - Issue exists, no changes → skip
#   - Issue exists, synced section changed → update only the top half;
#     your manual edits below the divider (decision, price, notes)
#     are always preserved.
#
# Body structure:
#   [synced content — driven by this script]
#   <!-- MANUAL -->
#   [your edits on GitHub — never touched by the script]
#
# State is tracked in .github/.issue_sync (commit this file so
# re-clones on other machines start from the right baseline).
#
# Usage:
#   cd ~/Documents/Claude/investments-and-ideas
#   brew install gh && gh auth login   # one-time setup
#   bash scripts/create_github_issues.sh
# ────────────────────────────────────────────────────────────────

set -euo pipefail

SYNC_FILE=".github/.issue_sync"
DIVIDER="<!-- MANUAL -->"
touch "$SYNC_FILE"

# ── Helpers ───────────────────────────────────────────────────────

# Hash a string → 64-char hex (sha256)
sha() { echo "$1" | shasum -a 256 | cut -d' ' -f1; }

# Read stored synced-hash for a title (empty if not seen before)
get_stored_hash() {
  local key; key=$(sha "$1")
  grep "^${key}=" "$SYNC_FILE" 2>/dev/null | cut -d'=' -f2 || echo ""
}

# Persist synced-hash for a title
store_hash() {
  local key; key=$(sha "$1")
  local tmp="${SYNC_FILE}.tmp"
  grep -v "^${key}=" "$SYNC_FILE" > "$tmp" 2>/dev/null || true
  echo "${key}=$2" >> "$tmp"
  mv "$tmp" "$SYNC_FILE"
}

# Return issue number if a matching title exists (open or closed), else empty
find_issue() {
  gh issue list --state all --limit 200 --json number,title \
    | jq -r --arg t "$1" '.[] | select(.title == $t) | .number' \
    | head -1
}

# Extract everything AFTER the divider from a full GitHub issue body.
# Returns the default manual section if the divider isn't present yet.
extract_manual_section() {
  local full_body="$1"
  local default_manual="$2"
  if echo "$full_body" | grep -qF "$DIVIDER"; then
    # Take everything after the first divider line
    echo "$full_body" | awk "/${DIVIDER//\//\\/}/{found=1; next} found{print}"
  else
    echo "$default_manual"
  fi
}

# Create or update an issue.
# $1 title  $2 labels  $3 synced_body  $4 default_manual_section
upsert_issue() {
  local title="$1" labels="$2" synced="$3" default_manual="$4"

  local synced_hash; synced_hash=$(sha "$synced")
  local stored_hash; stored_hash=$(get_stored_hash "$title")

  local number; number=$(find_issue "$title")

  # ── Create (issue doesn't exist yet) ──────────────────────────
  if [[ -z "$number" ]]; then
    local full_body="${synced}

${DIVIDER}
${default_manual}"
    gh issue create --title "$title" --label "$labels" --body "$full_body"
    store_hash "$title" "$synced_hash"
    echo "  ✅ Created:     $title"
    return
  fi

  # ── Skip (synced section unchanged) ───────────────────────────
  if [[ "$synced_hash" == "$stored_hash" ]]; then
    echo "  ⏭  No changes:  $title (#${number})"
    return
  fi

  # ── Update (synced section changed — preserve manual section) ─
  local current_body; current_body=$(gh issue view "$number" --json body -q .body)
  local manual_section; manual_section=$(extract_manual_section "$current_body" "$default_manual")

  local new_body="${synced}

${DIVIDER}
${manual_section}"
  gh issue edit "$number" --body "$new_body"
  store_hash "$title" "$synced_hash"
  echo "  ✏️  Updated #${number}: $title  (manual section preserved)"
}

echo "📌 Syncing investment idea issues to GitHub..."
echo ""

# ── Issue 1: Aedifica ────────────────────────────────────────────
upsert_issue \
  "[IDEA] AED — Aedifica (Healthcare REIT)" \
  "idea,watching,real-estate,europe" \
  "## One-Line Thesis
Belgian healthcare REIT with defensive, inflation-linked rental income from senior housing across Western Europe — structural beneficiary of demographic ageing.

## Business Overview
- **Sector**: Healthcare Real Estate (Belgian RREC / REIT)
- **Geography**: Belgium, Netherlands, Germany, UK, Ireland, Sweden, Finland
- **Portfolio fair value**: €6.2bn (618 sites, end-2025)
- **Listed on**: Euronext Brussels (AED)
- **Broker**: DEGIRO

## Thesis
Aedifica owns senior housing on long-term triple-net leases. Demand is structural (demographic ageing), rents are indexed to inflation, and the sector is under-supplied across Western Europe. Valuation has compressed sharply from 2021 highs — stock trades ~25–30% below EPRA NTA. A falling rate environment is the re-rating catalyst.

## Key Catalysts
- [ ] ECB rate cuts → NAV expansion / yield compression
- [ ] Cofinimmo exchange offer outcome (potential scale + synergy benefits)
- [ ] Like-for-like rent growth via indexation (2.7% in 2025)
- [ ] Pipeline project deliveries

## Valuation
| Metric | Value |
|--------|-------|
| EPRA Earnings/share | €5.15 (FY2025, +4% YoY) |
| Gross dividend/share | €4.00 (proposed, May 2026 AGM) |
| Dividend yield | ~6–7% at current price |
| EPRA NTA | ~€80+ (stock at ~30% discount) |
| Fair value estimate | €72–80 base case |

## Risks
1. Cofinimmo deal distraction / dilution if unsuccessful
2. Rates re-accelerate → delays NAV recovery
3. Care home operator financial stress (staffing costs, regulation)

## Portfolio Fit
- **Bucket**: Real Estate (target 10% sleeve)
- **Max size**: 4–5% of portfolio
- **Broker**: DEGIRO
- **Hold period**: 3–5 years minimum" \
  "## My Decision  ← edit this directly on GitHub, it won't be overwritten
- [ ] Buy — entry price: €___ · size: ___% · date: ___
- [x] Watch — revisit when: Cofinimmo deal outcome + next ECB meeting
- [ ] Pass — reason: ___

## Notes
| Date | Note |
|------|------|
| | |"

# ── Issue 2: Merlin Properties ───────────────────────────────────
upsert_issue \
  "[IDEA] MRL — Merlin Properties (REIT + Data Centres)" \
  "idea,watching,real-estate,europe,data-centers" \
  "## One-Line Thesis
Spain's largest REIT pivoting from offices to data centres at the right time — Iberia's AI infrastructure buildout is an underappreciated growth engine trading at a discount.

## Business Overview
- **Sector**: Diversified Commercial Real Estate / SOCIMI (Spanish REIT)
- **Geography**: Spain, Portugal
- **Portfolio fair value**: ~€12bn (end-2025)
- **Listed on**: BME / IBEX-35 (MRL)
- **Broker**: DEGIRO

## Thesis
Merlin is the dominant commercial property owner in Iberia. Traditional income (offices, logistics, shopping centres) is stable and inflation-linked. The emerging angle is data centres — AI demand is driving explosive infrastructure needs in Southern Europe, and Merlin is executing Phase III (412 MW, €650M+ targeted revenues). Dual value: stable REIT core at a discount + embedded growth option in a high-multiple sector.

## Key Catalysts
- [ ] Data centre Phase III operational milestones
- [ ] Iberian AI/cloud capex continues — hyperscaler demand
- [ ] Like-for-like rent growth on logistics/office portfolio
- [ ] ECB rate cuts → REIT multiple re-rating across Europe
- [ ] Portfolio rotation: mature offices sold → recycled into DCs

## Valuation
| Metric | Value |
|--------|-------|
| FFO (2025) | €327m (+5.1% YoY) |
| Rental income (2025) | €509.8m |
| Analyst avg. target | €16.88 (range €13.9–€20.85) |
| Analyst consensus | 19/19 Buy |
| Portfolio occupancy | 95.6% (watch: -116bps YoY) |
| Fair value estimate | €17–18 base case; €20+ bull (DC repricing) |

## Risks
1. SOCIMI regime risk — Spanish political changes to tax treatment
2. Office structural headwinds (53% of income)
3. Data centre execution / capex overrun risk
4. Occupancy drift accelerating

## Portfolio Fit
- **Bucket**: Real Estate or Emerging/Thematic (DC angle)
- **Max size**: 3–5% of portfolio
- **Broker**: DEGIRO
- **Hold period**: 3–5 years (DC thesis needs time)" \
  "## My Decision  ← edit this directly on GitHub, it won't be overwritten
- [ ] Buy — entry price: €___ · size: ___% · date: ___
- [x] Watch — revisit when: DC Phase III update + SOCIMI regime clarity
- [ ] Pass — reason: ___

## Notes
| Date | Note |
|------|------|
| | |"

# ── Issue 3: Quantum Computing Theme ────────────────────────────
upsert_issue \
  "[IDEA] THEME — Quantum Computing Sector" \
  "idea,watching,thematic,technology,speculative" \
  "## One-Line Thesis
Quantum computing is transitioning from lab to nascent industry (~\$3.5B → ~\$20B by 2030). Barbell strategy: IBM/GOOGL for funded exposure + small IonQ position for asymmetric upside.

## Sector Overview
Quantum computers use qubits to solve certain problems exponentially faster than classical computers. Key applications: cryptography, drug discovery, financial optimisation, materials science. Sector is pre-commercial for most use cases but inflecting — 2025/2026 is an infrastructure and IP buildout phase.

## Key Players
**Pure-play (high risk / high upside)**
| Ticker | Company | Notable |
|--------|---------|---------|
| IONQ | IonQ | Q3 2025 revenue +222% YoY; acquired SkyWater (fab) for vertical integration |
| RGTI | Rigetti | Full-stack model; underwhelmed Q4 2025; down ~27% YTD |
| QBTS | D-Wave | Quantum annealing niche; nearest to commercial |

**Diversified (lower risk)**
| Ticker | Company | Quantum angle |
|--------|---------|---------------|
| IBM | IBM | Heron R2 (156 qubits); targets quantum advantage demo 2026 |
| GOOGL | Alphabet | Willow chip (105 qubits, error correction milestone) |
| MSFT | Microsoft | Topological qubits; Azure Quantum cloud |

## Strategy
Barbell: hold IBM/GOOGL within the Global Equities bucket (funded, profitable businesses); add a small speculative position in IonQ (max 1–2% of portfolio) for asymmetric optionality. Avoid underfunded pure-plays (RGTI).

## Key Catalysts
- [ ] IBM demonstrates quantum advantage on commercial problem (2026 target)
- [ ] IonQ profitability milestones / major enterprise contract
- [ ] EU/US government quantum investment programmes
- [ ] Fault-tolerant qubit demonstration by any major player

## Risks
1. Timeline risk — practical quantum advantage may be 5–10 years away
2. Pure-play dilution — ongoing equity issuance to fund R&D
3. Architecture obsolescence — winning qubit type still unclear
4. Valuation still pricing unrealistic near-term adoption
5. Micro-cap liquidity for pure-plays

## Portfolio Fit
- **Bucket**: Emerging / Thematic (max 10% sleeve)
- **Max size**: 1–2% for pure-plays; IBM/GOOGL in Global Equities bucket
- **Broker**: DEGIRO (US stocks)
- **Hold period**: 5–10 year horizon" \
  "## My Decision  ← edit this directly on GitHub, it won't be overwritten
- [ ] Buy — IonQ entry: \$___ · size: ___% · date: ___
- [x] Watch — revisit when: IBM quantum advantage update + IonQ Q2 2026 earnings
- [ ] Pass — reason: ___

## Notes
| Date | Note |
|------|------|
| | |"

# ── Issue 4: UnitedHealth Group ─────────────────────────────────
upsert_issue \
  "Research: UNH — UnitedHealth Group" \
  "idea,watching,healthcare,us-equities" \
  "## One-Line Thesis
Largest US managed care company (\$448B revenue), trading at decade-low multiple after 2024–2025 crisis cascade. Q1 2026 beat + MCR improvement signal inflection — DOJ probe and Medicare Advantage reset are unresolved overhangs.

## Business Overview
- **Sector**: US Healthcare — Managed Care / Integrated Health Services
- **Geography**: United States (dominant)
- **Market cap**: ~\$349B
- **Listed on**: NYSE (UNH)
- **Broker**: DEGIRO

### Two-Engine Structure
| Segment | 2025 Revenue | YoY |
|---------|-------------|-----|
| UnitedHealthcare | \$344.9B | +16% |
| Optum Rx | \$154.7B | +16% |
| Optum Health | \$102.0B | -3% (op. income -\$278M) |
| Optum Insight | \$19.4B | +4% |
| **Total** | **\$447.6B** | **+12%** |

## Thesis
Vertically integrated flywheel (payer + provider + PBM + analytics). 2024–2025 crisis compressed multiple from ~25× to ~21×. Hemsley \"2026 reset\": exiting low-margin MA markets, cutting Optum Health network 20%, consolidating 18 EMR → 3, \$1.5B AI investment targeting ~\$1B cost savings. Q1 2026: EPS \$7.23 (+10% beat), MCR 83.9% (improving from 84.8%).

## Key Catalysts
- [ ] DOJ resolution without criminal charges
- [ ] MCR normalisation — Q2/Q3 2026 confirmation below 85%
- [ ] Optum Health return to positive operating income (2027)
- [ ] AI cost savings realisation (~\$1B targeted for 2026)
- [ ] 2027 guidance: 13–16% EPS growth re-rate toward 25×

## Valuation
| Metric | Value |
|--------|-------|
| Price | ~\$380 (52-week: \$234–\$387) |
| 2026E adj. EPS | \$18.25+ (raised post-Q1) |
| Forward P/E | ~20.8× (10-year low; hist. avg ~25×) |
| Dividend yield | 2.33% |
| Operating margin | ~8.5% (vs CVS 3.8%, Cigna 4.5%, ELV 6.0%) |
| Analyst consensus | Buy (26/28); avg target \$384–389; Goldman \$435 |

### Fair Value Scenarios
| Scenario | Multiple | Price |
|----------|----------|-------|
| Stress | 17× | \$310 |
| Base | 22× | \$402 |
| Recovery | 25× | \$456 |
| Bull (2027 re-rate) | 27× \$20 EPS | \$540 |

## Risks
1. DOJ criminal indictment (active criminal + civil probes since Jul 2025)
2. Optum Health structural impairment (op. income -\$278M vs +\$7.8B in 2024)
3. Medicare Advantage structural underfunding (CMS cuts, losing 1.3–1.4M members)
4. Prior auth forced regulatory changes → structural MCR increase
5. Antitrust / forced Optum divestiture (worst-case DOJ outcome)" \
  "## My Decision  ← edit this directly on GitHub, it won't be overwritten
- [ ] Buy — entry price: \$___ · size: ___% · date: ___
- [x] Watch — revisit when: Q2 2026 MCR confirmation + any DOJ development
- [ ] Pass — reason: ___

## Price Alerts
- Add to position: \$330–350
- Full position (2–3%): on DOJ resolution

## Notes
| Date | Note |
|------|------|
| 2026-05 | Initial. Stock ~\$380, Q1 beat, MCR improving. Wait for better entry or DOJ clarity. |"

# ── Issue 5: Adyen ──────────────────────────────────────────────
upsert_issue \
  "[IDEA] ADYEN — Adyen N.V. (EU Payments)" \
  "idea,researching,europe,fintech,payments" \
  "## One-Line Thesis
Dutch single-platform global payments processor at **52-week low (~€872, ~68% off 2021 ATH)** despite FY2025 delivering on every reset target — 21% constant-currency net revenue growth, 53% EBITDA margin (H2 55%). Market disconnect, not waiting case.

## Business Overview
- **Sector**: Payments / Fintech infrastructure (European Equities bucket)
- **Geography**: Amsterdam HQ; EMEA majority, NA fastest-growing
- **Market cap**: **€27.5B** (Yahoo Finance, 2026-06-04)
- **Listed on**: Euronext Amsterdam (ADYEN.AS)
- **Broker**: DEGIRO

## Thesis
Single global stack — in-house, no acquisitions — processing in-store + online + payouts on one ledger. Few credible enterprise-scale peers: Stripe private, Worldpay/Fiserv on legacy rails, PayPal/Braintree losing share. Post-2023 management reset slowed hiring; FY2025 delivered margin recovery to 53% (H2 55%) on €2.36B net revenue (+21% cc). 2026 guide: 20–22% growth, margin held, 55%+ targeted by 2028. Co-founder van der Does stepped back; Ingo Uytdehaage sole CEO.

## Key Catalysts
- [x] **FY2025 print — delivered ✅** (53% margin, 21% cc growth)
- [ ] H1 2026 print (Aug 2026) — sustains margin ≥53% and growth ≥20%
- [ ] Margin trajectory to 55%+ target (2028)
- [ ] Unified Commerce volume mix rising
- [ ] AI / agentic-commerce payment standards adoption
- [ ] First-ever buyback authorization

## Valuation (live, 2026-06-04)
| Metric | Value |
|--------|-------|
| Price | **€871.90** (Yahoo Finance, intraday -2%) |
| 52-week range | **€824 – €1,750** (near low) |
| ATH (Nov 2021) | ~€2,768 (~68% below) |
| Market cap | **€27.5B** |
| P/E TTM | **25.9×** |
| FY2025 net revenue | **€2,364M (+21% cc)** |
| FY2025 EBITDA | **€1,246M (+26%), 53% margin (H2 55%)** |
| 2026 guide | +20–22% growth, ~53% margin |
| EV / FY25 EBITDA | ~22× |
| EV / FY25 net revenue | ~11.6× |

### Fair Value Scenarios (rebuilt at €872)
| Scenario | Price | Driver |
|----------|-------|--------|
| Bear | €700 | Growth → mid-teens, margin stalls 53%, derates to 18× EBITDA |
| **Base** | **€1,150** | 20% growth, 53% margin holds, 24× EBITDA → ~+32% |
| Bull | €1,500+ | 22%+ growth, margin → 55%, 28× EBITDA → ~+72% |

## Risks
1. Stripe IPO / NA price-led competition
2. Mega-merchant concentration (Uber, Spotify, Meta, eBay, McDonald's)
3. Margin reversal (hiring re-acceleration) → 2023 episode rerun
4. FX (~30%+ non-EUR revenue)
5. Founder dilution of engineering-led culture post van der Does
6. Long-tail: stablecoin / PSD3 take-rate compression

## Portfolio Fit
- **Bucket**: European Equities — sleeve currently underweight (~14% vs. 20% target)
- **Max size**: 4–5% of portfolio
- **Broker**: DEGIRO (whole-share OK at €872) or TR fractional
- **Hold period**: 3–5 years
- **Overlap**: zero payments/fintech exposure → genuine diversifier" \
  "## My Decision  ← edit this directly on GitHub, it won't be overwritten
- [x] Buy — entry zone: €800–900 · size: 4–5% target · scale on weakness to €750
- [ ] Watch — revisit when:
- [ ] Pass — reason: ___

## Price Alerts
- Initial entry zone: €800–900 (current)
- Add aggressively: <€800
- Take some off: ≥€1,200 (base case hit)

## Notes
| Date | Note |
|------|------|
| 2026-06-04 | **Revised after live data check.** Initial draft used stale price (€1,600); real €871.90 near 52-wk low. FY2025 delivered margin 53% (H2 55%) and 21% cc growth — watch trigger fired. Base FV €1,150 (24× EV/FY26E EBITDA). |"

# ── Issue 6: ASML ───────────────────────────────────────────────
upsert_issue \
  "[IDEA] ASML — ASML Holding (EUV Monopoly)" \
  "idea,researching,europe,technology" \
  "## One-Line Thesis
Dutch crown jewel — only EUV lithography supplier on Earth. Quasi-monopoly with 30y compounded R&D, Carl Zeiss optics lock-in, €38.8B backlog. **Quality undisputed; entry price is the question.** Currently at 52-wk HIGH.

## Business Overview
- **Sector**: Semiconductors (capital equipment)
- **Geography**: HQ Veldhoven NL; customers TSMC, Intel, Samsung, SK Hynix, Micron
- **Market cap**: **€567.9B** (2026-06-05)
- **Listed on**: Euronext Amsterdam (ASML.AS); also NASDAQ
- **Broker**: DEGIRO

## Thesis
Only company that builds EUV lithography (sub-7nm chips impossible without it). Each machine €150–350M. Customer wait years. Backlog €38.8B YE25. Q1 2026: rev €8.8B (+13%), EPS €7.15, net income €2.8B (+17%). FY26 guide lifted to €36–40B. China down to 19% of sys (from 36%) — absorbed without breaking guidance. AI capex cycle extends.

## Key Catalysts
- [ ] Q2 2026 earnings (Jul 2026) confirms FY guide
- [ ] High-NA EUV unit shipments accelerate
- [ ] AI infra capex cycle extends through 2027
- [ ] €60B/2030 revenue ambition signals
- [ ] Capital return — active buyback + growing dividend

## Valuation (2026-06-05)
| Metric | Value |
|--------|-------|
| Price | **€1,473.40** |
| 52-week range | **€587.80 – €1,496** (near HIGH) |
| Market cap | **€567.9B** |
| Q1 2026 revenue | €8.8B (+13%) |
| FY2026 guide | €36–40B (raised) |
| Forward P/E | ~37–42× (premium vs. 10y median ~30×) |
| EV/FY26E revenue | ~14× |
| Backlog | €38.8B YE25 |

### Fair Value Scenarios
| Scenario | Price | Driver |
|----------|-------|--------|
| Bear | €1,050 | Cycle peak, multiple to 28× |
| **Base** | **€1,400** | FY26 €38B, slow grind sideways |
| Bull | €1,900 | High-NA inflects, FY27 €48B+, re-rates to 40× |

## Risks
1. Cycle risk at peak multiple
2. US/China export controls escalate further
3. High-NA execution
4. Customer concentration (TSMC/Samsung/Intel ~60%+)
5. Single-source supplier dependencies (Zeiss/Cymer)
6. Multiple compression — even on good news

## Portfolio Fit
- **Bucket**: Quality Compounders sleeve (revised 15%) / Global Eq tilt
- **Max size**: 5%
- **Broker**: DEGIRO; €1,473 single share = ~13% of €11.4k current book — wait for book to grow OR price to pull back
- **Hold period**: 5–10 years (multi-cycle)" \
  "## My Decision  ← edit this directly on GitHub, it won't be overwritten
- [ ] Buy — entry zone: **<€1,250 (15% pullback)** · size: 5% · aggressive add <€1,050
- [x] Watch — revisit when: pullback to €1,250 OR FY27 €44B+ trajectory confirmed
- [ ] Pass — reason: ___

## Price Alerts
- First entry: <€1,250
- Aggressive add: <€1,050

## Notes
| Date | Note |
|------|------|
| 2026-06-05 | Initial. €1,473 near 52-wk high €1,496. Quality undisputed; price the issue. Wait for pullback. |"

# ── Issue 7: Topicus ─────────────────────────────────────────────
upsert_issue \
  "[IDEA] TOI — Topicus.com (EU VMS Roll-up)" \
  "idea,researching,europe,technology" \
  "## One-Line Thesis
Constellation Software spin-out (2021) applying Mark Leonard's VMS roll-up playbook to fragmented European software. Q1 2026 revenue +23% (5% organic), FCF compounding. Stock ~47% below 52-wk high. Classic compounder at a discount.

## Business Overview
- **Sector**: Vertical-Market Software roll-up
- **Geography**: HQ Deventer NL; ~150 European VMS companies
- **Market cap**: **CAD \$8.71B** (~€5.9B, 2026-06-05)
- **Listed on**: **TSX Venture (TOI.V)** primary; also Euronext Amsterdam (TOPCS.AS, lower vol)
- **Broker**: DEGIRO (TSX-V access)

## Thesis
Acquires niche EU software at 4–6× cashflow, holds forever, redeploys. Same playbook as Constellation parent (1000-bagger since 2006). EU 5–10y behind NA in software consolidation = fresher hunting ground. Q1 2026 rev €435.7M (+23%, 5% organic). FCF available to shareholders €165.4M. Net income dip (€55.1M, -€15M YoY) is acquisition front-loading — not deterioration.

## Key Catalysts
- [ ] Q2 2026 — acquisition pipeline + margin normalization
- [ ] Major large acquisition (€20M+ deals scaling)
- [ ] Sustained 20%+ revenue growth
- [ ] Constellation parent strength (sentiment correlation)
- [ ] EU public-sector software wave (PSD3, eIDAS)

## Valuation (2026-06-05)
| Metric | Value |
|--------|-------|
| Price | **CAD \$104.55** |
| 52-week range | **CAD \$82.67 – \$199.00** |
| Market cap | **CAD \$8.71B** (~€5.9B) |
| Q1 2026 revenue | €435.7M (+23%, 5% organic) |
| Q1 2026 net income | €55.1M (-€15M YoY) |
| Q1 2026 FCF | €165.4M |
| P/E TTM | ~174× (lumpy — intangible amort) |
| EV/NTM revenue | ~3.5× |
| EV/FCF | ~13–15× (cleaner metric) |

> GAAP P/E heavily distorted by intangible amortization. EV/FCF ~14× for a 20%+ grower is cheap.

### Fair Value Scenarios
| Scenario | Price | Driver |
|----------|-------|--------|
| Bear | CAD \$80 | Acquisition pace slows, organic <4% |
| **Base** | **CAD \$150** | EV/FCF re-rates to 18× on €750M+ FCF |
| Bull | CAD \$200+ | 25% growth, EV/FCF 22×, retest ATH |

## Risks
1. TSX-V listing for EUR-revenue Dutch company — FX overhead
2. Capital allocation engine slowing (bigger deals harder to find at 4–6×)
3. Multi-year governance / CEO discipline drift risk
4. GAAP earnings volatility scaring incremental buyers
5. TSX-V liquidity in volatile periods
6. EU labor-cost inflation compressing margins

## Portfolio Fit
- **Bucket**: Quality Compounders sleeve (revised 15%)
- **Max size**: 3–4%
- **Broker**: DEGIRO
- **Hold period**: 5–10 years
- **Tax angle**: CAD-denominated, no NL withholding on token divs" \
  "## My Decision  ← edit this directly on GitHub, it won't be overwritten
- [x] **Buy — entry zone: CAD \$100–110 (current)** · size: 3–4% scale-in over 6 months
- [ ] Watch — revisit when:
- [ ] Pass — reason: ___

## Price Alerts
- Buy zone: CAD \$95–115
- Aggressive add: <CAD \$90

## Notes
| Date | Note |
|------|------|
| 2026-06-05 | Initial. Stock at 52-wk low while operational engine delivering 23% growth. Classic disconnect. Mark Leonard playbook intact. Base FV CAD \$150. |"

# ── Issue 8: Sea Limited ─────────────────────────────────────────
upsert_issue \
  "[IDEA] SE — Sea Limited (SE Asia Triple-Engine)" \
  "idea,researching,thematic,speculative" \
  "## One-Line Thesis
SE Asia's digital flywheel — Shopee (#1 in 7/8 markets) + Garena (Free Fire back to record bookings) + SeaMoney (loans +71%) all firing. Q1 2026 record rev \$7.1B (+47%), adj EBITDA \$1B. Stock near 52-wk LOW (~76% below ATH). Operationally inflecting; market hasn't noticed.

## Business Overview
- **Sector**: EM Internet (e-commerce + gaming + fintech)
- **Geography**: HQ Singapore; SE Asia + Brazil
- **Market cap**: **\$55.4B** (2026-06-05)
- **Listed on**: NYSE (SE)
- **Broker**: DEGIRO

## Thesis
Three businesses, all inflecting Q1 2026:
1. **Shopee**: \$5.1B rev (+45%), GMV \$37.3B (+30%)
2. **Garena**: \$931M bookings (+20%), 61.6% EBITDA margin — best in 5y
3. **SeaMoney**: \$1.2B rev (+58%), loans \$9.9B (+71%), 38M credit users (+35%)

Post-2022 reset complete. Now compounding all three with positive operating leverage. Market still pricing 2022 loss-machine.

## Key Catalysts
- [ ] Q2 2026 (Aug) confirms 40%+ Shopee growth, SeaMoney NPL <3%
- [ ] SeaMoney standalone valuation (~\$20B+ at fintech multiples)
- [ ] Indonesia regulatory clarity (TikTok Shop restrictions favor incumbents)
- [ ] First buyback / special div
- [ ] AI-driven logistics efficiency at Shopee

## Valuation (2026-06-05)
| Metric | Value |
|--------|-------|
| Price | **\$90.53** |
| 52-week range | **\$77.05 – \$199.30** (near LOW) |
| ATH (Oct 2021) | ~\$370 (~76% below) |
| Market cap | **\$55.4B** |
| P/E TTM | **35.6×** (EPS \$2.54) |
| Q1 2026 revenue | \$7.1B (+47%) |
| Q1 2026 adj EBITDA | \$1.0B |
| FY2026E revenue | ~\$28B |
| EV/FY26E revenue | ~2× |

### Fair Value Scenarios
| Scenario | Price | Driver |
|----------|-------|--------|
| Bear | \$65 | Shopee → 20% growth, SeaMoney NPL spike |
| **Base** | **\$135** | 2.5× EV/Rev, ~16% adj EBITDA margin |
| Bull | \$200+ | All 3 engines hit, SeaMoney crystallizes |

## Risks
1. TikTok Shop competition in Indonesia (~40% of GMV)
2. SeaMoney credit blow-up (loans +71% = real underwriting risk)
3. Garena Free Fire single-title concentration
4. FX / EM volatility (IDR, BRL, THB)
5. SE Asia regulatory fragmentation
6. Promotional environment (Lazada / TikTok force margin compression)
7. Tencent ~10% overhang

## Portfolio Fit
- **Bucket**: **Home-Run sleeve** (revised 5%)
- **Max size**: 2–3% (could 5× or halve)
- **Broker**: DEGIRO USD
- **Hold period**: 5+ years
- **Drawdown**: must hold through 40%+; already has happened twice since 2021" \
  "## My Decision  ← edit this directly on GitHub, it won't be overwritten
- [x] **Buy — entry zone: \$85–95 (current)** · size: 2–3% as home-run pick · scale-in 2 tranches
- [ ] Watch — revisit when:
- [ ] Pass — reason: ___

## Price Alerts
- Buy zone: \$85–95
- Aggressive add: <\$80
- Take some off: >\$160 (base hit)

## Notes
| Date | Note |
|------|------|
| 2026-06-05 | Initial. Triple-engine flywheel inflecting at 52-wk low. Asymmetric: base +49%, bull +120%, bear -28%. Home-run sleeve fit. |"

# ── Issue 9: Spotify ─────────────────────────────────────────────
upsert_issue \
  "[IDEA] SPOT — Spotify (Operating Leverage Inflection)" \
  "idea,researching,technology" \
  "## One-Line Thesis
Operating-leverage inflection — Spotify hit profitability 2024, Q1 2026 GM 33% (+133bps), op margin 15.8%, on 12% MAU growth and pricing power. Stock near 52-week LOW. Market still pricing 2022 loss-maker, not 2026 cashflow compounder.

## Business Overview
- **Sector**: Media / Internet (audio streaming)
- **Geography**: HQ Stockholm; global; ADR
- **Market cap**: **\$101.5B** (2026-06-05)
- **Listed on**: NYSE (SPOT)
- **Broker**: DEGIRO USD

## Thesis
Reached fundamental scale. 761M MAU (+12%), 293M Premium subs (+10%), Q1 2026 rev €4.53B (+8%, +14% cc), GM 33% (+133bps), op income €715–780M (15.8% margin). 'Labels take all margin' narrative empirically broken. Pricing power holding from 2023–2024 hikes. Audiobooks bundling is the new growth lever.

## Key Catalysts
- [ ] Q2 2026 (Jul) confirms €4.8B (+15%), 778M MAU
- [ ] GM trajectory toward 35%+ over next 4 quarters
- [ ] Audiobook monetization scaling
- [ ] Next price hike (last Jul 2024)
- [ ] Buyback expansion or first dividend
- [ ] AI-DJ / generative tools monetization

## Valuation (2026-06-05)
| Metric | Value |
|--------|-------|
| Price | **\$493.58** |
| 52-week range | **\$405 – \$785** (near LOW) |
| Market cap | **\$101.5B** |
| P/E TTM | **32.9×** (EPS \$15.02) |
| Q1 2026 revenue | €4.53B (+8%, +14% cc) |
| Q1 2026 op income | €715–780M (15.8% margin) |
| FY2026E revenue | ~€19B (+12%) |
| FY2026E op margin | ~16% |
| EV/FY26E revenue | ~5× |
| Gross margin | 33% (+133bps YoY) |

### Fair Value Scenarios
| Scenario | Price | Driver |
|----------|-------|--------|
| Bear | \$400 | NA sub decline structural, GM stalls 33% |
| **Base** | **\$650** | 35× P/E on \$18 EPS, margin expansion holds |
| Bull | \$850+ | GM → 35–37%, op margin 20%+, re-rates to 40× |

## Risks
1. **NA subscriber decline (Q1 noted)** — kill-switch
2. Pricing power ceiling (parity with Apple Music / YouTube)
3. Label re-negotiation risk
4. Podcasting wave over; audiobook smaller TAM
5. AI music dilution (Suno, Udio) 5y horizon
6. FX (mixed USD/EUR exposure)
7. Founder voting concentration (Daniel Ek)

## Portfolio Fit
- **Bucket**: Quality Compounders sleeve (revised 15%)
- **Max size**: 3–4%
- **Broker**: DEGIRO USD
- **Hold period**: 3–5 years (margin expansion cycle)
- **Kill-switch**: 2 consecutive quarters of NA Premium decline = stop adding" \
  "## My Decision  ← edit this directly on GitHub, it won't be overwritten
- [x] **Buy — entry zone: \$450–500 (current)** · size: 3–4% scale-in over 6 months
- [ ] Watch — revisit when:
- [ ] Pass — reason: ___

## Price Alerts
- Buy zone: \$450–500
- Stop adding: 2 consecutive quarters NA Premium decline
- Take some off: >\$650 (base hit)

## Notes
| Date | Note |
|------|------|
| 2026-06-05 | Initial. Record op income at 52-wk low = disconnect. NA sub trend is kill-switch. Base FV \$650 (+32%). |"

# ── Issue 10: Hims & Hers ────────────────────────────────────────
upsert_issue \
  "[IDEA] HIMS — Hims & Hers (DTC Telehealth)" \
  "idea,researching,speculative" \
  "## One-Line Thesis
DTC telehealth platform with 2.6M subscribers pivoting from compounded GLP-1s (FDA letter March 2026) to official Novo Nordisk Wegovy distributor. 60% off 52-wk high. Asymmetric — could compound into real platform OR get stuck as high-CAC distributor.

## Business Overview
- **Sector**: Telehealth / DTC consumer health
- **Geography**: US-focused
- **Market cap**: **\$6.48B** (2026-06-05)
- **Listed on**: NYSE (HIMS)
- **Broker**: DEGIRO USD

## Thesis
Subscription DTC across hair, ED, weight loss, mental health, derm. 2.6M subs (+9%). FDA letters March 2026 forced pivot from compounded to branded GLP-1; signed Novo Nordisk deal as official Wegovy/Ozempic distributor. 125k shipments in 6 weeks. Q1 2026 messy (net loss \$92M, adj EBITDA \$44M down from \$91M) — restructuring + lower-margin branded GLP-1. FY26 guide raised to \$2.8–3.0B (+19–28%), adj EBITDA \$275–350M (~11% margin). Higher uncertainty than other names; sized accordingly.

## Key Catalysts
- [ ] Q2 2026 (Aug) — margin recovery + Wegovy attach rate
- [ ] Subscriber growth re-accelerates past 3M
- [ ] Non-GLP-1 categories (mental health, derm) >25% growth
- [ ] Eli Lilly partnership (Zepbound/Mounjaro)
- [ ] International expansion (UK pilot)
- [ ] Buyback at \$28 plausible with \$300M+ cash

## Valuation (2026-06-05)
| Metric | Value |
|--------|-------|
| Price | **\$28.01** |
| 52-week range | **\$13.74 – \$70.43** (~60% below high) |
| Market cap | **\$6.48B** |
| P/E TTM | 57× (EPS -\$0.09 negative recent) |
| Q1 2026 revenue | \$608M (+4%, missed) |
| Q1 2026 net loss | \$92M |
| Q1 2026 adj EBITDA | \$44M (-50% YoY) |
| FY2026 guide | \$2.8–3.0B rev (+19–28%) |
| FY2026 EBITDA guide | \$275–350M (~11% margin) |
| EV/FY26E revenue | ~2.2× |
| EV/FY26E EBITDA | ~21× midpoint |

### Fair Value Scenarios
| Scenario | Price | Driver |
|----------|-------|--------|
| Bear | \$18 | Sub growth stalls, Novo economics squeeze, regulatory drag |
| **Base** | **\$40** | FY26 \$2.9B / \$310M EBITDA, 2.5× revenue holds |
| Bull | \$70+ | 4M+ subs, Lilly deal, intl launch, 3.5× revenue |

## Risks
1. **GLP-1 regulatory whiplash** — another shoe every 3–6 months
2. Branded-GLP-1 unit economics structurally lower than compounded
3. Subscriber CAC degrading at scale
4. Weight-loss revenue concentration (~50%+ of incremental)
5. Competition — Ro, Noom, LillyDirect
6. SBC ~15% of revenue (dilutive)
7. Meme-stock volatility / short interest

## Portfolio Fit
- **Bucket**: **Home-Run sleeve** (revised 5%)
- **Max size**: 1.5–2% (smaller than SE due to binary regulatory risk)
- **Broker**: DEGIRO USD
- **Hold period**: 3–5 years
- **Drawdown**: must hold through 40%+; has already drawn down 60%" \
  "## My Decision  ← edit this directly on GitHub, it won't be overwritten
- [ ] Buy — entry zone: \$25–28 · size: 1.5–2%
- [x] **Watch — revisit when: Q2 2026 confirms margin recovery + sub growth >3M, OR price <\$20**
- [ ] Pass — reason: ___

## Price Alerts
- Aggressive entry: <\$20
- Stop-watching: any new FDA action

## Notes
| Date | Note |
|------|------|
| 2026-06-05 | Initial. vs SE Limited: HIMS has more binary regulatory risk + weaker Q1. Watch, not buy now. Better risk/reward in SE for same sleeve allocation. |"

# ── Issue 11: Nebius ─────────────────────────────────────────────
upsert_issue \
  "[IDEA] NBIS — Nebius Group (EU AI Cloud)" \
  "idea,researching,europe,technology,speculative" \
  "## One-Line Thesis
Dutch-incorporated AI cloud (Yandex non-Russia rump) — Q1 2026 rev \$399M (+684%), \$9.3B net cash, building 4GW contracted capacity. Real European GPU cloud at hyperscale. **Quality compelling; entry rich — near 52-wk HIGH \$259.**

## Business Overview
- **Sector**: AI infrastructure / GPU cloud
- **Geography**: Dutch-incorporated; data centers Finland, Israel, Philadelphia
- **Market cap**: **\$65.9B** (2026-06-05)
- **Listed on**: NASDAQ (NBIS)
- **Broker**: DEGIRO USD

## Thesis
Rump of Yandex post-Russia divestiture. \$9.3B cash from carve-out funds buildout. Q1 2026: AI cloud rev \$390M (+841%), group EBITDA margin 32%. 2026 guide: \$3.0–3.4B revenue, \$7–9B exit run rate, ~40% EBITDA margin. CapEx \$20–25B. Founder Volozh leading. **Debt-light vs CRWV's \$24.8B debt.**

## Key Catalysts
- [ ] Q2 2026 (Aug) — 4GW capacity progress
- [ ] Hyperscaler-class customer wins
- [ ] Philadelphia 1.2GW facility milestones
- [ ] Exit run rate trajectory to \$9B
- [ ] First GAAP positive earnings

## Valuation (2026-06-05)
| Metric | Value |
|--------|-------|
| Price | **\$259.67** |
| 52-week range | **\$41.40 – \$278.84** (near HIGH) |
| Market cap | **\$65.9B** |
| Cash | **\$9.3B** |
| Q1 2026 revenue | \$399M (+684%) |
| 2026 guide | \$3.0–3.4B (run rate \$7–9B) |
| 2026 CapEx | \$20–25B (raised) |
| EV/2026E revenue | ~17× |
| EV/exit run rate | ~7× |

### Fair Value Scenarios
| Scenario | Price | Driver |
|----------|-------|--------|
| Bear | \$130 | CapEx blowout, dilution, multiple to 8× run rate |
| **Base** | **\$290** | Top of guide, holds 7× run rate |
| Bull | \$450+ | Hyperscaler win, 10× run rate |

## Risks
1. CapEx execution (\$20–25B 2026)
2. GPU utilization (Philadelphia must fill)
3. Customer concentration (few large AI labs)
4. AI capex cycle peak risk
5. Russia legacy / OFAC scrutiny
6. GPU obsolescence (Blackwell → Vera Rubin)
7. Multiple compression at 17× FY26 rev

## Portfolio Fit
- **Bucket**: Home-Run sleeve (5%)
- **Max size**: 2%
- **Broker**: DEGIRO USD
- **Hold**: 3–5y
- **Dutch fit**: NL-incorporated, Box 3 standard" \
  "## My Decision  ← edit this directly on GitHub, it won't be overwritten
- [ ] Buy — entry zone: **<\$210 (20% pullback)** · size: 2% home-run · aggressive add <\$160
- [x] **Watch — revisit when:** pullback to \$210 OR Q2 confirms 4GW + customer diversification
- [ ] Pass — reason: ___

## Price Alerts
- First entry: <\$210
- Aggressive add: <\$160

## Notes
| Date | Note |
|------|------|
| 2026-06-05 | Initial. Quality compelling at 52-wk high after 6× run. Right name, wrong moment. Cleaner balance sheet than CRWV. |"

# ── Issue 12: CoreWeave ─────────────────────────────────────────
upsert_issue \
  "[IDEA] CRWV — CoreWeave (NVDA's AI GPU Cloud)" \
  "idea,researching,speculative" \
  "## One-Line Thesis
NVDA's chosen AI GPU cloud — Q1 2026 rev \$2.08B (+112%), \$99B backlog, MSFT concentration cut 72%→45%. But **\$24.8B debt, \$740M Q1 loss, \$2.1B annualized interest** — capital structure is the kill-switch. Likely PASS in favor of NBIS.

## Business Overview
- **Sector**: AI GPU cloud / data center
- **Geography**: HQ Roseland NJ; US data centers
- **Market cap**: **\$69.4B** (2026-06-05)
- **Listed on**: NASDAQ (CRWV)
- **Broker**: DEGIRO USD

## Thesis
NVDA preferred cloud — first to deploy Blackwell + Vera Rubin NVL72 (+16% intraday on news). Q1 2026 rev \$2.08B (+112%), backlog \$99.4B (4× YoY), 10 customers \$1B+. MSFT concentration 45% (was 72%). **But debt \$24.8B vs equity \$4.8B**, Q1 interest \$536M. IPO Mar 2025 at \$40, now \$127 (3.2×). Capital structure carries existential risk on any AI capex slowdown.

## Key Catalysts
- [ ] Q2 2026 backlog conversion pace
- [ ] First positive op income
- [ ] MSFT customer concentration <35%
- [ ] Vera Rubin NVL72 milestones
- [ ] Debt refinancing at improved terms
- [ ] OpenAI / Oracle / Meta customer commits

## Valuation (2026-06-05)
| Metric | Value |
|--------|-------|
| Price | **\$127.30** (+16.22% intraday) |
| 52-week range | **\$63.80 – \$187** |
| IPO price (Mar 2025) | \$40 (3.2× since) |
| Market cap | **\$69.4B** |
| Total debt | **\$24.8B** |
| Equity | \$4.8B (heavily levered) |
| Q1 2026 revenue | \$2.08B (+112%) |
| Q1 2026 net loss | -\$740M |
| Q1 interest expense | \$536M (\$2.1B annualized) |
| Customer A (MSFT) | 45% (was 72%) |
| EV/2026E revenue | ~12× |

### Fair Value Scenarios
| Scenario | Price | Driver |
|----------|-------|--------|
| Bear | \$70 | AI slowdown, util 70%, interest overwhelms ops |
| **Base** | **\$145** | Backlog converts at projected pace |
| Bull | \$220+ | Vera Rubin + OpenAI/Oracle, MSFT <30% |

## Risks
1. **Capital structure** — \$24.8B debt vs \$4.8B equity, \$2.1B annualized interest
2. NVDA dependency cuts both ways
3. MSFT 45% still concentrated
4. GPU obsolescence (Blackwell → Vera Rubin write-downs)
5. Hyperscalers shift to in-house silicon (TPU, MTIA, Trainium)
6. SBC + dilution
7. Customer credit risk (many AI labs unprofitable)

## Portfolio Fit
- **Bucket**: Home-Run sleeve (5%)
- **Max size**: 1–1.5% (smaller than NBIS due to debt)
- **Broker**: DEGIRO USD
- **Hold**: 2–4y, binary AI capex cycle
- **Drawdown**: debt structure makes 60–70% drops plausible" \
  "## My Decision  ← edit this directly on GitHub, it won't be overwritten
- [ ] Buy — entry zone: **<\$85** · size: 1.5% max (binary risk)
- [x] **Watch — revisit when:** debt restructured, interest coverage >2×, OR price <\$85
- [ ] **Likely PASS in favor of NBIS** — cleaner balance sheet for same theme

## Price Alerts
- Aggressive entry only: <\$80

## Notes
| Date | Note |
|------|------|
| 2026-06-05 | Initial. NBIS captures same theme with \$9.3B cash vs CRWV's \$24.8B debt. Pass-leaning. |"

# ── Issue 13: Sandisk ───────────────────────────────────────────
upsert_issue \
  "[IDEA] SNDK — Sandisk (NAND Cycle-Peak Warning)" \
  "idea,passed,technology,speculative" \
  "## One-Line Thesis
NAND spinoff from WDC (Feb 2025) riding AI demand. **Stock up ~47× since spinoff** to \$1,759. Q3 FY26 GM 78.4% (vs 22.5% YoY) = canonical cycle peak. PASS at current price.

## Business Overview
- **Sector**: Memory semiconductors (NAND flash)
- **Geography**: HQ Milpitas CA; Kioxia JV (Japan)
- **Market cap**: **\$260.6B** (2026-06-05)
- **Listed on**: NASDAQ (SNDK)
- **Broker**: DEGIRO USD

## Thesis (the cyclical reality)
Q3 FY26 rev \$5.95B (+251%), GM 78.4% (vs 22.5% YoY), DC rev \$1.47B (+645%). Q4 guide \$7.75–8.25B, GM 79–81%. NAND prices +60% Q1, +70–75% forecast Q2. **Every prior memory upcycle ended with 50%+ drawdowns within 6 months of margin peak.** This IS the peak. Capacity additions hit 12–18 months out. Quality of business average; quality of cycle moment extreme.

## Key Catalysts (mostly negative)
- [ ] Q4 FY26 earnings — confirm \$8B+ revenue
- [ ] Kioxia/Sandisk M&A
- [ ] **(NEGATIVE)** Samsung/SK Hynix capacity announcement
- [ ] **(NEGATIVE)** Spot NAND price decline = first inning of turn

## Valuation (2026-06-05)
| Metric | Value |
|--------|-------|
| Price | **\$1,759.68** |
| 52-week range | **\$37.33 – \$1,861** (~47× from low) |
| Market cap | **\$260.6B** |
| P/E TTM | 60× (EPS \$29.30) |
| Forward P/E | **27×** (if margins hold — they won't) |
| Q3 FY26 revenue | \$5.95B (+251%) |
| Q3 FY26 GM | 78.4% (vs 22.5% YoY) |
| Datacenter rev | \$1.47B (+645%) |
| NAND price | +60% Q1, +70–75% Q2 est |

### Fair Value Scenarios (cyclical)
| Scenario | Price | Driver |
|----------|-------|--------|
| Bear | \$400 | Cycle peak Q3 26, capacity hits, GM → 35%, EPS → \$10 |
| Mid-cycle | \$700–1,000 | Normalized GM ~45%, EPS \$18–22 |
| Bull | \$2,500 | AI defies memory cycle (requires precedent) |

## Risks
1. **Memory cycle** — most cyclical sub-industry, 50–75% drawdowns standard
2. Samsung/SK Hynix/Micron capacity additions inbound
3. NAND spot price volatility = first inning of GM compression
4. Single-product (no DRAM buffer like Micron)
5. Kioxia JV concentration risk
6. AI demand elasticity unknown
7. New mgmt team, post-spinoff alignment unproven

## Portfolio Fit
- ~~Quality Compounders~~ — doesn't fit (cyclical, not compounding)
- Home-Run only at **<\$500** (cycle trough setup)
- **Hold-through-40% rule violated by cycle-peak entry**" \
  "## My Decision  ← edit this directly on GitHub, it won't be overwritten
- [ ] Buy — only at: **<\$500** (cycle trough)
- [ ] Watch — revisit when: NAND spot prices crack
- [x] **PASS — buying NAND at 78% GM is canonical bag-holder trade.** Memory cycles brutal. Skip.

## Price Alerts
- Set alert: <\$600 (cycle bottom watch)

## Notes
| Date | Note |
|------|------|
| 2026-06-05 | Initial. \$1,759, up 47× since Feb 2025 spinoff. Q3 FY26 GM 78.4% = peak. Pass. The 47× already happened. |"

# ── Issue 14: AMD ───────────────────────────────────────────────
upsert_issue \
  "[IDEA] AMD — Advanced Micro Devices (AI Duopoly)" \
  "idea,researching,technology" \
  "## One-Line Thesis
Genuine quality compounder — only credible NVDA challenger in AI GPUs (Instinct MI300/450). Q1 2026 rev \$10.3B (+38%), Data Center \$5.8B (+57%), Meta 6GW deployment win. **Best business of the AI-infra basket; stock at 52-wk HIGH after ~4.5× run.**

## Business Overview
- **Sector**: Semiconductors (CPU + GPU + accelerators)
- **Geography**: HQ Santa Clara; TSMC manufacturing
- **Market cap**: **\$853B** (2026-06-05)
- **Listed on**: NASDAQ (AMD)
- **Broker**: DEGIRO USD

## Thesis
Only credible second source for AI compute. Q1 2026: DC \$5.8B (+57%), MI300-series ~73% of DC (>\$4.2B/Q). Q2 guide \$11.2B. **Meta 6GW Instinct deployment** (first 1GW custom MI450) = most credible non-NVDA AI buildout. EPYC server share grinding higher (AWS/Azure/GCP/Tencent). Lisa Su tenure since 2014 is deepest quality signal. Timing problem, not quality problem.

## Key Catalysts
- [ ] Q2 2026 (Jul) — confirm \$11.2B + MI300+ trajectory
- [ ] MI450 production ramp + Meta milestones
- [ ] ROCm software adoption signals
- [ ] 2027 DC \$40B+ ambition
- [ ] Additional hyperscaler commits beyond Meta
- [ ] PC market recovery (Client ~25%)

## Valuation (2026-06-05)
| Metric | Value |
|--------|-------|
| Price | **\$523.20** |
| 52-week range | **\$114.71 – \$546.44** (near HIGH; 4.5× from low) |
| Market cap | **\$853B** |
| P/E TTM | **175×** (EPS \$2.98, depressed) |
| Forward P/E | **74.6×** |
| Q1 2026 revenue | \$10.3B (+38%) |
| Q1 2026 DC | \$5.8B (+57%) |
| Q2 2026 guide | \$11.2B |
| FY2026E revenue | ~\$45B |
| EV/FY26E revenue | ~19× |
| Forward P/E 2027E | ~50× (if EPS hits \$10+) |

### Fair Value Scenarios
| Scenario | Price | Driver |
|----------|-------|--------|
| Bear | \$320 | ROCm fails, hyperscalers go in-house, 35× on \$9 2027 EPS |
| **Base** | **\$560** | FY26 \$45B, FY27 \$60B, 56× on \$10 EPS |
| Bull | \$800 | MI450 wins broad, FY27 \$70B+, re-rates to 62× |

## Risks
1. NVDA CUDA moat (ROCm trails 3–5 years)
2. Hyperscaler in-house silicon (TPU, MTIA, Trainium)
3. TSMC concentration / geopolitics
4. **Valuation at 75× forward** — multiple compression on any miss
5. PC/Gaming cycle drag (~30% of revenue)
6. AI capex deceleration narrative
7. Lisa Su succession unclear

## Portfolio Fit
- **Bucket**: Quality Compounders sleeve (revised 15%)
- **Max size**: 4–5%
- **Broker**: DEGIRO USD
- **Hold**: 5–10y
- **Theme overlap**: same as ASML, NBIS, CRWV — pick ONE large AI-infra Quality position" \
  "## My Decision  ← edit this directly on GitHub, it won't be overwritten
- [ ] Buy — entry zone: **<\$420** (20% pullback) · size: 4–5% Quality · aggressive add <\$330
- [x] **Watch — revisit when:** pullback to \$420 OR Q2 confirms FY26 \$45B trajectory
- [ ] Pass — reason: ___

## Price Alerts
- First entry: <\$420
- Aggressive add: <\$330

## Notes
| Date | Note |
|------|------|
| 2026-06-05 | Initial. Quality real. Parallel to ASML — right name, wrong moment at 52-wk high. Wait for <\$420. |"

# ── Issue 15: Solaris Energy ────────────────────────────────────
upsert_issue \
  "[IDEA] SEI — Solaris Energy Infra (Data Center Power)" \
  "idea,passed,speculative" \
  "## One-Line Thesis
Oil/gas equipment co. pivoted to data-center power (gas turbines, mobile power). Q1 2026 rev \$196M (+55%), 2GW+ contracted. **Real pivot, real execution, but stock 3× from low + 52-wk high = priced for it. PASS for now in favor of SE + NBIS.**

## Business Overview
- **Sector**: Energy infrastructure / power generation
- **Geography**: HQ Houston TX
- **Market cap**: **\$7.13B** (2026-06-05)
- **Listed on**: NYSE (SEI)
- **Broker**: DEGIRO USD

## Thesis
Former oilfield-sand co. pivoted to natural-gas-fired mobile generation for AI data centers. Q1 2026: rev \$196M (+55%), adj EBITDA \$84M (43% margin, +79% YoY). Capacity 3.1GW (+40% YTD) via Genco + NovaLT16 acquisitions. **2GW+ long-term hyperscaler contracts.** Q2/Q3 EBITDA guide \$80–95M. Real catalyst (grid lead times), but cyclical/tactical not compounder.

## Key Catalysts
- [ ] Q2 2026 (Jul) — confirm \$83–93M EBITDA
- [ ] New ≥500MW hyperscaler contracts
- [ ] Additional turbine acquisitions
- [ ] Long-duration (5y+) contract conversions
- [ ] **(NEGATIVE)** Competitor capacity announcements

## Valuation (2026-06-05)
| Metric | Value |
|--------|-------|
| Price | **\$76.31** |
| 52-week range | **\$24.57 – \$81.24** (near HIGH; ~3.1× from low) |
| Market cap | **\$7.13B** |
| P/E TTM | 90× (EPS \$0.84) |
| Q1 2026 revenue | \$196M (+55%) |
| Q1 2026 adj EBITDA | \$84M (43% margin) |
| FY2026E EBITDA | ~\$340M |
| EV/FY26E EBITDA | ~22× (expensive for industrial) |
| Capacity | 3.1GW |
| Contracted | 2GW+ long-term |

### Fair Value Scenarios
| Scenario | Price | Driver |
|----------|-------|--------|
| Bear | \$45 | AI power demand decelerates, comp capacity floods, GM 30%, 15× |
| **Base** | **\$85** | FY26 EBITDA \$340M, holds 22× |
| Bull | \$120 | Multi-year hyperscaler locks 5y+, 5GW capacity, 28× |

## Risks
1. Cycle is the thesis — pricing power compresses fast once grid catches up
2. Customer concentration not fully disclosed
3. Gas price volatility on input
4. Caterpillar / Cummins / Vertiv / GE Vernova competing
5. Capital intensity (Genco + NovaLT16 = leverage)
6. Small-cap thematic flow volatility
7. 22× EV/EBITDA rich for cyclical industrial

## Portfolio Fit
- **Bucket**: Home-Run sleeve only (5%)
- **Max size**: 1.5%
- **Broker**: DEGIRO USD
- **Hold**: 2–3y tactical
- **Theme overlap**: 3rd AI-capex bet in 5%-sleeve = over-concentration" \
  "## My Decision  ← edit this directly on GitHub, it won't be overwritten
- [ ] Buy — entry: **<\$55**
- [ ] Watch — <\$60 OR multi-year contract surprise
- [x] **PASS for now** — already SE + NBIS as cleaner home-run picks

## Price Alerts
- Pullback watch: <\$55

## Notes
| Date | Note |
|------|------|
| 2026-06-05 | Initial. Real pivot, priced for it. Already have SE + NBIS shortlisted. SEI is 3rd AI-capex bet in 5% sleeve = no. |"

echo ""
echo "✅ Sync complete. View issues: gh issue list"
echo "   Checksums stored in: $SYNC_FILE"
