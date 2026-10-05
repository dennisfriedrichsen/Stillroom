Build a native Apple TV app called **AlbumLoop** that reliably plays slideshows of complete albums from my ordinary iCloud Photos library.

Implement the app, not just an architecture proposal. Make reasonable implementation decisions and proceed unless you encounter a genuine blocker.

## My situation

- My Apple TV has approximately 32 GB of storage.
- My iCloud Photos library is over 300 GB.
- These are ordinary Photos albums, not Shared Albums.
- Apple’s built-in Photos slideshow often plays approximately the first ten pictures repeatedly instead of progressing through the album.
- The problem appears related to pictures that haven’t downloaded locally, but that diagnosis is unconfirmed.
- I want to select an album with the Apple TV remote and reliably play every photo, including photos that must load from iCloud.
- I do not want to export albums, mirror my library to another server, or keep my Mac or iPhone running during playback.

## Verify feasibility first

Check current Apple documentation and the installed tvOS SDK for public PhotoKit support, authorization, album enumeration, and image retrieval on tvOS.

Do not assume that an API available on iOS works identically on tvOS. Verify access to ordinary iCloud Photos albums specifically. Clearly identify anything that needs validation on a physical Apple TV.

If a platform limitation prevents direct access, explain the precise limitation before changing the architecture. Do not implement private APIs, Apple Account credential collection, iCloud scraping, or an unrelated replacement workflow.

## Technology and scope

Use Swift, SwiftUI where appropriate, PhotoKit, and structured concurrency. Use UIKit where needed for reliable tvOS behavior.

Choose and document a reasonable deployment target based on verified API availability. Keep dependencies minimal.

Version one should display still photos. Show Live Photos as still images and explicitly exclude videos from the playback count. Music, elaborate transitions, and video playback are out of scope.

## User experience

1. Request Photos access with an understandable explanation.
2. Handle denied, restricted, unavailable, and empty-library states.
3. Show accessible albums with names, thumbnails, and eligible still-photo counts.
4. Allow selecting an album and starting a slideshow.
5. Provide:
   - Sequential playback using album order where publicly supported.
   - A documented fallback order if album order is unavailable.
   - Shuffle without repeating an image until the cycle completes.
   - Loop on/off.
   - Adjustable slide duration, with a default of 8 seconds.
   - Pause/resume and previous/next using the Siri Remote.
   - An optional “Photo 127 of 600” overlay.
   - Fit-to-screen display that preserves the entire photo’s aspect ratio.
6. Use a simple dark interface, visible focus states, and controls that hide during playback.
7. Keep the display awake during active slideshow playback and restore normal behavior when leaving it or backgrounding the app.

## Critical playback requirements

The complete album sequence and the downloaded-image buffer must be independent.

For example, a 600-photo album must remain a 600-item sequence even if only five images are currently buffered. Never treat the locally cached subset as the complete album.

- Snapshot eligible asset identifiers at the start of a slideshow.
- Track position independently of download completion.
- Advance only according to the playback sequence.
- Start a slide’s display timer when an acceptable image is actually displayed.
- If the next image is loading, hold the current image and show a subtle loading indication.
- A loading failure must never reset playback to the first image or trigger an early loop.
- Pause must stop automatic advancement while allowing useful prefetch work.
- Previous/next must behave predictably during downloads and transitions.
- Shuffle should create a permutation per cycle, retain navigable history for that cycle, and avoid an immediate boundary repeat when possible.
- Handle album edits or deleted assets gracefully without silently rebuilding the sequence mid-cycle.

## iCloud loading and memory management

Use public PhotoKit image requests with network access explicitly enabled where required.

Implement an app-owned, bounded rolling buffer:
- Prioritize the image currently needed.
- Prefetch a small configurable number of upcoming images.
- Retain a small number of previous images for back navigation.
- Bound both download concurrency and decoded-image memory use.
- Request images appropriate to the actual display’s pixel dimensions rather than original-resolution camera files unnecessarily.
- Evict older app-owned images as playback advances.
- Cancel obsolete requests after album changes, navigation, or leaving playback.

Do not assume PhotoKit preheating guarantees cloud downloads have finished. Track actual request completion and readiness.

Correctly handle:
- Multiple PhotoKit callbacks for one request.
- Degraded previews versus final results.
- Cloud-only assets.
- Download errors and cancellations.
- Late callbacks after the user changes albums or navigates.
- Memory pressure and app lifecycle changes.

Do not make persistent local copies of the entire album or library. Treat system caches as purgeable and outside our control.

## Failure handling

Use bounded automatic retries with backoff and a recoverable stalled-download state. Avoid infinite silent waiting.

After retries fail, hold the current image and offer Retry or Skip. If the user skips an unavailable image, record that explicitly. Report any skipped images at the end of a cycle rather than claiming that every photo was displayed.

If nothing can load, show a useful error instead of spinning or looping.

Recover from temporary network loss without losing the slideshow’s position.

## Architecture and diagnostics

Separate:
- Photos authorization and album access.
- Asset/image loading.
- Playback sequence and state.
- SwiftUI/tvOS presentation.

Use an explicit playback state model to prevent timer/download/navigation races. Keep UI updates on the main actor.

Include useful development diagnostics:
- Eligible album count.
- Current sequence position.
- Displayed, buffered, pending, failed, and skipped counts.
- Image-request durations, retries, and errors.

Use local structured logging. Do not log image contents or send photo information to external services.

## Verification

Write focused tests for playback logic using a fake image provider. Cover:
- An album larger than the buffer plays completely before repeating.
- Delayed downloads do not reset or truncate the sequence.
- Out-of-order completion does not reorder playback.
- Shuffle does not repeat within a cycle.
- Pause and manual navigation during loading.
- Failures, retries, and explicit skips.
- Stale callbacks from a previous album or playback session.
- Buffer bounds.

Provide a physical-device test checklist for:
- A large album containing cloud-only images.
- At least one full sequential cycle and one full shuffle cycle.
- Network loss and recovery.
- Leaving and reopening playback.
- Verifying counts against Photos.

Clearly distinguish mocked tests, simulator checks, and behavior actually verified on physical hardware. Do not claim iCloud reliability based only on mocks.

## Deliverables

- A complete buildable Xcode project, with all source files and required Photos permission configuration.
- A README explaining architecture, supported OS versions, limitations, and how to build.
- Exact instructions for signing, pairing, installing, and running on my physical Apple TV.
- Explain current free Apple Account versus paid Developer Program deployment options and limitations; do not assume I have a membership.
- Tests and the physical-device verification checklist.

If your environment cannot run Xcode, still create the complete project and clearly identify the build and device checks I must run locally.

Start with the smallest end-to-end implementation that lists a real album and retrieves photos beyond the initially cached subset, then complete the playback and reliability requirements above.