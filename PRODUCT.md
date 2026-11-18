# No-halla

<!-- impeccable:product-schema 1 -->

## Platform

macOS 13+ menu bar utility. SwiftUI is specified in the implementation brief. HTML design artifacts model macOS windows at their point sizes.

## Users and purpose

Developers and freelancers who keep selected desktop apps behind a VPN. They need to see whether those apps are protected and resume them immediately if needed.

## Operating context

First launch configures protected apps and a trusted IP. During normal use the menu bar icon and popover report protection. A network change triggers another IP check. A grace period precedes freezing. Trusted IP recovery resumes apps automatically. Manual resume and timed pause are available.

## Constraints

No-halla works on selected apps. The product does not set up a VPN or filter system traffic. No accounts, telemetry or cloud sync. Source of behavior is [the implementation brief](docs/IMPLEMENTATION_BRIEF.md).

## Brand and access

No-halla, «Valhalla can wait.» The gate metaphor supports the functional language. English and Russian. System appearance, keyboard navigation and VoiceOver are required. Source of product and brand decisions is [the design brief](docs/DESIGN_BRIEF.md).
