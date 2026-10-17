# Organizations, school centers and campuses

Publication status: prepared and locally tested, **not applied to production**. Supabase reads work, but both `execute_sql` DDL and `apply_migration` return `Invalid or expired requestState`. The CLI has no access token; the dashboard requires sign-in. Restore the existing connection before applying. Do not replay completed teacher imports.

The former model had one address per organization. That cannot represent Moscow school 548 or Yaroslavl's reorganized educational complexes. The new child records distinguish school/branch/preschool locations and unclassified educational places, retain source and identity hashes, and keep every teacher/review on its existing organization. An organization's legal address is not automatically a campus.

Verified examples:

- School 548, OGRN 1037739570384: four school campuses in Moscow, two school/branch locations in Moscow Oblast, and four preschool locations. The school's published address list was joined by `unique_address_id` to the platform's organization API with the exact OGRN. The broader 15-address organization inventory was not treated as 15 current school campuses.
- School 99, Yaroslavl: center of complex 6 “Квант”, OGRN 1027600512532, Труфанова, 25а. School 58 is another center at Труфанова, 21а. The current official page links the exact active license record.

Sources: [548 published locations](https://cou548.mskobr.ru/api/get/addresses.json), [548 organization identity](https://api-app.mskobr.ru/api/v3/organization/13866), [complex 6 official information](https://ok6-yar.edu.yar.ru/svedeniya_ob_obrazovatelnoy_organizatsii/osnovnie_svedeniya/index.html), [Yaroslavl department overview](https://yar-edudep.ru/obwee_obrazovanie/).

The local audit traversed all 23,603 collection checkpoints and 8,446 available pages. The reviewed payload contains 1,742 distinct addresses for 321 active, uniquely matched organizations. Moscow's published lists contributed 1,383 locations from 155 organizations; the broader 162-organization inventory is not a publication input. Every source page must independently prove its organization. Network partners, practice sites, ambiguous multi-address strings and shared cross-organization claims are held. Unknown building types remain unknown.

All 3,930 active profiles without organization OGRNs were compared with verified campus evidence. 34 duplicate candidates have an exact street/building and explicit school number, with the reported school 548 case individually reviewed because its OSM address omitted corpus 2. One clearly unrelated barber-training profile is separately held for soft correction. All 35 profiles currently have zero references in all 12 non-cache foreign-key tables. The correction function rechecks **all** current foreign keys under row locks, stores a private before-image, archives without deletion, and creates a canonical-link alias for duplicates. A referenced profile aborts the transaction.

Coverage is incomplete. Of 39,661 active general-program license records in the 14 October source snapshot, 1,990 do not match the active catalog: 845 are outside the school organization classifier, 83 have no valid organization OGRN, and 1,062 need address review. These are records, not a claim that all 1,990 are missing schools. A conservative additional locality parser recognizes explicit prefix/suffix settlement names and reversed republic names. Its output stays in the local review queue until source and status checks finish. No national campus census or complete teacher coverage is claimed.

## Deployment and recovery

Apply the generated schema migration only after reconnecting Supabase. New public tables are read-only for anonymous/authenticated users, follow parent-school RLS, and expose no personnel/contact fields. Staging, before-images and privileged import/correction functions remain private. Search retains the existing caller RLS and request bounds, adds campus names/addresses to the spelling cache and respects explicitly proven campus regions. No Auth, SMTP, SMS or moderator changes are included.

Generate a local staging package with `scripts/stage-school-campus-import.cjs`; use the reviewed input and the current teacher mapping digest. Register the run, stage every numbered SQL file, check counts/checksum, then execute its apply file once. The import checks the teacher mapping digest before and after, and refuses a replay. Current baseline: 79,085 total teacher rows, digest `6ffe025c5d3d4b67d1751ebcd1f903ab`. Reviewed payload SHA256: `c0193b8617d41c76f0f248dd116e4f9745e65f3f89da49d889bc98a4ddc0629a`.

Keep raw pages, API responses, source personnel snapshots, staging SQL and school before-images under ignored `work/`. Publish only code, tests and aggregate reports. After applying, verify anonymous search for 99/Труфанова, 548 in Moscow/Moscow Oblast, campus type counts, duplicate redirects, teacher mapping invariants, advisors, and the mobile layout before merging the release.

Validation: parser identity/address separation and ambiguity cases; exact license-link and legal identity proofs; full search migration chain in PGlite; prefix vocabulary and branch-region search; parent RLS propagation; public write denial; replay/integrity checks; all-FK soft-correction refusal; safe/escaped campus UI and alias normalization; existing catalog/account/social/map regression suites.
