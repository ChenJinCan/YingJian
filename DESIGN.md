---
name: Yingjian MVP
colors:
  surface: '#121415'
  surface-dim: '#121415'
  surface-bright: '#38393a'
  surface-container-lowest: '#0c0e0f'
  surface-container-low: '#1a1c1d'
  surface-container: '#1e2021'
  surface-container-high: '#282a2b'
  surface-container-highest: '#333536'
  on-surface: '#e2e2e3'
  on-surface-variant: '#d1c5af'
  inverse-surface: '#e2e2e3'
  inverse-on-surface: '#2f3132'
  outline: '#9a907c'
  outline-variant: '#4d4635'
  surface-tint: '#ecc14a'
  primary: '#ffd975'
  on-primary: '#3e2e00'
  primary-container: '#e6bc45'
  on-primary-container: '#624c00'
  inverse-primary: '#755b00'
  secondary: '#c9c6bf'
  on-secondary: '#31302b'
  secondary-container: '#484741'
  on-secondary-container: '#b8b5ae'
  tertiary: '#e1dcd4'
  on-tertiary: '#32302b'
  tertiary-container: '#c5c0b9'
  on-tertiary-container: '#514e49'
  error: '#ffb4ab'
  on-error: '#690005'
  error-container: '#93000a'
  on-error-container: '#ffdad6'
  primary-fixed: '#ffdf91'
  primary-fixed-dim: '#ecc14a'
  on-primary-fixed: '#241a00'
  on-primary-fixed-variant: '#594400'
  secondary-fixed: '#e6e2da'
  secondary-fixed-dim: '#c9c6bf'
  on-secondary-fixed: '#1c1c17'
  on-secondary-fixed-variant: '#484741'
  tertiary-fixed: '#e7e2da'
  tertiary-fixed-dim: '#cac6be'
  on-tertiary-fixed: '#1d1b17'
  on-tertiary-fixed-variant: '#494741'
  background: '#121415'
  on-background: '#e2e2e3'
  surface-variant: '#333536'
typography:
  display-lg:
    fontFamily: Manrope
    fontSize: 32px
    fontWeight: '700'
    lineHeight: 40px
    letterSpacing: -0.02em
  display-md:
    fontFamily: Manrope
    fontSize: 24px
    fontWeight: '600'
    lineHeight: 32px
    letterSpacing: -0.01em
  body-lg:
    fontFamily: Inter
    fontSize: 18px
    fontWeight: '400'
    lineHeight: 28px
  body-md:
    fontFamily: Inter
    fontSize: 16px
    fontWeight: '400'
    lineHeight: 24px
  label-lg:
    fontFamily: Inter
    fontSize: 14px
    fontWeight: '600'
    lineHeight: 20px
    letterSpacing: 0.02em
  label-sm:
    fontFamily: Inter
    fontSize: 12px
    fontWeight: '500'
    lineHeight: 16px
    letterSpacing: 0.01em
  display-lg-mobile:
    fontFamily: Manrope
    fontSize: 28px
    fontWeight: '700'
    lineHeight: 36px
rounded:
  sm: 0.5rem
  DEFAULT: 1rem
  md: 1.5rem
  lg: 2rem
  xl: 3rem
  full: 9999px
spacing:
  photo-height-mobile: 65vh
  photo-height-desktop: 72vh
  margin-main: 20px
  gutter-ui: 12px
  stack-gap: 8px
  floating-dock-bottom: 32px
---

## Brand & Style

The brand personality is centered on being a "quiet companion" rather than a complex tool. It aims to evoke a sense of focused calm, where the user’s photography remains the hero. The interface should feel like a premium, dark-room gallery space—unobtrusive, respectful, and sophisticated.

The design system utilizes **Deep Minimalism** mixed with **Floating Tactile** elements. It prioritizes "Result-Oriented" interactions, removing the friction of technical sliders in favor of conversational, colloquial Chinese commands. The emotional response should be one of instant gratification and creative empowerment without the intimidation of professional editing jargon.

## Interaction Structure

- Each editing project contains exactly one photo, so the editor never exposes photo counts, strips, sorting, batch scope, or an add-photo action.
- The home screen may contain multiple independent draft cards, ordered by most recently updated. Tapping a card opens that exact draft.
- “Choose a photo” always creates a new draft and never requires deleting an existing draft. Deletion is an explicit action scoped to the currently opened draft.
- The most recent draft may appear as the hero and primary continue action, while every other draft remains directly reachable in the recent-drafts list.

## Colors

This design system employs a high-contrast, dark-first palette to ensure the photo content is the primary source of light and color on the screen.

