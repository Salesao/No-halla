# No-halla brand

Write **No-halla**, pronounced “no-HAH-lah”. Keep the capital N and the hyphen. The tagline is **Valhalla can wait.** In Russian, **Вальхалла подождёт.**

| Phrase | Meaning |
|---|---|
| The gate | VPN tunnel |
| Trusted realm | Trusted IPv4, IPv6 or CIDR |
| Waiting at the gate | Selected apps are frozen (onboarding and notification imagery) |
| The gate is open | Traffic is allowed: trusted IP, paused, or disabled |
| The gate is closed | Selected apps are frozen |
| The gate is ajar | Manual resume bypass window |
| The watch | No-halla and its watchdog |

Use calm sentence case. Add lore in a supporting line, on About or in a notification title. Keep functional state labels and actions explicit. The notification body describes the event and available action. Avoid language about combat, death, sacrifice or blame.

| Role | Light | Dark | Use |
|---|---|---|---|
| Fjord | `#16323B` | `#0E1F26` | Icon, illustration base and dark shell |
| Fjord light | `#2A4A55` | `#1C333D` | Distant ridge and dark group surface |
| Bronze | `#B5763A` | `#D9A066` | Gateway metal, gate line, rims and selected-tab underline |
| Bronze highlight | `#D9A066` | `#E8BE8A` | Metal light and thin gate lines |
| Bone | `#E8E0D0` | `#E8E0D0` | Light decorative line work |
| Ember | `#C65A3A` | `#D9765A` | Optional decorative accent |

**Selected icon.** The bronze gateway in a ring on a dark fjord background is the full-colour application identity. Use the same image in both appearances at every app icon size; see [the icon export](exports/appicon-1024.png) and the Doop GatewayAppIcon component. The separate menu bar status glyphs retain their existing monochrome designs.

Draw the menu bar glyph in one color at 18 pt with a 1.4 pt outline and no ornament. Render as a template so macOS supplies the foreground. The native shell uses the deep fjord and raised group tones in dark mode. Reuse the 24 short marks in the 1 pt header divider and About. Bronze is decoration on the pill, selected tab and frozen row. The functional text, glyphs and primary actions keep their semantic colors. Onboarding, About and compact empty-state vignettes share the amber gateway in teal mountains (`exports/gate-scene.png`) in both appearances.
