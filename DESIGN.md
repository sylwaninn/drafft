---
version: alpha
name: Wise-Inspired-design-analysis
description: An inspired interpretation of Wise's design language — a global money-transfer brand whose surface combines an unusually heavy near-black display sans (weight 900 at 64–126 px) with a vivid lime-green brand accent, sage-tinted surface neutrals, and rounded white cards on a pale green-tinted canvas; the whole system reads more like a Scandinavian fintech magazine than a bank.

colors:
  primary: "#9fe870"
  on-primary: "#0e0f0c"
  primary-active: "#cdffad"
  primary-neutral: "#c5edab"
  primary-pale: "#e2f6d5"
  ink: "#0e0f0c"
  ink-deep: "#163300"
  body: "#454745"
  mute: "#868685"
  canvas: "#ffffff"
  canvas-soft: "#e8ebe6"
  positive: "#2ead4b"
  positive-deep: "#054d28"
  warning: "#ffd11a"
  warning-deep: "#b86700"
  warning-content: "#4a3b1c"
  negative: "#d03238"
  negative-deep: "#a72027"
  negative-darkest: "#a7000d"
  negative-bg: "#320707"
  accent-orange: "#ffc091"
  accent-cyan: "#38c8ff"

typography:
  display-mega:
    fontFamily: Wise Sans, Inter, system-ui, -apple-system, sans-serif
    fontSize: 126px
    fontWeight: 900
    lineHeight: 107.1px
  display-xxl:
    fontFamily: Wise Sans, Inter, system-ui, sans-serif
    fontSize: 96px
    fontWeight: 900
    lineHeight: 81.6px
  display-xl:
    fontFamily: Wise Sans, Inter, system-ui, sans-serif
    fontSize: 64px
    fontWeight: 900
    lineHeight: 54.4px
  display-lg:
    fontFamily: Wise Sans, Inter, system-ui, sans-serif
    fontSize: 47px
    fontWeight: 400
    lineHeight: 70.5px
    letterSpacing: -0.108px
  display-md:
    fontFamily: Wise Sans, Inter, system-ui, sans-serif
    fontSize: 40px
    fontWeight: 900
    lineHeight: 34px
  display-sm:
    fontFamily: Inter, system-ui, sans-serif
    fontSize: 32px
    fontWeight: 600
    lineHeight: 38.4px
    letterSpacing: -0.96px
  display-xs:
    fontFamily: Inter, system-ui, sans-serif
    fontSize: 24px
    fontWeight: 600
    lineHeight: 31.2px
    letterSpacing: -0.48px
  body-lg:
    fontFamily: Inter, system-ui, sans-serif
    fontSize: 20px
    fontWeight: 400
    lineHeight: 30px
  body-md:
    fontFamily: Inter, system-ui, sans-serif
    fontSize: 16px
    fontWeight: 400
    lineHeight: 24px
  body-md-strong:
    fontFamily: Inter, system-ui, sans-serif
    fontSize: 16px
    fontWeight: 600
    lineHeight: 24px
  body-sm:
    fontFamily: Inter, system-ui, sans-serif
    fontSize: 14px
    fontWeight: 400
    lineHeight: 20px
  body-sm-strong:
    fontFamily: Inter, system-ui, sans-serif
    fontSize: 14px
    fontWeight: 600
    lineHeight: 20px
  caption:
    fontFamily: Inter, system-ui, sans-serif
    fontSize: 12px
    fontWeight: 400
    lineHeight: 16px
  button-md:
    fontFamily: Inter, system-ui, sans-serif
    fontSize: 16px
    fontWeight: 600
    lineHeight: 24px

rounded:
  none: 0px
  sm: 8px
  md: 12px
  lg: 16px
  xl: 24px
  pill: 9999px
  full: 9999px

spacing:
  xxs: 2px
  xs: 4px
  sm: 8px
  md: 12px
  lg: 16px
  xl: 24px
  2xl: 32px
  3xl: 48px

