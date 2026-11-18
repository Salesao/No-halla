# Open questions

- **Grace range.** The design brief sets 0–60 s and FR-21 allows 0–120 s. The mockup uses 0–60 s with a default of 5 s. Align the visible range and config validation before shipping.
- **Cancel during grace.** The design brief includes Cancel, but does not specify the protection state after it is pressed. Approve a policy before implementation. Recommend an immediate recheck with a visible state change and no hidden indefinite bypass. The Doop flow returns to Checking for the design review.
- **Repository link.** No Git remote or release repository URL is present in the project. Bind the About link to the official repository before shipping.