- **Global Background (#0B0D0E):** A warm, deep black that avoids the harshness of pure black, providing a rich "gallery" backdrop.
- **Brand Gold (#E6BC45):** Reserved strictly for primary calls to action, active states, and "success" moments. It serves as the "magic" highlight.
- **Soft White (#F6F2EA):** Used for primary headings and body text to ensure high legibility against the dark background while maintaining a warm, organic feel.
- **Muted Grey (#A7A39C):** For secondary information, inactive icons, and subtle borders. It recedes into the background to reduce visual noise.

## Typography

The typography strategy balances modern precision with extreme legibility for Chinese characters.

- **Headlines:** Use **Manrope** for its refined, geometric balance. It provides a contemporary feel that looks "designed" but remains approachable.
- **Body & Labels:** Use **Inter** for its neutral, systematic clarity. It is highly optimized for small UI labels and colloquial text strings.
- **Language Treatment:** When displaying Chinese characters, prioritize weight over size to maintain readability against the dark background. Use `label-lg` for most interactive buttons to ensure tap targets are clear and the language feels bold and direct.

## Layout & Spacing

The layout is content-obsessed. The top **60-72%** of the screen is a dedicated "Canvas Zone" for the photo, free from any UI overlays except for essential status indicators.

- **Bottom-Anchored Docks:** All editing controls reside in the bottom third of the screen, designed for thumb-reach.
- **Floating Capsules:** UI elements should not touch the screen edges. Use a consistent **20px margin** from the device edge.
- **Spacing Rhythm:** Use a 4px-based grid, but prioritize visual breathing room. Information density should be kept intentionally low to prevent the "professional editor" feel.
- **Responsive Behavior:** On larger screens (tablets), the photo expands to 72% height, and the bottom dock expands horizontally into a wider control bar rather than stacking vertically.

## Elevation & Depth

This design system uses **Tonal Layers** and **Subtle Blurs** to create depth without relying on heavy drop shadows.

- **Surface Levels:**
  - Layer 0: Global Background (#0B0D0E).
  - Layer 1: Floating Capsules/Docks (Semi-transparent black at 80% opacity with a 16px backdrop blur).
- **Outlines:** Instead of shadows, use a **0.5px or 1px border** (Soft White at 10-15% opacity) on floating elements to define their shape against the deep background.
- **Focus State:** When a tool is active, the capsule’s border color transitions to Brand Gold (#E6BC45).

## Shapes

The shape language is **Soft and Pill-shaped**. Every interactive element—from command inputs to action buttons—uses high corner radii to evoke a friendly, approachable "appliance" feel rather than a "software tool" feel.

- **Primary Containers:** Use `rounded-xl` (1.5rem / 24px) for the main bottom dock.
- **Floating Buttons/Capsules:** Use `rounded-full` (Pill-shape) for action triggers and voice command bars.
- **Photo Canvas:** The photo itself should have a slight `rounded-lg` (1rem / 16px) corner to separate it from the device frame, enhancing the "object" feel.

## Components

### Floating Command Bar

The central component is a pill-shaped input field at the bottom. It uses Soft White text for colloquial Chinese prompts (e.g., "帮我调亮一点" - "Make it a bit brighter"). It features a Brand Gold microphone icon for voice input.

### Action Capsules

Buttons are never square. They are always pill-shaped with significant horizontal padding. Primary actions (like "Save" or "Apply") use a Brand Gold background with Global Black text.

### Result Cards

Small, horizontally scrolling thumbnails at the bottom that show "Instant Previews" of different result styles. These cards should have 12px rounded corners and a Brand Gold border when selected.

### Tool Docks

A lightweight, semi-transparent dock that houses 3-4 primary category icons. Use "No-label" icons here to maintain a clean look, but show a colloquial label (e.g., "修人像", "调色彩") in Soft White above the dock when the category is tapped.

### Modals & Overlays

Avoid traditional full-screen modals. Use "Bottom Sheets" that only slide up to 40% of the screen height, ensuring the photo remains visible and the user never feels like they have "left" the editing context.

## Unified Interaction Contract

The production experience uses one task path and one editor shell:

> Select photos → see the first result → describe or refine in the shared dock → apply → export

### Home

- Home only starts a new edit, resumes the current draft, and opens Settings.
- Do not use a tab bar for commands or destinations that do not preserve navigation state.
- Do not expose unavailable camera or AI actions as tappable controls.
- Settings has one visible entry. A current draft makes “Continue editing” the primary action; starting over is secondary and explicitly confirms replacement.

### Editor Shell

- The top bar owns Back, Undo/Redo, and Export for the current photo.
- The photo remains in the same canvas while command, manual, atmosphere, and lighting controls change below it.
- Atmosphere and lighting are dock states, never separate editor routes.
- Only one editing dock is visible at a time. Closing a tool returns to the command dock without moving or recreating the photo canvas.

The shared dock has four observable states:

1. `command`: text/voice entry, contextual quick actions, and manual refinement.
2. `adjusting`: one active manual, atmosphere, or lighting control.
3. `previewing`: a temporary result awaiting a safe render or user decision.
4. `exporting`: progress, cancellation, partial failure, and final result.

Photo capability analysis runs in the background after import. It may enable
applicable tools, but it must not change the recipe, create a decision gate, or
block the command dock.

The MVP is single-photo only. The picker requests exactly one photo, and the
editor does not expose add-photo, ordering, thumbnail-strip, group scope, photo
count, or batch-export controls. Export always targets the current photo.

### State Language

- **Preview** is temporary and must be rendered successfully before it can be applied.
- **Apply** creates one serializable, undoable edit transaction.
- **Undo** reverses the latest applied transaction.
- Draft persistence is automatic and is not presented as a tool-level Save action.
- **Export** is the only action that creates the final image file.

### Voice and Text

- Voice and typed commands share the same text field and planning path.
- A supported, unambiguous request applies after preview validation without a second confirmation screen.
- Ask at most one clarification when multiple materially different targets are valid.
- Never show editable-looking summary chips unless changing a chip changes the actual operation draft.
- Failure leaves the previous image state intact and keeps the command editable.
