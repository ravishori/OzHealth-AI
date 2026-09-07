# UI MD3 Healthcare Redesign — Change Log

**Branch:** `cursor/ui-md3-healthcare-redesign-4e78`  
**Scope:** Presentation layer only. Business logic, APIs, providers, models, and route paths are preserved.

## Goals

Elevate VitaPulse / HealthNest toward a premium healthcare interface (Apple Health / Google Fit / One Medical–inspired) on Material Design 3, with:

- Consistent **8px spacing** and **16px** default corner radius  
- Subtle elevation (soft shadows) instead of flat bordered cards  
- Dynamic greeting, AI insight teaser, modern metric cards  
- Glassmorphism on the home brand pill  
- Smooth page / section transitions and shimmer loading  
- Dark mode retained via existing Appearance / ThemeManager  
- Accessibility semantics + reduced-motion respect  
- Responsive phone / tablet column counts  

## Design tokens

| File | Change |
|------|--------|
| `lib/theme/design_tokens/app_spacing.dart` | `screenHorizontal` → 16; `itemGap` → 16 (8px grid) |
| `lib/theme/design_tokens/app_radius.dart` | Default button/textField → 16; `card` alias; square cards use 8 |
| `lib/theme/app_theme_builder.dart` | Soft card elevation + quiet outline; `scaffoldBackgroundColor` uses `surfaceContainerLowest`; `pageTransitionsTheme` fade-upwards |

## New reusable widgets

| Widget | Path | Purpose |
|--------|------|---------|
| `SoftSurface` / `GlassSurface` | `shared/widgets/premium_surface.dart` | Elevated / glass containers |
| `TapScale` | `shared/widgets/tap_scale.dart` | 0.96 press feedback |
| `SectionHeader` | `shared/widgets/section_header.dart` | Icon + title + subtitle row |
| `HealthMetricCard` | `shared/widgets/health_metric_card.dart` | Dashboard vitals chips + shimmer |
| `DynamicGreeting` / `DynamicGreetingText` | `shared/widgets/dynamic_greeting.dart` | Time-of-day greeting (no emoji) |
| `AiInsightTeaser` | `shared/widgets/ai_insight_teaser.dart` | Advisory teaser → `/home/insights` |
| `ResponsiveLayout` / `ResponsiveContent` | `shared/widgets/responsive_layout.dart` | 2/3/4 columns + max width |
| `FadeSlide` | `shared/widgets/fade_slide.dart` | Staggered section entrance |
| `fadeThroughPage` | `core/router/page_transitions.dart` | go_router fade/slide helper |

## Screen updates

### Home (`home_screen.dart`)

- Greeting uses `DynamicGreetingText` (icon instead of 👋).  
- Brand pill uses `GlassSurface`.  
- Today’s Health uses `HealthMetricCard` with shimmer while APIs load (same endpoints).  
- New `AiInsightTeaser` navigates to existing insights route (no new API).  
- Sections use shared `SectionHeader`, `FadeSlide`, `TapScale`.  
- Columns via `ResponsiveLayout.featureColumns`.  

### Drawer (`app_drawer.dart`)

- Section titles cleaned (emoji removed for a11y / premium tone).  
- Navigation targets unchanged.

### Shared polish

- `InfoCard` → `SoftSurface` elevation.  
- `EmptyState` → rounded container, semantics, 8px padding tokens.  

### Router

- `/home/ai-chat` and `/home/insights` use `fadeThroughPage` (paths unchanged).

## Explicit non-changes

- No API / provider / model / auth changes.  
- No Azure / staging / DB migrations.  
- Checklist / feature status docs not updated.  
- Clinical safety copy and Australia eRx boundaries untouched.  
- Theme variants + Appearance dark mode still Hive-persisted.

## Testing

- Widget tests: `test/ui_md3_healthcare_widgets_test.dart`  
- Full suite: `flutter test`, `flutter analyze` (0 errors expected)

## Follow-ups (optional next UI sprints)

- Apply `SoftSurface` / `SectionHeader` to remaining feature hubs (records, reminders, medicines).  
- Expand `fadeThroughPage` to more feature routes.  
- Optional expressive typeface via `google_fonts` (not added this sprint to avoid network/font flakiness in CI).