components:
  nav-bar:
    backgroundColor: "{colors.canvas}"
    textColor: "{colors.ink}"
    typography: "{typography.body-sm-strong}"
    padding: "{spacing.md} {spacing.xl}"
  nav-link:
    textColor: "{colors.ink}"
    typography: "{typography.body-sm-strong}"
  button-primary:
    backgroundColor: "{colors.primary}"
    textColor: "{colors.on-primary}"
    typography: "{typography.button-md}"
    rounded: "{rounded.xl}"
    padding: "{spacing.md} {spacing.xl}"
  button-secondary:
    backgroundColor: "{colors.canvas-soft}"
    textColor: "{colors.ink}"
    typography: "{typography.button-md}"
    rounded: "{rounded.xl}"
    padding: "{spacing.md} {spacing.xl}"
  button-tertiary:
    backgroundColor: "{colors.canvas}"
    textColor: "{colors.ink}"
    borderColor: "{colors.ink}"
    typography: "{typography.button-md}"
    rounded: "{rounded.xl}"
    padding: "{spacing.md} {spacing.xl}"
  button-icon-circular:
    backgroundColor: "{colors.canvas}"
    textColor: "{colors.ink}"
    rounded: "{rounded.full}"
    padding: "{spacing.sm}"
  text-input:
    backgroundColor: "{colors.canvas}"
    textColor: "{colors.ink}"
    borderColor: "{colors.ink}"
    typography: "{typography.body-md}"
    rounded: "{rounded.md}"
    padding: "{spacing.md} {spacing.lg}"
  card-content:
    backgroundColor: "{colors.canvas}"
    textColor: "{colors.ink}"
    typography: "{typography.body-md}"
    rounded: "{rounded.xl}"
    padding: "{spacing.xl}"
  card-feature-sage:
    backgroundColor: "{colors.canvas-soft}"
    textColor: "{colors.ink}"
    typography: "{typography.body-md}"
    rounded: "{rounded.xl}"
    padding: "{spacing.xl}"
  card-feature-green:
    backgroundColor: "{colors.primary-pale}"
    textColor: "{colors.ink}"
    typography: "{typography.body-md}"
    rounded: "{rounded.xl}"
    padding: "{spacing.xl}"
  card-feature-dark:
    backgroundColor: "{colors.ink}"
    textColor: "{colors.primary}"
    typography: "{typography.body-md}"
    rounded: "{rounded.xl}"
    padding: "{spacing.xl}"
  hero-band:
    backgroundColor: "{colors.canvas-soft}"
    textColor: "{colors.ink}"
    typography: "{typography.display-mega}"
    padding: "{spacing.3xl} {spacing.xl}"
  hero-band-dark:
    backgroundColor: "{colors.ink}"
    textColor: "{colors.primary}"
    typography: "{typography.display-mega}"
    padding: "{spacing.3xl} {spacing.xl}"
  content-band:
    backgroundColor: "{colors.canvas}"
    textColor: "{colors.ink}"
    typography: "{typography.display-md}"
    padding: "{spacing.3xl} {spacing.xl}"
  currency-converter-card:
    backgroundColor: "{colors.canvas}"
    textColor: "{colors.ink}"
    borderColor: "{colors.ink}"
    typography: "{typography.body-md}"
    rounded: "{rounded.xl}"
    padding: "{spacing.xl}"
  badge-positive:
    backgroundColor: "{colors.primary-pale}"
    textColor: "{colors.positive-deep}"
    typography: "{typography.body-sm-strong}"
    rounded: "{rounded.pill}"
    padding: "{spacing.xs} {spacing.md}"
  badge-negative:
    backgroundColor: "{colors.negative-bg}"
    textColor: "{colors.on-primary}"
    typography: "{typography.body-sm-strong}"
    rounded: "{rounded.pill}"
    padding: "{spacing.xs} {spacing.md}"
  contour-texture:
    description: "Drafft block texture: topographic contour lines (hairline loops like a trail map) behind coloured blocks. See 'Contour texture' in Drafft app rules."
    strokeColorOnDark: "{colors.primary}"
    strokeColorOnLime: "{colors.on-primary}"
    lineOpacity: 0.15
    indexLineOpacity: 0.30
    lineWidth: 0.8px
    indexLineWidth: 1.2px
    indexEvery: 5
    lines: 12–14 iso-lines on a gentle generated terrain (broad summit + 3–4 low hills)
  bottom-bar:
    description: "Anything pinned to a screen edge sits over ProgressiveBlur (variable blur, radius 0 to 14, no tint). Modifiers: bottomBar, topBar, blurredNavigationEdge. Never a background colour."
    controls: "Liquid Glass for neutral controls, lime-tinted glass for send, solid button-primary for validate"
  footer:
    backgroundColor: "{colors.ink}"
    textColor: "{colors.canvas-soft}"
    typography: "{typography.body-sm}"
    padding: "{spacing.3xl} {spacing.xl}"

  # ─── Examples (illustrative) — auto-derived; resolve any TO_FILL markers below ───
  ex-pricing-tier:
    description: "Default Pricing tier card. Re-uses feature-card chrome with brand canvas-soft surface."
    backgroundColor: "{colors.canvas-soft}"
    textColor: "{colors.ink}"
    borderColor: "{colors.mute}"
    rounded: "{rounded.xl}"
    padding: "{spacing.xl}"
  ex-pricing-tier-featured:
    description: "Featured/highlighted tier — polarity-flipped surface (dark fill + light text in light mode, light fill + dark text in dark mode)."
    backgroundColor: "{colors.ink}"
    textColor: "{colors.on-primary}"
    rounded: "{rounded.xl}"
    padding: "{spacing.xl}"
  ex-product-selector:
    description: "What's Included summary card — re-purposed for SaaS / B2B verticals (NOT a literal product gallery)."
    backgroundColor: "{colors.canvas-soft}"
    rounded: "{rounded.xl}"
    padding: "{spacing.xl}"
  ex-cart-drawer:
    description: "Subscription summary — re-purposed for SaaS / B2B (line items per add-on, not literal cart)."
    backgroundColor: "{colors.canvas}"
    rounded: "{rounded.xl}"
    padding: "{spacing.xl}"
    item-divider: "{colors.canvas-soft}"
  ex-app-shell-row:
    description: "Sidebar nav row inside the App Shell example. Active state uses brand primary as the indicator."
    backgroundColor: "{colors.canvas}"
    activeIndicator: "{colors.primary}"
    rounded: "{rounded.sm}"
    padding: "{spacing.md} {spacing.lg}"
  ex-data-table-cell:
    description: "Default data-table th + td chrome. Header uses mono-caps eyebrow typography; body uses body-sm."
    headerBackground: "{colors.canvas-soft}"
    headerTypography: "{typography.caption}"
    bodyTypography: "{typography.body-sm}"
    cellPadding: "{spacing.md} {spacing.lg}"
    rowBorder: "{colors.canvas-soft}"
  ex-auth-form-card:
    description: "Sign-in / sign-up card. Re-uses feature-card chrome with text-input primitives inside."
    backgroundColor: "{colors.canvas-soft}"
    rounded: "{rounded.xl}"
    padding: "{spacing.xl}"
  ex-modal-card:
    description: "Modal dialog surface — same chrome as feature-card with elevated shadow."
    backgroundColor: "{colors.canvas}"
    rounded: "{rounded.xl}"
    padding: "{spacing.xl}"
  ex-empty-state-card:
    description: "Empty-state illustration frame."
    backgroundColor: "{colors.canvas-soft}"
    rounded: "{rounded.xl}"
    padding: "{spacing.3xl}"
    captionTypography: "{typography.body-md}"
  ex-toast:
    description: "Toast notification surface — feature-card shape + medium shadow."
    backgroundColor: "{colors.canvas}"
    rounded: "{rounded.xl}"
    padding: "{spacing.md} {spacing.lg}"
    typography: "{typography.body-sm}"

---


## Overview

Wise — the global money-transfer brand — wears its identity in a single signature pairing: a vivid lime-green `{colors.primary}` (`#9fe870`) used as the CTA pill and brand accent, set against a pale sage-tinted canvas `{colors.canvas-soft}` (`#e8ebe6`) that runs across the hero band, and a near-black ink `{colors.ink}` (`#0e0f0c`) with a hint of warmth from the brand's underlying olive cast. The brand reads more like a calm Scandinavian magazine than a bank — generous whitespace, large rounded cards, and an unusually heavy display sans set at weight 900 carrying every hero headline.

Display typography is the second decisive voice. The proprietary `Wise Sans` family carries hero displays at weight 900 in scales from 64 px up to 126 px on the largest hero. The brand pairs Wise Sans 900 with Inter at weight 600 for sub-displays — the contrast between the chunky proprietary face and Inter's neutrality creates a particular hierarchy: Wise Sans for the brand moment, Inter for everything else.

Cards are universally pill-rounded — `{rounded.xl}` 24 px is the brand's signature card radius. Buttons take the same 24 px pill-rectangle shape. The brand never uses sharp corners on UI elements; the visual softness is part of the friendly fintech voice.

**Key Characteristics:**
- A single lime-green CTA accent `{colors.primary}` (`#9fe870`) — the brand's universal primary action color. No second accent.
- Two-face display typography — Wise Sans (proprietary, weight 900, hero scale) + Inter (weight 600, sub-display scale). The contrast is the brand's typographic story.
- `{rounded.xl}` 24 px is the canonical card and button radius. Generous, friendly.
- Sage-tinted canvas `{colors.canvas-soft}` (`#e8ebe6`) is the brand's hero surface; white `{colors.canvas}` is reserved for cards within the sage band.
- A full semantic palette: positive green family, warning yellow family, negative red family — each documented with content / hover / active variants for in-product use.
- Currency-converter card on the hero — the brand's signature interactive component, hosting from/to amount inputs.

## Colors

### Brand & Accent
- **Wise Green** (`{colors.primary}` — `#9fe870`): The brand's universal CTA color. Every primary button, every "Send money" pill, the brand's logo accent.
- **Wise Green Hover** (`{colors.primary-active}` — `#cdffad`): The lighter green for active state.
- **Wise Green Neutral** (`{colors.primary-neutral}` — `#c5edab`): A mid-saturation green used as a neutral active fill.
- **Wise Green Pale** (`{colors.primary-pale}` — `#e2f6d5`): The lightest green for soft surface tints / badge backgrounds.

