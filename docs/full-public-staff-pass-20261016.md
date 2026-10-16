# Complete source queues and teacher import

Import `20261016-staff-full` added **6,759 teachers from 444 additional school rosters**. The active public catalog now contains **65,371 teachers, 41,662 schools and 2,639 schools with teacher records**. The import and independent follow-up query report 0 unmatched schools, 0 ambiguous names, 0 links to existing people and 0 orphan teacher-school associations. The national teacher catalog remains incomplete.

The run completed **12,352 source attempts for 12,350 distinct licensed organizations**, rather than stopping at a small sample:

| Complete queue | Organizations attempted | Teacher candidates |
| --- | ---: | ---: |
| Remaining empty network/DNS checkpoints | 10,144 | 5,133 |
| Previously missing staff-page links | 762 | 9 |
| Previously unsupported staff formats | 1,247 | 984 |
| Certificate-chain checks using existing OS trust | 199 | 0 |

The last queue uses Node's documented [`--use-system-ca`](https://nodejs.org/api/cli.html#--use-system-ca) option. It installs no roots and keeps certificate validation enabled; hostname errors, expired certificates and access restrictions are not selected. Source collection refuses disabled TLS validation and rejects local/private/multicast destinations. Robots rules, source identity checks, request/page bounds and per-host scheduling remain active. There were no Auth, RLS, role, SMTP or SMS changes.

An additional checksum audit inspected 1,847 remaining format checkpoints. It recovered 634 teacher records from 125 school snapshots whose identity and staff HTML both matched their original response hashes. The original check times were retained. Missing identity proofs (75 schools), unavailable staff proofs (1) and unresolved formats (1,646) were held. No cached HTML was presented as a newly fetched page.

The readers now support explicitly associated personnel title/value fields, primary Gosweb employee cards and same-card staff carousel fields. Name and classroom-teacher role must belong to the same person. Qualification headings cannot supply a role; biography, contact, photo and other unrelated fields are ignored. A subject can come from a labeled discipline field or an explicitly published teaching position. Roster indexes outrank individual-profile carousel links. One explicitly labeled official site migration may be followed, with fresh organization and network validation; ambiguous destinations are held.

All 23,603 source checkpoints and earlier established rosters are retained. Current-license, organization-association, duplicate-roster and complete-snapshot guards produced 65,335 eligible source records across 2,638 schools. The 36 earlier public profiles explain the larger live total. One new candidate failed source-field validation. The delta has 6,759 new identities and no material updates to older identities. 2,134 new subjects remain unknown. Subject normalization affected 136 new fields by removing explicit qualification/publication-consent suffixes, trailing punctuation or repeated subject segments; no subjects were guessed and older identities were untouched. The derived checkpoints were canonicalized and re-prepared, producing the exact normalized content checksum.

Only the verified delta was privately staged, with count/hash checks before the existing SECURITY INVOKER import. The final canonical content SHA256 is `d65d159c4c3366679d35e46263eeabab6b77814a02637686c37a4cb1324d8d9a`; the staged delta SHA256 is `b96e4077c99d31ea9914971b38d5ed5819af0e1797fba0273c45b2bfc47cac38`. Raw HTML, source queues and personnel snapshots remain local and ignored. GitHub receives code, tests and aggregate reports only.

Tests cover source restrictions and migrations, canonical roster selection, same-person DOM associations, qualification/contact exclusion, tampered cache hashes, retained check dates, explicit subject suffix removal, immutable earlier identities, snapshot completeness and preservation of established rosters. The plain catalog search was separately published in PR49: no suggestions, no preference that can restore them, and no automatic query-history collection.

The completed queues do not constitute a census of all teachers in Russia. Unavailable sites, unresolved school identities, restricted pages, older/scanned documents, unsupported remaining formats and missing source information still limit coverage. Public source verification does not guarantee present employment.
