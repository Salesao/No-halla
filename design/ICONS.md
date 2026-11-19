# Icons and symbols

[appicon-1024.png](exports/appicon-1024.png) is the selected bronze gateway artwork from the Doop GatewayAppIcon component, cropped with the 22.5% rounded corners shown in the design. Generate all macOS AppIcon sizes from this raster. Use the same artwork in the dashboard header, About, alerts and notifications. The menu bar status symbols remain separate template glyphs.

[menubar-icons.svg](exports/menubar-icons.svg) contains five reusable SVG symbols. The preview renders them in order, 18 pt each. Export each symbol separately with its own 18 × 18 viewBox and template rendering enabled.

| Symbol ID | Image set name | States | Suggested in-window SF Symbol |
|---|---|---|---|
| protected | MenuBarProtected | Protected | shield.checkered |
| checking | MenuBarGrace | Checking, Grace | clock |
| frozen | MenuBarFrozen | Frozen | pause.circle |
| unknown | MenuBarUnknown | Unknown, Setup | exclamationmark.shield |
| off | MenuBarOff | Paused, Disabled, Bypassing | shield.slash |

Other mappings are gearshape for Settings, arrow.clockwise for Refresh, plus for Add, magnifyingglass for Search, slider.horizontal.3 for Advanced, info.circle for About, and exclamationmark.triangle for caution. The HTML mockups use equivalent custom strokes. Resolve app icons from NSWorkspace in the app. The demonstrations embed product favicons from Doop's logo lookup for Claude, Cursor and ChatGPT.
