# Settings, forgiving search and verified catalog expansion

## Interface

Settings now occupy the fixed last item of the bottom navigation on desktop and mobile. The overview opens Appearance, Panel, Region and Account as ordinary nested pages with a Back control. The old palette and panel settings controls are removed from the header. Saved dock choices are preserved; a fresh/default dock contains Home, Teachers, Schools and Settings. Hiding the dock retains a Settings restore button.

The catalog has one search input with a nearby region picker; the separate locality input is removed. Russian case, whitespace, punctuation and е/ё normalize consistently. Alphabetic terms use word prefixes, so `фад` finds `Фадеева`. School numbers remain exact. If there are no ordinary matches, up to four close spellings per word are tried; all query terms and region constraints still apply. Approximate cards say «Похожее совпадение». This supports common typos, not arbitrary semantic questions or every possible misspelling.

Opening a school's staff uses its ID and paginated teacher records, preserving separation between schools with the same name. Typing another query leaves this school-specific scope. New input cancels obsolete HTTP requests; stale replies cannot replace current results.

## Search access and performance

`search_catalog` remains SECURITY INVOKER. A compact school-document cache has caller RLS that checks visibility in the source `schools` table. Its maintenance trigger only copies authorized source writes; it exposes no privileged read helper. The cache and teachers use equivalent non-correlated visible-school ID sets, allowing a single hashed visibility check. Additional source-school RLS still propagates to both.

The public spelling vocabulary contains words, without record IDs, school associations or contacts. Clients have SELECT only. The schema is not added to the exposed REST schemas. The spelling extension initializes only if the ordinary search is empty. The RPC alone has an 8-second timeout, without changing role-wide timeouts. Warm public REST probes were approximately 0.3–0.9 seconds; one cold full-country request took 6.6 seconds, and a six-request stress probe exceeded the earlier 5-second limit. This free instance has variable latency; these checks do not establish production concurrency capacity.

## Catalog counts and source verification

After import run `20261015-staff-cards`, the public active catalog contains **41,661 schools, 52,836 teachers, and 1,967 schools with teacher records**. This run inserted **19,698 teachers from 390 schools**, with zero unmatched school associations, ambiguous names or links to existing people. The parser handles roster cards only when one linked full name and an explicit classroom-teacher role appear together. Missing subjects remain unknown; other roles and private contact fields are excluded.

The official [license version index](https://islod.obrnadzor.gov.ru/opendata_licenses_files/saved_resource.html) was rechecked on October 15 UTC (October 16 Moscow time for final checks). The latest listed snapshot was `20261014`. The [full archive](https://islod.obrnadzor.gov.ru/opendata-lic/data-20261014-structure-20150421.zip) contains 307,529 licenses; the general-education/current-license filter yields 37,642 distinct organizations. Every eligible OGRN is present in an active school record: missing 0, duplicate active organization OGRNs 0. The sorted local and database key sets both have MD5 `c6d488a15291abe21515286014ed4c53`. This establishes organization coverage for this snapshot, not completeness of every building, branch or map node. The catalog also contains 3,930 map records without an organization OGRN. No orphan teacher-school associations were found.

The finite registry-linked website inventory has 23,603 checkpoints. This pass retried 1,864 identity-confirmed HTML sources, completing all of them; 390 yielded the new rosters. Earlier verified checkpoints retain their original check dates. The prepared combined snapshot has 52,800 teachers; 36 earlier public records account for the catalog total of 52,836.

The national teacher base is **not complete**. Among 1,365 remaining identity-confirmed format-review sites, a cached-HTML audit found 1,598 same-origin staff-document links across 594 schools: 409 current-year candidates, 239 explicitly older documents, 889 without a verified date, and 61 legacy binary Word documents. Links alone are not approved personnel records. Document dates, table layout and name/teaching-role association require validation before import. Other checkpoints remain inaccessible or fail organization/source checks; robots restrictions, access challenges, TLS errors and private addresses are not bypassed. No collection process is left running after this release.

Personnel archives, raw HTML and documents stay in ignored local work/data files. Only code, SQL and aggregate reports are committed. Publication is the site catalog, as requested; no downloadable personnel archive is published to GitHub.

## Validation

- Existing catalog, accounts, themes, region onboarding, import/provenance and new school-roster/cancellation tests pass. No live registration, SMTP or SMS delivery was performed.
- The full SQL migration chain passes in pinned PGlite 0.5.10 with pg_trgm. Production SQL fixtures run inside BEGIN/ROLLBACK and cover case, prefix, punctuation, е/ё, repeated/transposed letters, all terms, type, region, hidden archived schools and stable pagination. Final fixture counts are zero.
- The local SQL harness additionally hides an otherwise active source school through a new restrictive policy and verifies that cache, teachers and search expose none of its records; cache writes by anon are denied.
- Desktop and 390×844 mobile settings, nested Back navigation, dock hide/restore, prefix and typo result cards were checked in the browser. The public REST API was checked with the public client configuration.
- Supabase advisors show no findings for the new `catalog_spelling` objects or `search_catalog`; existing unrelated auth/trigger advisories remain outside this change.

To reproduce optional SQL checks, install the pinned test runtime in an ignored work directory with `npm install --prefix work/sql-test-runtime --ignore-scripts --no-save @electric-sql/pglite@0.5.10`, set `PGLITE_PATH` to the absolute `work/sql-test-runtime/node_modules/@electric-sql/pglite` path, and run `node tests/fuzzy-catalog-sql.cjs`.
