# How it works

- `ScrollEngine` installs a `CGEventTap` at the annotated session level, after the system has picked the target app.
  Continuous events (trackpad, Magic Mouse) pass through unchanged. Line-based wheel events are swallowed, their
  distance is accumulated and then replayed frame by frame on a `CADisplayLink` with an ease-out curve.
- Each frame is a copy of the original event posted directly to the target app with `postToPid`. Posting back into the
  session tap, or into an earlier tap before the event has a target, never reaches the app.
- The fast-scroll modifier is removed from the posted events so apps don't treat them as Option+scroll.
- The display link pauses when there is nothing to scroll, so the app stays idle.
- `ButtonMapper` taps `otherMouseDown/Dragged/Up`. When the frontmost app (or "every app") has a mapping for the
  button, the click is swallowed and the shortcut is sent instead; otherwise the click passes through. When the bypass
  modifier is held, the click passes through with that modifier removed.
- Presses on MouseFlow's own settings window always stay native so the window can highlight which row a button is.
  While that window has focus, presses over other windows use the mapping of the app under the pointer, and only
  system actions are sent, since a keyboard shortcut would land in the settings window.
- Settings and button mappings are stored in `UserDefaults`.
