# YouTube Floating Remote Design

## Goal

Add a Safari Web Extension companion for Hazakura Amp that gives users a small on-page control while watching YouTube.

The extension is not a YouTube customization suite. It is a thin remote for Hazakura Amp's existing 0-400% system audio boost, plus a minimal repeat toggle for the current YouTube video.

## Approved Direction

Use a compact floating bar on YouTube pages.

- Show a `Boost` slider from 0% to 400%.
- Show the current boost value as a percentage.
- Show a `Repeat` toggle for the current video.
- Provide a collapse or close affordance so the bar can get out of the way.
- Do not replace or redesign YouTube's own player controls.

The Safari extension owns the YouTube page integration. Hazakura Amp owns all audio processing.

## Architecture

### Containing App

Hazakura Amp remains the native macOS app and the source of truth for boost state.

- Existing Core Audio / ScreenCaptureKit pipeline applies the actual gain.
- The app exposes a narrow command surface for the Safari Web Extension.
- The command surface supports reading current state, setting gain, and requesting start.
- The native app decides whether a start request can succeed. If permissions or runtime state block startup, the extension shows the app-provided status instead of pretending boost is active.

### Safari Web Extension

The Safari Web Extension injects a content script on YouTube watch pages.

- The content script renders the floating bar.
- Slider changes are sent to the extension background layer.
- The background layer relays boost commands to the native app with Safari native messaging.
- The extension persists small UI preferences, such as collapsed state and repeat preference, in extension storage.

### YouTube Repeat

Repeat stays page-local and minimal.

- Detect the current page's primary `video` element.
- Prefer setting `video.loop = true` when repeat is enabled.
- Reapply repeat when YouTube SPA navigation changes the current video.
- Do not manage playlists, queues, shorts behavior, captions, playback speed, or YouTube volume.

## Data Flow

```
YouTube floating bar
  -> content script
  -> extension background
  -> Safari native messaging
  -> Hazakura Amp app
  -> existing audio boost pipeline
```

For repeat:

```
YouTube floating bar
  -> content script
  -> current HTMLVideoElement.loop
```

## Scope

- Add a Safari Web Extension target or package that can run on `youtube.com`.
- Render one compact floating bar on YouTube watch pages.
- Send 0-400% boost changes to Hazakura Amp through native messaging.
- Keep boost state synchronized enough that opening a YouTube page reflects the app's current configured gain.
- Add one-video repeat for the currently loaded YouTube video.
- Keep the feature macOS-first until the native app communication path is proven.

## Non-Goals

- Do not implement a general YouTube enhancer.
- Do not replace YouTube's volume control.
- Do not boost audio inside YouTube with Web Audio as the primary path.
- Do not add playlist repeat, queue management, autoplay rules, shortcuts, subtitles, speed controls, sponsor skipping, ad blocking, or analytics.
- Do not require broad host permissions beyond the YouTube domains needed for this feature.

## UX Requirements

- The bar must be visually quiet and small.
- It should default to a fixed corner position rather than covering YouTube's main controls.
- It must stay usable in normal and theater mode.
- Fullscreen support is outside the first implementation. If it works naturally, keep it; if it is fragile, do not chase it in the MVP.
- The control must have clear labels for keyboard and assistive technology users.

## Permissions And Privacy

- Request YouTube host access only for page injection.
- Request native messaging only for communicating with Hazakura Amp.
- Do not inspect, store, or transmit watch history.
- Do not collect audio data. Audio processing remains local in the native app.
- Explain in user-facing copy that the YouTube overlay is a remote for Hazakura Amp, not a recorder.

## Risks

- YouTube is a single-page app, so content script initialization must handle navigation without full page reloads.
- YouTube DOM and fullscreen behavior can change without warning.
- Safari native messaging may require an Xcode packaging path and careful entitlement setup.
- If Hazakura Amp is not running, the extension needs a calm failure state instead of silently doing nothing.
- If the native audio path is stopped, setting gain alone may not make the boost audible unless the app starts or prompts the user.

## Verification

- Load the extension on YouTube in Safari.
- Confirm the floating bar appears once on a watch page.
- Navigate between videos without a full page reload and confirm the bar remains single-instance.
- Move the boost slider and confirm Hazakura Amp receives the requested 0-400% value.
- Confirm the existing audio pipeline applies the value, using the app's diagnostics or focused app-side tests.
- Enable Repeat, let a video end, and confirm the same video restarts without changing YouTube volume or other controls.
- Confirm disabling Repeat restores normal ended behavior for a single video.
- Run the existing Hazakura Amp app tests after adding the native message command surface.
