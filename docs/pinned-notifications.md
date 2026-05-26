# Pinned notifications

macOS banners disappear after a few seconds and slide into the (easily ignored)
Notification Center. BannerShift's pinned list keeps the notifications you care
about visible: any rule can copy a matching notification into a small,
always-on-top panel that stays on screen until you dismiss it. Think of it as the
Outlook reminder window on Windows — a persistent, glanceable list of "don't
forget about these."

For where this fits among the other rule options and settings, see
[configuration.md](configuration.md); this page covers the feature itself.

## Turning it on

Pinning is a per-rule option, so you choose exactly which notifications persist.

1. Open **Rules…** from the menu bar and add or edit a rule.
2. Set the patterns that identify the notifications you want to keep (for
   example, app `Calendar`, or title `*standup*`).
3. Check **Also pin to the always-on-top list**.
4. Save.

From then on, every banner that matches the rule is both repositioned (if the
rule sets a position) **and** copied into the pinned list. Repositioning and
pinning are independent: a rule can do either, both, or — if it sets no position
override — just pin.

> [!NOTE]
> Only rules with the pin option checked add to the list. A notification that no
> rule pins is repositioned (or left alone) as usual and never appears here.

## The panel

The list lives in a floating panel titled **Pinned Notifications**:

- It **stays above other apps' windows**, follows you across Spaces, and shows
  over full-screen apps, so it's there when you glance back.
- It **never steals focus** — clicking it won't pull you out of what you're
  doing.
- It appears at the **top-right** of your main display the first time something
  is pinned. **Drag it anywhere**; the position is remembered across launches.
- It's only visible while the list has items. Dismiss the last one and it
  disappears; it returns when something new is pinned.

Each row shows the source app, the notification title, and up to two lines of
body text.

### Grouping and counts

Repeat notifications from the same app with the same title **collapse into one
row** rather than stacking up. The row carries a count badge (for example,
`Slack · 3`) and shows the most recent body text. The freshest group moves to the
top of the list, so the latest activity is always nearest the top.

### Dismissing

- Click the **×** on a row to remove that group.
- Click **Dismiss All** in the footer to clear the whole list.
- Click anywhere else on a row to **open the source app** (when BannerShift could
  resolve which app it was).

## Limits and lifetime

> [!IMPORTANT]
> The pinned list is **in-memory only**. It is *not* persisted: quitting or
> relaunching BannerShift starts with an empty list. Only the panel's on-screen
> position is saved between launches — never any notification content.

The list holds at most **50 groups** (`Constants.maxPinnedItems`). When a new
group would push past that, the oldest group at the bottom is evicted. In
practice you'll dismiss items long before hitting the cap; it exists to bound
memory and keep the panel from growing taller than the screen.

## Privacy

Pinned notification text is treated exactly like every other notification
BannerShift reads: held in memory only, and never written to disk unless you
explicitly enable debug logging. See [SECURITY.md](../SECURITY.md#security-model)
for the full model.
