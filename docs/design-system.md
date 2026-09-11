# Design System

> Visual language for **Flames** (`ai.hermes.flames`, package `flutter_ai_agent`).
> Built for an autonomous, technical, agentic mobile terminal workstation.
>
> Source files:
> - `lib/core/theme/app_theme.dart` — Core Dark Slate & Teal Theme (`AppTheme`)
> - `lib/core/theme/hermes_theme.dart` — Technical Terminal Theme (`HermesTheme`, `HermesColors`)
>
> Related: [`architecture.md`](./architecture.md), [`rules.md`](./rules.md).

---

## 1. Foundations

| Concern | Specification |
|---|---|
| Platform targets | Android, iOS, Linux / Desktop |
| Default theme | **Dark Mode Only** |
| Accent color | Teal `#008080` / Hermes Neon `#EDFF45` / Blue `#0000F2` |
| Surface background | Dark Slate `#0F172A` / Stage `#0A0A20` |
| Font families | System Sans, Google Fonts (`Oswald`, `IBM Plex Sans`, `JetBrains Mono`) |
| Iconography | `Icons.*` only — **ZERO emoji icons** in UI chrome, headers, or cards |

---

## 2. Color Tokens

### 2.1 Core App Theme (`AppTheme`)

| Token | Hex Value | Usage |
|---|---|---|
| `darkSurface` | `#0F172A` | Primary app scaffold background, dark cards |
| `accentTeal` | `#008080` | Primary action buttons, FAB, send button, active toggles |
| `onSurface` | `#FFFFFF` | Primary readable text and headings |
| `surfaceBorder` | `#334155` | Card outlines, dividers, input borders |

### 2.2 Hermes Terminal Theme (`HermesColors`)

| Token | Hex Value | Usage |
|---|---|---|
| `deepObsidian` / `stage` | `#0A0D14` | Terminal background stage, scaffold |
| `cardSurface` / `surface` | `#131926` | Panel cards, tool call inspection containers |
| `border` / `surfaceBorder` | `#1E293B` | Card outlines, dividers, input borders |
| `electricTeal` / `info` | `#00F2FE` | Primary technical accent, active focus |
| `accentTeal` | `#008080` | Primary action buttons, FAB, active toggles |
| `emerald` / `success` | `#10B981` | Running gateway status, connected RPC |
| `amber` / `warning` | `#F59E0B` | Achievement tier badges, warnings |
| `danger` | `#FFFF8442`| Rejected actions, execution failures, error states |
| `inkPrimary` | `#F8FAFC` | High-contrast body text |
| `inkSecondary` | `#94A3B8`| Secondary labels, timestamps, metadata |
| `inkMuted` | `#64748B` | Subtle hints, muted labels |
| `codeBg` | `#060612` | JSON viewer / code snippet background |

---

## 3. Component Specifications

### 3.1 Chat Bubbles & Streaming Output
- **User bubble**: Right-aligned, dark surface card with subtle border, white text.
- **Assistant bubble**: Left-aligned, markdown-rendered text (`flutter_markdown`).
- **Streaming state**: Subtle pulsing typing indicator when `AgentStreaming` or `AgentThinking` is emitted.

### 3.2 Tool Call Cards
- Nested inside or adjacent to the assistant stream.
- Shows tool name, execution tier badge (Tier 1 Auto / Tier 2 Permission / Tier 3 HITL), and expandable JSON parameters.
- Background: `#18182D` (`HermesColors.surface`) or `#1E293B` with `0.8px` hairline border.

### 3.3 Human-in-the-Loop (HITL) Action Approval Sheet (`ActionApprovalSheet`)
- Bottom sheet modal displayed when `WaitingApproval` state is active.
- Prominently displays tool name and formatted JSON parameters.
- Actions:
  - **Approve**: Green / Accent primary button (`#008080` or `#6EFFD6`).
  - **Reject**: Red / Danger button (`#FFFF8442`).
- Prevents dismiss without explicit action if critical security action is pending.

### 3.4 Header Console / Status Bar (`HeaderConsoleBar`)
- Top status header displaying active connection status and agent progression.
- Components:
  - **Gateway Status Chip** (`GatewayStatusChip`): Monospace pill with pulsing green dot (`PulsingDot` in `#10B981`) showing gateway connection state (e.g. `Running 8644`).
  - **Achievement Tier Badge** (`AchievementTierBadge`): Monospace tier pill with amber bolt icon (`Icons.bolt` in `#F59E0B`) displaying gamified rank (e.g. `Olympian • 47/60 Badges`).
- Border: `#1E293B` bottom border, background `#0A0D14`.

---

## 4. Iconography & Anti-Slop Rules

1. **Zero emoji in chrome**: Never use unicode emojis (e.g. ⚙️, 🚀, 🤖, ⚠️) in headers, navigation items, buttons, or action cards. Use Flutter Material icons (`Icons.settings`, `Icons.terminal`, `Icons.security`, etc.).
2. **Consistent iconography**:
   - Settings: `Icons.settings`
   - Send: `Icons.send`
   - Reset: `Icons.refresh`
   - Torch: `Icons.flash_on` / `Icons.flash_off`
   - Tool execution: `Icons.build`, `Icons.code`
   - HITL Shield: `Icons.shield` / `Icons.verified_user`