### Surface
- **Canvas** (`{colors.canvas}` — `#ffffff`): Pure white for card interiors.
- **Canvas Soft** (`{colors.canvas-soft}` — `#e8ebe6`): The sage-tinted page background. Defining mood of the brand.

### Text
- **Ink** (`{colors.ink}` — `#0e0f0c`): Near-black with a hint of olive warmth — the brand's default text and headings color.
- **Ink Deep** (`{colors.ink-deep}` — `#163300`): A deep forest-green ink used on positive-state surfaces.
- **Body** (`{colors.body}` — `#454745`): Secondary body text.
- **Mute** (`{colors.mute}` — `#868685`): Lowest-priority text — captions, placeholder, fine print.

### Semantic
- **Positive** (`{colors.positive}` — `#2ead4b`): Success indicator.
- **Positive Deep** (`{colors.positive-deep}` — `#054d28`): Pressed positive state.
- **Warning** (`{colors.warning}` — `#ffd11a`): Caution indicator.
- **Warning Deep** (`{colors.warning-deep}` — `#b86700`): Pressed warning.
- **Warning Content** (`{colors.warning-content}` — `#4a3b1c`): Text on warning surfaces.
- **Negative** (`{colors.negative}` — `#d03238`): Destructive / error red.
- **Negative Deep** (`{colors.negative-deep}` — `#a72027`): Pressed destructive.
- **Negative Darkest** (`{colors.negative-darkest}` — `#a7000d`): Highest-emphasis destructive text.
- **Negative Bg** (`{colors.negative-bg}` — `#320707`): Dark maroon for destructive callout backgrounds.

### Brand Accent — Tertiary
- **Accent Orange** (`{colors.accent-orange}` — `#ffc091`): Bright peach used inside illustrative content / pricing cards.
- **Accent Cyan** (`{colors.accent-cyan}` — `#38c8ff`): Bright sky-blue used as a tertiary illustration accent.

## Typography

### Font Family
Two faces ladder the system:
1. **Wise Sans** — proprietary geometric sans with an unusually heavy weight 900 used for all hero displays. The face is the brand's typographic signature. Always at weight 900, never lighter on the marketing surface.
2. **Inter** — used for sub-displays (weight 600), all body, and form labels. Loaded with `font-feature-settings: "calt"` for contextual alternates.

### Hierarchy

| Token | Size | Weight | Line Height | Letter Spacing | Use |
|---|---|---|---|---|---|
| `{typography.display-mega}` | 126px | 900 | 107.1px | 0 | Hero stencil at maximum scale. |
| `{typography.display-xxl}` | 96px | 900 | 81.6px | 0 | Sub-hero scale. |
| `{typography.display-xl}` | 64px | 900 | 54.4px | 0 | Standard hero headline. |
| `{typography.display-lg}` | 47px | 400 | 70.5px | -0.108px | Lighter sub-display. |
| `{typography.display-md}` | 40px | 900 | 34px | 0 | Section / card headlines. |
| `{typography.display-sm}` | 32px | 600 | 38.4px | -0.96px | Inter-rendered section headings. |
| `{typography.display-xs}` | 24px | 600 | 31.2px | -0.48px | Sub-section displays. |
| `{typography.body-lg}` | 20px | 400 | 30px | 0 | Lead paragraphs. |
| `{typography.body-md}` | 16px | 400 | 24px | 0 | Default body. |
| `{typography.body-md-strong}` | 16px | 600 | 24px | 0 | Bold inline body. |
| `{typography.body-sm}` | 14px | 400 | 20px | 0 | Secondary body. |
| `{typography.body-sm-strong}` | 14px | 600 | 20px | 0 | Bold caption / nav-link. |
| `{typography.caption}` | 12px | 400 | 16px | 0 | Fine print. |
| `{typography.button-md}` | 16px | 600 | 24px | 0 | Button label. |

### Principles
- **Weight 900 for hero, weight 600 for everything else.** The brand's display ceiling is full-black weight; everything below is semibold.
- **Wise Sans for the brand voice, Inter for utility.** Strict role separation.

### Note on Font Substitutes
Wise Sans is proprietary. Open-source substitutes:
- **Display** — *Inter* at weight 900 or *Manrope* at weight 800 / 900 captures the geometric heaviness. *Geist* weight 800 is a passable second choice.
- **Sub-display + body** — *Inter* is the brand's actual second face.

## Layout

### Spacing System
- **Base unit**: 4 px.
- **Tokens**: `{spacing.xxs}` 2 px · `{spacing.xs}` 4 px · `{spacing.sm}` 8 px · `{spacing.md}` 12 px · `{spacing.lg}` 16 px · `{spacing.xl}` 24 px · `{spacing.2xl}` 32 px · `{spacing.3xl}` 48 px.
- **Section padding**: bands use `{spacing.3xl}` 48 px top/bottom on desktop.
- **Card interior**: cards at `{spacing.xl}` 24 px.

### Grid & Container
- Marketing container centres at ~1200 px.
- Hero: split layout (headline left, currency-converter card right) at desktop; stacked at mobile.
- Feature grids: 2-up / 3-up at desktop.

### Responsive Strategy

#### Breakpoints

| Name | Width | Key Changes |
|---|---|---|
| Mobile | < 768px | Hero stacks; converter card full-width below headline; grids 1-up. |
| Tablet | 768–1023px | Grids 2-up. |
| Desktop | ≥ 1024px | Hero split; full grids. |

#### Touch Targets
Buttons render ~48 px tall (12 vertical padding + 24 line). WCAG AAA at all widths.

#### Image Behavior
Photography is sparse; the brand prefers illustrative SVGs and product mockups inside cards. Country flag thumbnails appear inside currency rows.

## Elevation & Depth

| Level | Treatment | Use |
|---|---|---|
| Level 0 — Flat | No shadow, no border. | Default. |
| Level 1 — Hairline on Dark | 1 px solid `{colors.ink}` border. | Tertiary outline buttons, form inputs. |
| Level 2 — Soft Card | Implicit Level 0 white card sitting on sage canvas — the surface contrast IS the elevation. | Cards on the sage hero band. |

The brand uses surface contrast (`{colors.canvas-soft}` background vs `{colors.canvas}` cards) as the primary elevation cue.

## Shapes

### Border Radius Scale

| Token | Value | Use |
|---|---|---|
| `{rounded.none}` | 0px | Full-bleed bands. |
| `{rounded.sm}` | 8px | Inline pills, small badges. |
| `{rounded.md}` | 12px | Form inputs, smaller chrome. |
| `{rounded.lg}` | 16px | Mid-size cards. |
| `{rounded.xl}` | 24px | The brand's canonical button + card radius. |
| `{rounded.pill}` | 9999px | Status pills and full-radius accents. |
| `{rounded.full}` | 9999px | Circular icon containers. |

## Components

### Buttons

**`button-primary`** — the lime-green CTA pill.
- Background `{colors.primary}`, text `{colors.on-primary}`, label `{typography.button-md}`, padding `{spacing.md} {spacing.xl}`, shape `{rounded.xl}` 24 px.

**`button-secondary`** — the sage-tinted secondary.
- Background `{colors.canvas-soft}`, text `{colors.ink}`, same typography / padding / shape.

