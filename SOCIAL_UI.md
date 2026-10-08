# Social UI update

The existing homepage sections and routes are preserved. `social-ui.js` extends the current school-life screens and uses the existing Supabase tables.

- Mobile dock: show/hide, up to four shortcuts, reset to defaults. The settings button remains accessible when hidden; all sections remain in the main menu. Preferences are device-local.
- School chat: compact header, date groups, own-message alignment, search, reply quotes, emoji insertion, growing composer, and a per-school local draft. Desktop Enter sends, Shift+Enter inserts a line; touch devices keep multiline Enter. Quotes are persisted in the existing message body. Message polling preserves the draft and filtered feed.
- Reels: vertical scroll snapping, only the visible video plays, pause/resume, mute toggle, seeking, previous/next buttons, keyboard controls, sharing, local likes, and a readable unavailable-video state. Reduced-motion mode requires explicit playback.
- Three original silent procedural WebM clips are included under `public/media/`, explicitly labelled as demo animations. These are not generated through an AI video service.

No new migration is required. Shared school data still requires the previously documented Supabase migration and production authentication. Likes and navigation settings are local; they are not shared social metrics. Chat replies are textual quotes, not server-side reply relationships. Video uploads still use direct HTTPS MP4/WebM URLs.

Validation: `node tests/school-life.test.cjs`, `node tests/social-ui.test.cjs`, and browser interaction checks on a local preview with isolated demo fixtures. Checked mobile chat sending, quotes, search, draft restoration, dock hiding/restoration and customization, reel playback and switching. Production database writes were not used for testing.
