# TurboFieldfare Mac Design System

## 1. Atmosphere & Identity

TurboFieldfare is a quiet native utility: operational, legible, and explicit
about long-running model work. Its signature is a restrained fieldfare-green
accent used only for primary actions and healthy state, while native macOS
materials and controls carry the rest of the interface.

## 2. Color

| Role | Token | Value | Usage |
| --- | --- | --- | --- |
| Accent | `TurboFieldfareMacTheme.accentColor` | sRGB 106, 186, 113 | Primary actions, healthy emphasis |
| Surface/primary | `windowBackgroundColor` | macOS semantic | Window background |
| Surface/secondary | `controlBackgroundColor` | macOS semantic | Cards and status capsules |
| Text/primary | `primary` | macOS semantic | Titles and values |
| Text/secondary | `secondary` | macOS semantic | Explanations and labels |
| Text/tertiary | `tertiary` | macOS semantic | Paths and low-priority metadata |
| Border | `separator` at 50% | macOS semantic | Subtle card outlines |
| Status/success | `green` | macOS semantic | Ready state |
| Status/warning | `orange` | macOS semantic | Starting and external-server states |
| Status/error | `red` | macOS semantic | Launch and runtime failures |

No fixed light/dark surface colors are introduced; semantic macOS colors must
continue to adapt to system appearance and accessibility settings.

## 3. Typography

| Level | SwiftUI style | Weight | Usage |
| --- | --- | --- | --- |
| H1 | `.title` | bold | Screen identity |
| H2 | `.title3` | semibold | Card title |
| Body | `.body` | regular | Primary explanation |
| Supporting | `.callout` | regular or medium | Status and secondary content |
| Caption | `.caption` | regular or medium | Labels and metadata |

The primary family is the macOS system font. Endpoints, paths, byte counts, and
other machine-readable values use the system monospaced design.

## 4. Spacing & Layout

Spacing follows a 4-point base:

| Token | Value | Usage |
| --- | --- | --- |
| `space-2` | 8 pt | Tight icon and label groups |
| `space-3` | 12 pt | Row and action spacing |
| `space-4` | 16 pt | Standard inner padding |
| `space-5` | 20 pt | Comfortable horizontal padding |
| `space-6` | 24 pt | Card padding |
| `space-8` | 32 pt | Major content groups |
| `space-12` | 48 pt | Screen edge and identity spacing |

Installer screens use one centered readable column, capped near 620 points.
The server screen uses a status column and a 340-point configuration column
inside a scrolling canvas. It must remain usable at the app window minimum size
without horizontal scrolling.

## 5. Components

### Utility Card

- **Structure:** rounded semantic surface, subtle separator outline, content stack.
- **Variants:** information, warning, error.
- **States:** static; interactive controls inside retain native macOS states.
- **Accessibility:** information remains available as text, never color alone.

### Status Indicator

- **Structure:** semantic dot or progress indicator plus a short status label.
- **Variants:** stopped, starting, ready, external, failed.
- **States:** starting uses native indeterminate progress; all others are steady.
- **Accessibility:** combined label and value describe the complete state.

### Primary Action Cluster

- **Structure:** native macOS buttons in a 12-point cluster.
- **Variants:** primary, secondary, destructive stop.
- **States:** native hover, focus, press, disabled, and keyboard behavior.
- **Accessibility:** visible labels describe the action without relying on icons.

### Server Configuration Card

- **Structure:** native pickers, toggles, sliders, and steppers grouped by
  runtime concern.
- **Variants:** load-time controls and request-default controls.
- **States:** editable while the owned server is ready; changes show an explicit
  restart-required message and **Apply & Restart** action.
- **Accessibility:** every control has a visible label and current value; API
  override behavior is described in text.

### Menu-Bar Status

- **Structure:** state icon followed by Server RSS and latest decode token rate.
- **Variants:** stopped, starting, ready, external, and failed.
- **States:** metrics appear when available; unknown values use an em dash
  rather than a fabricated zero.
- **Menu:** server status, detailed metrics, open window, copy URL/key,
  start/stop, and quit.

## 6. Motion & Interaction

State transitions use SwiftUI's standard smooth animation at 200–300 ms.
Activity is communicated with native `ProgressView`; no decorative animation is
added. Native controls own hover, focus, press, and reduced-motion behavior.

## 7. Depth & Surface

The strategy is mixed native material: tonal surface shifts plus a half-point
semantic separator outline. Custom drop shadows, glass effects, and decorative
gradients are not part of the utility-card vocabulary. The window may retain
the existing subtle accent-mixed background gradient.

## 8. Accessibility Constraints & Accepted Debt

### Constraints

- Respect system light/dark appearance, increased contrast, and reduced motion.
- Every status has a text label; color is supplementary.
- All actions are keyboard reachable with native focus treatment.
- Long endpoints and paths may truncate visually but expose their complete value
  through selection, copy actions, accessibility, or help text.
- Body text does not use a style smaller than `.callout`; `.caption` is limited
  to labels and metadata.

### Accepted Debt

None.