**`button-tertiary`** — the white outline tertiary.
- Background `{colors.canvas}`, text `{colors.ink}`, 1 px solid `{colors.ink}` border, same typography / padding / shape.

**`button-icon-circular`** — the circular icon button.
- Background `{colors.canvas}`, ink icon, shape `{rounded.full}`.

### Cards & Containers

**`card-content`** — the default white card.
- Background `{colors.canvas}`, text `{colors.ink}`, padding `{spacing.xl}`, shape `{rounded.xl}`. No border, sits on sage canvas.

**`card-feature-sage`** — the sage-tinted feature card.
- Background `{colors.canvas-soft}`, text `{colors.ink}`, padding `{spacing.xl}`, shape `{rounded.xl}`.

**`card-feature-green`** — the soft-green feature card.
- Background `{colors.primary-pale}`, text `{colors.ink}`, padding `{spacing.xl}`, shape `{rounded.xl}`.

**`card-feature-dark`** — the polarity-flipped dark card with green text.
- Background `{colors.ink}`, text `{colors.primary}` (Wise green!), padding `{spacing.xl}`, shape `{rounded.xl}`. Used for promotional moments.

**`currency-converter-card`** — the brand's signature interactive widget.
- Background `{colors.canvas}`, text `{colors.ink}`, 1 px solid `{colors.ink}` border, padding `{spacing.xl}`, shape `{rounded.xl}`. Hosts from/to amount inputs + currency selectors.

### Inputs & Forms

**`text-input`** — the canonical text input.
- Background `{colors.canvas}`, text `{colors.ink}`, 1 px solid `{colors.ink}` border, body in `{typography.body-md}`, padding `{spacing.md} {spacing.lg}`, shape `{rounded.md}`.

### Navigation

**`nav-bar`** — the sticky top nav.
- Background `{colors.canvas}`, text `{colors.ink}`, padding `{spacing.md} {spacing.xl}`.

**`nav-link`** — link items inside nav.
- Text `{colors.ink}`, set in `{typography.body-sm-strong}`.

**`footer`** — the dark footer band.
- Background `{colors.ink}`, text `{colors.canvas-soft}`, padding `{spacing.3xl} {spacing.xl}`. Body in `{typography.body-sm}`.

### Signature Components

**`hero-band`** — the sage-canvas hero band.
- Background `{colors.canvas-soft}`, text `{colors.ink}`, padding `{spacing.3xl} {spacing.xl}`. Headline in `{typography.display-mega}` (Wise Sans weight 900).

**`hero-band-dark`** — the polarity-flipped dark hero.
- Background `{colors.ink}`, text `{colors.primary}` (Wise green headline on near-black!), same padding / scale.

**`content-band`** — the white content band that follows hero.
- Background `{colors.canvas}`, text `{colors.ink}`, padding `{spacing.3xl} {spacing.xl}`. Section headline in `{typography.display-md}`.

**`badge-positive`** — the positive status pill.
- Background `{colors.primary-pale}`, text `{colors.positive-deep}`, body in `{typography.body-sm-strong}`, padding `{spacing.xs} {spacing.md}`, shape `{rounded.pill}`.

**`badge-negative`** — the negative status pill.
- Background `{colors.negative-bg}`, text white, body in `{typography.body-sm-strong}`, padding `{spacing.xs} {spacing.md}`, shape `{rounded.pill}`.

### Examples (illustrative)

> Auto-derived kit-mirror demonstration surfaces (`scripts/derive-examples-block.mjs`). Each `ex-*` entry references brand-native primitives so downstream consumers (`/preview-design`, `/generate-kit`) re-skin the same 10 surfaces consistently. `TO_FILL` markers indicate missing primitives — resolve in the LLM judgment pass.

**`ex-pricing-tier`** — Default Pricing tier card. Re-uses feature-card chrome with brand canvas-soft surface.
- Properties: `backgroundColor`, `textColor`, `borderColor`, `rounded`, `padding`

**`ex-pricing-tier-featured`** — Featured/highlighted tier — polarity-flipped surface (dark fill + light text in light mode, light fill + dark text in dark mode).
- Properties: `backgroundColor`, `textColor`, `rounded`, `padding`

**`ex-product-selector`** — What's Included summary card — re-purposed for SaaS / B2B verticals (NOT a literal product gallery).
- Properties: `backgroundColor`, `rounded`, `padding`

**`ex-cart-drawer`** — Subscription summary — re-purposed for SaaS / B2B (line items per add-on, not literal cart).
- Properties: `backgroundColor`, `rounded`, `padding`, `item-divider`

**`ex-app-shell-row`** — Sidebar nav row inside the App Shell example. Active state uses brand primary as the indicator.
- Properties: `backgroundColor`, `activeIndicator`, `rounded`, `padding`

**`ex-data-table-cell`** — Default data-table th + td chrome. Header uses mono-caps eyebrow typography; body uses body-sm.
- Properties: `headerBackground`, `headerTypography`, `bodyTypography`, `cellPadding`, `rowBorder`

**`ex-auth-form-card`** — Sign-in / sign-up card. Re-uses feature-card chrome with text-input primitives inside.
- Properties: `backgroundColor`, `rounded`, `padding`

**`ex-modal-card`** — Modal dialog surface — same chrome as feature-card with elevated shadow.
- Properties: `backgroundColor`, `rounded`, `padding`

**`ex-empty-state-card`** — Empty-state illustration frame.
- Properties: `backgroundColor`, `rounded`, `padding`, `captionTypography`

**`ex-toast`** — Toast notification surface — feature-card shape + medium shadow.
- Properties: `backgroundColor`, `rounded`, `padding`, `typography`


## Do's and Don'ts

### Do
- Reserve `{colors.primary}` Wise green for every primary CTA. The lime-green pill IS the brand's conversion signature.
- Set hero headlines in `{typography.display-mega}` / `{typography.display-xl}` Wise Sans weight 900. Never lighter.
- Use `{rounded.xl}` 24 px for buttons and cards. The generous radius is the brand's friendliness signature.
- Cycle page surfaces in `{colors.canvas-soft}` sage canvas → `{colors.canvas}` white cards. Surface contrast carries elevation.
- Use the full semantic palette (positive / warning / negative) for in-product status — never repurpose Wise green as success indicator since it IS the brand CTA.

### Don't
- Don't introduce a second brand accent. Wise green is the sole identity colour.
- Don't render the hero in weight 700 or lighter. The brand's display weight is 900.
- Don't render CTAs as sharp rectangles. The 24 px pill geometry is non-negotiable.
- Don't pair the green CTA with a green background. The brand always sits Wise green on neutral surfaces (sage / white / ink).
- Don't replace Wise Sans with a generic geometric sans for hero typography — the proprietary face IS the brand's voice.
## Drafft app rules (iOS)

Rules agreed while building the Drafft app. They apply on top of the tokens above.

