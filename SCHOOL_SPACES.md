# School spaces redesign

The home screen now links to teacher ratings, director ratings, school profiles, school atmosphere (chat/reels), voting and useful articles. The old regional chat is hidden; old `#chat` links open the director picker. Existing regional chat data is retained.

## Shared Supabase data

Apply `supabase/migrations/20261007_school_spaces_and_polls.sql` in the Supabase SQL Editor after the existing school and director rating migrations. It creates:

- `school_classes`: manually created classes per school, with a unique name such as `8А` or `10Б`;
- `school_polls`: whole-school or class-specific polls with 2–8 choices and optional deadlines;
- `school_poll_votes`: one vote per authenticated account and poll; changing a choice replaces the vote;
- `school_messages`: school-scoped chat with pseudonymous aliases and a three-second sending cooldown;
- `school_reels`: direct HTTPS MP4/WebM links and captions.

The `cast_school_vote` RPC validates the deadline and option on the server. `school_poll_results` returns totals and the caller's selected choice, without exposing voters' account IDs. Chat reads expose only aliases and message data. The frontend refreshes the chat feed every ten seconds without replacing the draft.

Class selection organizes polls; it does not verify class membership or restrict voting to enrolled students. Classes are created manually by authenticated users. School membership verification and class administration can be added separately.

The site's existing demo login uses local storage. All new creation/voting/chat actions in demo mode stay on that device, regardless of whether the migration has been applied. Shared publishing requires the existing real Supabase authentication to work; this release does not repair its previously documented signup issue.

Reels currently accept a direct video URL. Uploading, transcoding and hosting videos are not included.

## Verification

Run `node tests/school-life.test.cjs` for navigation entries, class validation and duplicates, poll creation, changed/closed votes, school data isolation, school chat and URL validation. The tests use the actual module with a small DOM/storage harness. Browser rendering and a live database are not covered by that harness.
