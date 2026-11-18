# Icons and symbols

[appicon.svg](exports/appicon.svg) is the original shield. [appicon-1024.png](exports/appicon-1024.png) is its 1024 × 1024 raster export. Generate the normal macOS AppIcon sizes from the vector. The source SVG also contains the metadata that names the icon.

[menubar-icons.svg](exports/menubar-icons.svg) contains five reusable SVG symbols. The preview renders them in order, 18 pt each. Export each symbol separately with its own 18 × 18 viewBox and template rendering enabled.

| Symbol ID | Image set name | States | Suggested in-window SF Symbol |
|---|---|---|---|
| protected | MenuBarProtected | Protected | shield.checkered |
| checking | MenuBarGrace | Checking, Grace | clock |
| frozen | MenuBarFrozen | Frozen | pause.circle |
| unknown | MenuBarUnknown | Unknown, Setup | exclamationmark.shield |
| off | MenuBarOff | Paused, Disabled, Bypassing | shield.slash |

Other mappings are gearshape for Settings, arrow.clockwise for Refresh, plus for Add, magnifyingglass for Search, slider.horizontal.3 for Advanced, info.circle for About, and exclamationmark.triangle for caution. The HTML mockups use equivalent custom strokes. Resolve app icons from NSWorkspace in the app. The demonstrations embed product favicons from Doop's logo lookup for Claude, Cursor and ChatGPT.