### Dark mode
- The page is near-black in dark mode, so night blocks are lifted a step (`night` dark = #23261F, `nightRaised` #2E3229) and every coloured block (`draftBlock`) gets a faint hairline (`blockEdge`, white 9 %, invisible in light mode).
- Selection is shown by fills, never by frames or outlines. A selected tile or chip turns solid accent with on-accent content (reads the same in light and dark). On a night surface, a selected row takes the accent wash `selectedOnNight` (accent at 26 %).
- Selected or not, a label keeps one weight: nothing widens or shifts when it is picked. The check disc, the fill and the ink say it.
- Discover's action buttons sit centred between the cards and the tab bar (same space above and below).
- Discover's waiting cards use `deckVeil` (sage in light, #1A1C18 in dark, close to the page so they recede) plus the same hairline, so the stack never sinks into the page.

### Edges: progressive blur, never a background
- Anything pinned to an edge sits over a progressive blur, never a colour band or a painted background. One component (`ProgressiveBlur`: the blur radius ramps from 0 to max, no tint) and three modifiers, used everywhere, nothing else:
  - `.bottomBar { … }`: validate buttons, the chat composer, anything above the keyboard.
  - `.topBar { … }`: custom headers (`TabHeader`, sign-up step header).
  - `.blurredNavigationEdge()`: screens with the system navigation bar (chat, sheets): the blur covers the status bar and the whole bar, avatar and title included.
- Attach them to the scroll view itself. The system scroll-edge effects are hidden where these apply.
- The blur only appears when content actually sits under the bar (read from the scroll position): at the top of a page, or on a page shorter than the screen, nothing is blurred. It fades in over 0.2 s.
- Never put `.interactive()` glass on a button's label: interactive glass handles the touch itself and can swallow the button's action. Buttons use plain `.glassEffect(.regular)`.
- Controls on a bar stay opaque or Liquid Glass (lime validate, glass field and buttons), so their contrast never depends on what scrolls under.
- Screens that don't scroll (Discover) pin their header without blur. Exception: the profile detail's like/pass buttons float with no blur at all.
- `VariableBlurView` re-applies its filter whenever UIKit rebuilds the effect (leaving and coming back to a screen, tab switches, trait changes); otherwise it degrades into a flat, hard-edged block.
- Header heights never change with scroll (only the title scales): a bar that changes height moves the content under the finger. Chats' search field stays visible, it doesn't fold.
- Long lists whose rows vary a lot in height (chat messages) use a plain `VStack`, not `LazyVStack`, so scrolling back up never jumps.
- Discover ignores the keyboard safe area (the deck keeps its size), and signing in puts the keyboard away before showing the next screen.
- You has no title: only the blur under the status bar.

### Selection marks and banners
- One selection mark everywhere: `CheckDisc` (lime disc, on-lime tick when on; a ring when off, lighter on night). Never a lime tick on a light fill, never an SF "checkmark.circle.fill" whose cut-out tick shows the background.
- In-app banners (match, boost) use `BannerSurface`: solid night, a thin light rim and a layered shadow, so they detach from any page.
- Never a gradient in a background or a surface fill. Solid colours only (gradients stay limited to legibility scrims over photos and to masks of the progressive blur).

### Confirmations
- Short sheets keep the system corner radius (never `presentationCornerRadius`): floating sheets then follow the screen's corners with even side and bottom margins.
- **The page tone follows the accent.** "Sage" in these rules means the page tone (`DS.Palette.sage`, `canvasSoft`), which is tuned to the active accent so it never keeps a former one's colour: violet (current) gets a lilac mist `#ECEAFA` (dark `#0E0D14`), lime keeps `#E8EBE6`. Same lightness as the old sage, so white blocks still stand out; body, mute and accent ink stay at 4.5:1 or more on it.
- **Discover's empty stack is one screen, filtered or not** (`DeckEmptyView`): a running track with you in the infield and your radius; a runner laps the lane as it appears (you've been round everyone); then one concrete tap, "Widen to 25 km" (then 50, then any distance), with the chats as the second way on. Never a generic icon-and-headline card.
- **A sheet never shares the page's colour.** Screens are a sage page with white blocks; a sheet flips the pair: the sheet itself is white (lifted `#1A1C18` in dark mode) and its blocks sink into sage wells (`#0E0F0C` in dark). `DS.Palette.canvasSoft` / `canvas` are `Surface` styles that resolve by context, so the same view reads right pushed or presented. Every `.sheet` content ends with `.sheetSurface()`; nothing else is needed.
- Short modal sheets (confirmations, purchase confirmations, photo refused) sit one step higher still (`sheetRaised`: white, `#2A2D26` in dark), so they stand out over another sheet too.
- Never the system action sheet or alert. Use `.drafftConfirm`: a short sheet sized to its content, raised (`sheetRaised`), with an icon disc (red for destructive, lime otherwise), a display title, the consequence in one sentence, full-width buttons and a plain Cancel. Used for log out, leave sign-up, discard changes, report/block.

### Forms & flows
- Log in, sign up and every sign-up step sit on `PageContourBackdrop`: the sage page with the contour texture at half strength. The log-in background is FROZEN (`BackdropSeed.login` = "login-2", drawn by `TerrainField`): never regenerate it. Each sign-up step has its own terrain; changing step morphs the terrain into the next one (0.9 s): the lines slide and reshape, no fade.
- Gender is picked from a fixed list (Woman, Man, Non-binary); there is never a free-text way to describe a gender.
- No height anywhere: Drafft never asks for or shows how tall someone is.
- Labels and tags never wrap: one line, always (`lineLimit(1)` + `fixedSize`), shorten the text instead.
- Logo: the word "drafft" in Inter Display Black, solid, with two copies trailing to the left (tints at 45% and 20% of the word colour, offsets about 0.1 and 0.2 of the type size), over a very faint relief (contour lines at ~13%). App icon: white word on orange #FF7300 (Resources/Assets.xcassets/AppIcon, rendered from the logo study). `Wordmark` in the app draws the same trail.
- Brand accent in the app: vivid orange `#FF7300` (token names keep "lime" for the role), with **white** text and icons on it (a deliberate choice; keep labels semibold or bolder). Pale `#FFEBDC`, pressed `#FFB27A`. Switch in `Tokens.swift` (`DS.Palette.accent`: `.lime`, `.plum`, `.tangerine`).
- `accentInk` is the accent as text or a glyph on neutral surfaces: `#C45000` in light mode (4.7:1 on white, still orange, never the old brown `#7A3300`), `#FF8A2B` in dark mode. It is the app tint, so it drives the selected tab, links, date pickers and "Typing".

### Colour roles
One job per colour, everywhere:
- **Accent fill** (`lime`): the primary action (validate, send), selected chips, tiles, discs, toggles, slider tracks, progress. Content on it is `onLime`, glyphs included; a disc inside an accent block is `onLimeWash` with an `onLime` glyph, never a night disc with an accent glyph.
- **Accent text** (`accentInk`): tappable text (links, "Clear filters", "Resend code"), the selected tab, live state ("Typing").
- **Ink**: everything else, including utility controls (close, back, glass icon buttons, the filter button) and decorative icons in rows and block headers (ink glyph on a `canvasSoft` disc). Utility buttons are never accent.
- **Semantic**: `negative` for destructive and super like, `positive`/`positiveDeep` for verified states, `like` green for liking.

