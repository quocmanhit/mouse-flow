# How it works

- `ScrollEngine` installs a `CGEventTap` at the annotated session level, after the system has picked the target app.
  Continuous events (trackpad, Magic Mouse) pass through unchanged. Line-based wheel events are swallowed, their
  distance is accumulated and then replayed frame by frame on a `CADisplayLink` with an ease-out curve.
- Each frame is a copy of the original event posted directly to the target app with `postToPid`. Posting back into the
  session tap, or into an earlier tap before the event has a target, never reaches the app.
- The fast-scroll modifier is removed from the posted events so apps don't treat them as Option+scroll.
- Reversal is applied per output axis, after Shift has turned vertical movement into horizontal, so the horizontal
  setting controls horizontal movement whatever produced it. The non-smooth path inverts the same axes in place.
- The display link pauses when there is nothing to scroll, so the app stays idle.
- `ButtonMapper` taps `otherMouseDown/Dragged/Up`. When the frontmost app (or "every app") has a mapping for the
  button, the click is swallowed and the shortcut is sent instead; otherwise the click passes through. Two hold keys
  change that: with the native key held the click passes through, and with the All apps key held the lookup skips
  the app's own mappings. Both keys are removed from the down, drag and up events; if both are held, native wins.
- Presses on MouseFlow's own settings window always stay native so the window can highlight which row a button is.
  While that window has focus, presses over other windows use the mapping of the app under the pointer, and only
  system actions are sent, since a keyboard shortcut would land in the settings window.
- Excluded apps: both taps return the event untouched when the app it targets is excluded. Both resolve the bundle ID
  from the target pid through `ExclusionCache`, which caches per pid, clears when the list changes and refreshes
  entries whose app has terminated. `ButtonMapper` treats a click as excluded when either the app under the pointer
  or the app whose mapping would apply is excluded. It checks before stripping the hold keys, and the drag and
  release of such a press stay untouched.
- Settings and button mappings are stored in `UserDefaults`.
