# Themes and catalog moderation

Settings include 12 theme families with shape/interaction differences, day/night/system modes and reduced motion. Preferences remain on the device. The lower dock can still be configured or hidden.

Authenticated users submit school, teacher and director identities through `submit_catalog_request`. Anonymous Supabase accounts are supported; the explicit demo option only saves locally. Requests are private to their author and catalog moderators. Moderators use Settings → My requests → Moderation queue; membership is held in `catalog_moderators`, never in a client-editable profile field.

The server normalizes identity, deduplicates submissions, limits submissions to 10 per account per day and serializes publication per school. Identity publication creates no reviews or initial ratings. The former five-submission publication trigger is removed. This account limit is not a substitute for CAPTCHA or protection against many newly created anonymous accounts.

`verify-catalog` authenticates the caller and checks ownership. Automatic publication requires an already verified school's HTTPS source, a URL on that same origin and a full name plus subject/title in the same HTML table row. Redirects and private-network addresses are rejected; response size and request duration are bounded. Missing/unavailable/ambiguous sources go to manual review. New schools require manual review. Existing unverified seed entries are not automatically trusted. Moderators must verify the organization, full name, subject/title and official source before approval; director replacement requires manual approval. The audit table stores every publication/moderation decision.

Database migrations required: director ratings, school spaces/polls, repaired profile signup, catalog requests, private director review RPC. Deploy `supabase/functions/verify-catalog/index.ts` with JWT verification enabled. No service key belongs in the frontend.

Run `npm test`. SQL integration tests use PGlite: install `@electric-sql/pglite` in a test workspace or set `PGLITE_PATH` to its absolute module path, then run `npm run test:catalog-sql`. Tests cover RLS, moderator-only publication, repeated submissions, required fields and zero fabricated ratings.

## Building a reliable database

Start with a pilot region: import school organizations into a staging queue, preserve source and collection date, normalize identifiers/location/name, resolve duplicates, review and publish. Municipal open data may be a starting point, but check its publication/update date. Add teacher/director professional information from confirmed school sites afterwards. Preserve historic employment separately when designing bulk imports; the current director table stores the current identity only. Periodically recheck sources and accept corrections. This release does not bulk-import a national database.