### Brand name
- The product is **drafft**, always lowercase, in copy and as the app name on the home screen. In running text it is set one weight above the sentence (semibold in regular text, heavy in semibold text) so it reads as a name: use `Text(branded:font:)`, which does it for every occurrence.
- The paid tier is **drafft tempo**: both words lowercase, same face and weight, "tempo" in the accent colour so the pair reads as one name. `Text(branded:)` colours it: `accentInk` on light surfaces, `lime` on night, `night` on an accent fill (the tier card on You, the paywall button). Never "Plus", "plus" or "+". The paywall lockup is the wordmark followed by "tempo" in Inter Display Black at the same size, in the accent. The spark stays the tier's icon.
- Liking stays green (`like`, `#9fe870`) whatever the brand accent: like buttons, the heart pop, "Send like", "Like with this answer" and the like markers in chat.
- Never pre-select an answer for the person (identity, who to meet, birthday, photos). Empty until they choose.
- On an optional step, Continue stays disabled until something is filled in; Skip is the way past it.
- Multi-step flows move only with Back / Continue / Skip: no swipe between steps.
- One question per step: when a step asks two things (sports, then how often), split it.
- A field takes touches on its whole box, padding included: the text field fills the box and a tap anywhere on it focuses it.
- Never focus a field on arrival: the page opens whole, keyboard down, so the person sees everything first. The keyboard comes up when they tap a field.
- Forms scroll with `FocusScrollView`: a field that gets focus scrolls itself to the upper third, clear of the keyboard and the pinned button. A pinned button never sits on top of the field being typed in. Any field that isn't a `DrafftField` gets `.revealsOnFocus(…)`; the scroll content always ends with a margin, so even the last field never touches the keyboard.
- Fields share one pattern: label above (subheadline semibold), white bordered field (52 pt, radius md), hint or error below (footnote). The field is always the lifted white, in a sheet too (never the sheet's sage well); settings sheets set their groups straight on the white sheet, told apart by space, not grey boxes. A date the person knows by heart (birthday) is typed, not scrolled: day, month, year boxes in the language's order, number pad, auto-advance (`BirthdateField`); never a wheel with a made-up starting date.
- One icon per meaning: never reuse the same symbol for two different items in a list or a switcher.

### Verification & support
- Sign-up runs in four chapters, never mixed, one question per step: Account (language, preselected from the phone or English; ground rules + consent; phone), About you (first name, birthday, gender, who to meet, lifestyle, area), Sports (sports, then how often), Profile (photos, bio, voice, written prompts, interactive prompt, notifications). 17 steps. No "looking for" question: drafft doesn't ask it, show it or filter by it. Lifestyle is one step (rhythm, food, drinking, smoking, each optional, tap again to clear) shared with Edit profile (`LifestylePicker`).
- A finished sign-up creates a profile holding only the answers: no bio, goal, pronouns, lifestyle or prompts borrowed from demo data. Skipped prompts stay empty and are hidden on the profile (the interactive prompt shows only when complete); Edit profile accepts them empty.
- The stepper (`ChapterStepper`) shows one bar per chapter, same width each, filling step by step, with the chapter names under the bars: current in bold, finished ones ticked, next ones in body grey. Back on the left, Skip on the right (optional steps only). Entering a new chapter gives a success haptic. The last step's button says "Start swiping".
- No line under the pinned button to say why it's disabled: the screen already says what to do, repeating it is noise. Only a real error goes there, in red (the server turned the profile down).
- Exception to the pinned button: while a prompt answer is being typed, Continue leaves the keyboard bar (it would skip the other prompts); a lime check button next to the field closes the keyboard, and Continue comes back.
- Community rules come before anything personal: four short rules in a white block, then the required consent in its own block.
- Single and multiple choices are white blocks of rows with `CheckDisc` (language, gender, who to meet). Chips stay for sports.
- An unfinished sign-up is saved as it goes and resumes at the first mandatory step not done (usually the SMS), otherwise where it stopped (`OnboardingStore`).
- Location is required (at least While Using the App): sign-up can't continue without it (no typing an area), and if it's turned off later a blocking screen asks to turn it back on (`LocationGate`, `LocationRequiredView`).
- Sign-up is 18+: under 18, the typed birthday shows why and Continue stays disabled; a required, unchecked-by-default consent links each legal document inline.
- Demo builds show dashed "Demo only" panels (`DemoPanel`) to pick each check's outcome; they never ship.
- Every account verifies a phone number at sign-up (mandatory, no Skip). The first photo must show a face (Vision, on device). No video check for now: it was removed until a provider is chosen.
- The phone number can be replaced (after verifying the new one), never removed.
- Any failed check or error offers "Get help", which opens a prefilled support request (topic + reference).
- Front-end state machines (`PhoneVerificationModel`) sit on protocols (`PhoneVerifying`); demo implementations stand in until the API exists.

### Apple / Google sign-in
- Use only what the provider really shares (`SocialIdentity`). Apple: a stable ID, a verified email or a private relay address, and the name only on the first sign-in if shared; no photo, birthday or phone. Google (openid, email, profile): ID, email, name, picture URL, locale; nothing else without extra reviewed scopes.
- Prefill only that (first name, email), say where it came from ("From your Apple account. You can change it."), and still ask for everything else (birthday, phone). Social accounts have no Drafft password.
- Every sign-up step has a way back; on the first one it leaves sign-up, and leaving on purpose discards the answers (you start over). Progress is only kept when the app is closed mid-sign-up.

### Purchases
- Every completed purchase (drafft tempo, boost packs, super like packs) opens `PurchaseConfirmation` over the screen it was bought on: a raised sheet (`sheetRaised`: white, lifted grey in dark mode) sized to its content, the item's mark popping in with its trail, a display title ("You're on drafft tempo.", "5 boosts added."), what it does in one sentence, a receipt-like recap (plan, price, renewal; or added, balance, paid), one next step and "Apple emails your receipt."
- The next step fits where the purchase started: the paywall's `unlockedTitle` ("Undo my last swipe", "See who likes you", "Continue"), "Boost now" with "Later" for boosts, "Got it" for super likes. Closing it returns to the origin.

### Safety
- One set of safety tips (`SafetyTips.meeting`), same words everywhere: the Safety tips page, a "Meet safely" block in every session invite (new or other times), the "Meet safely" sheet shown right after you confirm a time, and a "Meet safely" link on every confirmed session card.
- Report or block is offered on a profile in Discover, on a matched profile opened from a chat, and in the chat's "More" menu. Both report and block hide the person for good: out of Discover, Likes and Chats, and undo can't bring them back. Blocked people are listed in You › Blocked people; unblocking puts them back at the end of Discover, the old chat doesn't return.
- Data export is requested in the app and sent by email as a download link (usually within 24 hours, link valid 7 days); one request at a time.

### Subscription (drafft tempo)
- Billing belongs to the App Store (auto-renewable subscription). The app reads the state (`TempoSubscription`: plan, end of period, renews or not) and never cancels or changes a plan itself.
- You shows the tier card (entry to the paywall) while not subscribed, and a "drafft tempo" row under Account only while subscribed ("Renews 24 Oct", or "Ends 24 Oct" once cancelled).
- The row opens `SubscriptionSheet`: a night status block (lockup, Active/Ending pill, price, renewal or end date), what's included, the App Store billing terms (renews unless cancelled 24 h before the period ends; deleting the app doesn't cancel), "Open App Store subscriptions", Restore purchases, Terms, Privacy. The pinned action is "Manage subscription", which opens Apple's own sheet (`manageSubscriptionsSheet`).
- The paywall carries the same auto-renewal terms under its button, plus Restore, Terms and Privacy.
- Demo builds simulate the App Store's answer with a `DemoPanel` (Renews, Cancelled, Expired).

### Notifications
- Asked during sign-up, on its own optional step at the end of Profile ("Don't miss a match"), with what they'll get before the system prompt. Continue needs them on; Skip passes.
- System permissions share one pattern (`SystemPermission`, `PermissionButton`): the service keeps its state current by itself, back from Settings included, so screens only read it; the action asks the first time and opens Settings once refused, never a dead disabled button. Notifications use it today (sign-up and You › Notifications); location, camera, microphone and photos join the same way.
- You › Notifications is a dedicated page: the permission state first (turn on, or open iPhone Settings if denied), then Activity (matches, likes, messages, message previews off by default) and Sessions (evening before at 20:00, an hour before).
- Session reminders are real local notifications; tapping any notification opens its chat. Push is wired (capability + device token) and waits for the server.

### Sports list
- One catalog (`Sport`, Models/SportCatalog.swift), one picker (`SportPicker`) with search, used in sign-up, Edit profile and Filters. Every sport has its own symbol.

### Session invites
- Up to 3 time cards side by side (weekday, big day number, month, time pill). No card until the person adds one.
- "Add a time" and each card open a sheet with the native pickers: the system calendar for the day (no past days) and the system time picker (5-minute steps). The pinned button states the result ("Add Sat 27 Sep at 18:30"); the time only joins the invite then. Changing a card uses the same sheet, with "Remove this time".
- Send needs at least one time and says why when it can't (a time has passed, a time is already offered).
- "Suggest other times" changes the times only: a read-only night recap of sport and pitch, their offered times struck through.
- Voice bubbles in chat don't scrub on drag (tap to seek still works), so a sideways drag is always swipe-to-reply.

### Chat gestures
- Swipe a bubble right to reply; long press lifts it (page blurs, bubble stays in place) with a glass reaction bar above and Reply / Copy / Unsend below; double tap a text bubble for ❤️.
- A chat always opens scrolled to the latest message. Exception: opened from Sessions, it centres the session card and flashes it.
- No delivery states ("Sent", "Delivered", "Read") under messages.
- Voice: hold the mic (0.15 s, a light haptic on touch-down, a firmer one when recording starts) to record; a glass rail with a padlock rises above it, drag up into it to lock, left to cancel.

### Navigation & back
- Closing or going back always returns to the screen the flow started from. A confirmation, composer or sheet opened from a profile detail is presented over that detail, never after dismissing it.
- A screen that opens a chat (Sessions, profile) pushes it in its own stack; switching tabs is only for match moments (match screen, banner).

### Actions & forms
- **A validate button is always visible.** Every screen that edits or submits something (forms, editors, sheets, onboarding steps, sub-pages) keeps its primary action pinned at the bottom (`safeAreaInset(edge: .bottom)`), never scrolled away.
- **Disabled, not hidden.** When the action can't run yet (nothing changed, required field missing), the button stays visible in its disabled state, with one short line under it saying why ("Make a change to save it.", "Add at least one sport.").
- **Button labels fit on one line.** Never let a button wrap: shorten the label, give it the full width, or stack buttons vertically.
- **Close is top-right** on every sheet and modal. Back navigation stays top-left (system).
- Unsaved changes: closing asks for confirmation ("Discard changes" / "Keep editing").
- Destructive or sensitive actions (report, block) are quiet in the layout and confirmed in a dialog anchored to the control.

### Motion & speed
- Everything answers fast. Standard springs: `snappy` (response 0.22 s), `bouncy` (0.3 s), fades 0.18 s. Swipe fly-out 0.26 s.
- Selection (chip, tile, disc, plan) uses `Motion.select`: a 0.1 s ease-out on the colour, never a spring, and never a whole-sheet `.animation` on the edited value.
- Screens open on their first frame: anything expensive is computed once and cached (contour lines per block and size, sign-up terrains at rest, picked photos decoded once, `FlowLayout` measures each chip once per pass). Long chip lists in sheets start collapsed (`SportPicker(collapsedCount: 16)` plus "All N sports"); search always covers the full catalog.
- Haptics come from generators kept warm (`Haptics` re-prepares after each use), so the tick lands with the visual change.
- No artificial waits on the user's own actions: confirmation beats last 120–250 ms at most, simulated network calls 200–400 ms (export 600 ms). Only the other person's simulated typing is allowed to take seconds.
- Motion always follows the finger or the action; nothing loops or decorates.

### Touch (nothing may block a tap)
- Every custom button label takes the touch on its whole frame: `PressScaleStyle` and `TextLinkStyle` add a content shape; any other label ends with `.contentShape(...)`. Without it only drawn pixels answer, and glass (`glassEffect`) isn't hit-testable: a glass circle answered only on its glyph (the pass button "sometimes" did nothing).
- Text actions ("Clear filters", "Forgot?", "Resend code") use `.buttonStyle(.textLink)`: the 44 pt row is the target. Never a `.frame(minHeight: 44)` applied outside a button, it adds no touch area.
- Never `.interactive()` glass on anything holding a control (buttons, the chat field): it runs its own touch handling.
- Overlays (like and super like composers, the message focus) stop taking touches the moment they start closing, then fade themselves; the presenter removes them without a second fade, so no invisible veil lingers over the page.
- Decoration never takes touches: drafting trails, contour lines, photo steps, bursts are `allowsHitTesting(false)`.
- Nothing writes state on every frame: a value that changes while scrolling or during a push (a bubble's position for the long-press lift) lives in a plain reference, not `@State`, or the whole list re-renders each frame and the screen stops answering.
- Audio session activation and player or recorder setup run off the main thread; the button flips first.
- A press that tracks the finger (holding the mic) also ends when the system cancels the touch (`@GestureState` resets), never only in `onEnded`, so it can't stay stuck.
- Decoded images are cached (`PhotoCache`, `MessageImageCache`); waveforms are drawn in one `Canvas`.
- The tabs never build on a tap. `MainTabs` is mounted 0.8 s after launch, invisible and untouchable under the welcome screen (and sign-up), and opens each tab once in the background (`isActive` false: no permission prompt, no cover, no banner, no notification work until signed in). Signing in reveals screens that already exist and lands on Discover. Measured on device: the first visit of a tab froze the tab bar 50 to 125 ms before, 0 after. Sign-out and account deletion rebuild the tabs fresh (`AppModel.sessionID`).
- `Probe` (launch argument `-probe`) logs every main-thread block over 50 ms; `-autoLogin` and `-cycleTabs` replay the welcome, sign-in and tab path, to measure on device with `devicectl device process launch --console`.
- Photos shown small pass their size (`Photo(name:side:)`, `Avatar` does it): a downsampled copy is drawn, never a 1400 px JPEG for a 56 pt avatar. Blurred photos (locked likes) pass `blur:` and get the blur baked into a small copy, never a live `.blur` on each card. `ImageStore` prepares, in the background at launch, the welcome photos, the top of the deck, every avatar size and the locked-like copies, so a tab's first visit draws without decoding and the tab bar answers at once.

### Layout
- **No loose text on the sage canvas.** Section titles and their content live inside a block (white card, or night/lime feature block).
- Long settings are split into categories that push sub-pages, not one endless page.
- Icons sit in round badges, never squares. Glyphs keep padding and never touch their badge's edge.
- Nothing hangs off a block: counts, dots and badges sit inside their button, chip or card (the filter count is inside the filter pill, the super-like count inside its disc, the "new" dot inside the likes chip).

### Headers
- Top-level tabs (Discover, Sessions, Chats, You) use the shared **`TabHeader`**, not the system large-title bar (which leaves an empty inline row above the title).
  - The title sits right under the status bar in Inter Display Black 34, and shrinks smoothly as content scrolls.
  - Once content passes underneath, a **progressive blur** appears: material fading out toward the header's bottom edge. Never an opaque fill or a hard line.
  - Search (Chats) lives in the header under the title and folds into a round search button once scrolled; tapping it opens the field again.
  - Actions sit on the right of the title row (e.g. the Discover filter pill). Side margin 16 pt, content starts 4 pt below the header.
- Pushed screens and sheets keep the native navigation bar with an inline title (Inter Display ExtraBold), close on the right, back on the left, and soft scroll-edge blur.

### Matching
- No contact before a mutual match: no messages and no session invites from Discover.
- Sessions are proposed from the chat only (calendar button or "+" menu), never from a profile.
- An invite offers 1 to 3 date-and-time options. The other person picks one, or answers with other times (a new card; the old one shows "Other times suggested"), until you agree. Only the agreed time shows as confirmed.

### Copy
- A person's name is never truncated or shrunk: it wraps onto a second line (hyphenated names break at the hyphen). Keep names out of one-line buttons ("Say hi", not "Say hi to Maximilien-Alexandre").
- NEVER use a middle dot (·) as a separator, anywhere in the app. Use a comma, "at", "for", "with", parentheses or a line break instead ("Batignolles, 4,1 km", "Tue 30 Sep at 18:30", "Buy 5 boosts for €17.99").
- The area step explains location plainly in three facts: it updates as you move (each time Drafft opens), it's blurred to about 1 km before leaving the phone, and others only see the area and a rounded distance.
- Location shows an area only ("Lyon 4", "Paris 11", or the city elsewhere), never a street. Distances are rounded to the km ("Less than 1 km" below 1). The position is blurred to a ~1 km cell before it leaves the device, and the area comes from the server (`AreaResolving`), identical on iOS and Android.
- No location pin icon next to the neighborhood on the deck card or the profile detail; the place name stands on its own.
- Sport names are never truncated with an ellipsis. Show as many as fit, then "+X" (`SportsLine`, `SportChipsPreview`).
- Interface copy is never cut with "…" in any of the 7 languages. In order: wrap (buttons take up to 2 centred lines), reflow (`AdaptiveRow`: a trailing value moves under its label; `ViewThatFits`: a pill switches to its short wording or its icon, a link row stacks), then scale (never below 0.9). Only excerpts of people's content (message previews, bios, pitches) end with "…".
- On your profile card (You tab), sports show as a stack of overlapping round badges (`SportBadgeStack`: sport symbol on a solid disc, ringed in the card colour, "+X" as the last disc beyond four).
- No training days or moments of the day on profiles. A profile shows sports and how often ("3× a week"); a session invite carries an exact date and time ("Tue 30 Sep, 18:30").

### The drafting motif
- The drafting trail (fading offset copies, as in the app icon) goes **under buttons** (primary CTAs, play, like hearts), not on cards, icons or body text.
- Exception by explicit request: the "No one here." headline of the Discover empty state, whose ghosts use the same ink as the text.

### Contour texture (block backgrounds)

Coloured feature blocks carry a **topographic contour-line texture**: the relief lines of a trail map, traced on a small generated terrain. It gives the dark and lime blocks depth and a sport/outdoor feel without competing with content. It replaces the earlier blob-and-ghost backdrops, which are retired.

**Anatomy**
- A generated, fairly **gentle** terrain: one broad **main summit** near an edge or corner of the block, 3–4 low **secondary hills and ridges** (wide, elongated, rotated), and a faint low-frequency undulation. Keep it on the flat side: rolling hills, not mountains.
- **12–14 iso-lines** are traced on it (marching squares). Spacing is uneven by nature: tight on steep slopes, loose on plateaus; lines bend around saddles, split around hills and run off the edges. Never concentric rings.
- Hairlines at **0.8 pt, 15 % opacity**. Every fifth line is an **index contour** at **1.2 pt, 30 %**, as on real maps.
- Colour follows the surface: **lime lines on night** blocks (`{colors.primary}`), **ink lines on lime** blocks (`{colors.on-primary}`), **white lines** only on the session card in chat.
- Clipped to the block's rounded shape; drawn behind content; static (never animated); decorative only (hidden from VoiceOver).

**Placement**
- The main summit sits near an edge or corner of the block, never in the middle, so the densest lines stay away from the text.
- The terrain is laid out on a fixed reference frame from the block's top-leading corner, so the texture stays put when a block grows (transcript opened, icebreaker played).
- **One fixed composition per block type**, identical on every profile and every render:

| Block | Surface | Main summit | Extra hills | Lines | Terrain (frozen) |
|---|---|---|---|---|---|
| Voice intro | night | top-right corner | 3 | 13 | `relief-5` |
| Icebreaker | night | bottom-right | 4 | 13 | `relief-5` |
| Training for (goal) | lime | upper right | 3 | 12 | `relief-4` |
| How … moves (sports) | night | right edge | 4 | 14 | `relief-4` |
| Session card (chat) | night, white lines | top-right | 3 | 12 | `relief-5` |
| Profile card (You tab) | night | top right | 3 | 13 | `relief-5` |
| Next session (Sessions tab) | night | top right | 3 | 13 | `relief-5` |

**Use it on**
- Night (`{colors.ink}`) and lime (`{colors.primary}`) feature blocks that carry one idea: voice, icebreaker, goal, sports, session invites, your profile card, the next session.

**Never use it on**
- White or sage blocks (prompts, forms, settings rows, lists), the sage canvas itself, photos, buttons, chips, sheets and editors, or empty states.
- More than one layer per block, or combined with another decorative background.

**Adding a new textured block**
- **All terrains are validated and frozen.** Each block's relief is pinned by its entry in `ContourLines.terrainVersions` (goal and sports: `relief-4`; voice, icebreaker, session card, profile card: `relief-5`). Never change these values or the compositions below.
- Give it its own entry in `BackdropSeed`, a fixed composition in `ContourLines.styles` and its own `terrainVersions` entry (summit near an edge, 3–4 low hills, 12–14 lines). Don't reuse another block's composition, and don't tweak a validated one without an explicit decision.
- In code: `.draftBlock(fill, seed: BackdropSeed.<type>, tint: <line colour>)`.
