# Verified catalog expansion — 20–21 October 2026

The public website catalog now contains **235,021 active teacher profiles**, **42,237 active schools** and **8,970 schools with teachers**. The completed 21 October imports added **11,194 teachers**, following 69,346 additions on 20 October. The net increase since the 19 October result is **80,540**. National personnel coverage remains incomplete.

| Completed source group | New teachers |
| --- | ---: |
| Fresh school documents | 539 |
| Anonymous official Moscow school-portal staff listings | 31,279 |
| Two newly licensed school profiles | 35 |
| Government-platform school frontier | 47,914 |
| Staff of recently added licensed school organizations | 773 |
| Total | 80,540 |

The government-platform frontier finished all 2,342 source checkpoints on 20 October. Its recorded outcomes include 1,828 prepared sources, 370 partial lists, 94 formats needing review, 13 non-public addresses, 14 HTTP 404 responses and 23 aborted requests. All 2,342 checkpoints were subsequently accounted for in 15 disjoint cached-review cohorts, including access and format holds. A completed checkpoint does not establish a complete staff roster. Collection used one government-platform queue, at least 500 ms between global requests, one worker per host, a failure circuit, bounded pages and responses, destination-specific robots checks, public-address validation and TLS checks.

On 21 October the final 508 checkpoints were independently re-read. The accepted 11,251 source rows covered 487 licensed school organizations and 1,727 exact source responses. Removing 830 existing canonical identities yielded 10,421 new teachers across 463 schools. Eight incomplete names, five ambiguous name merges and identity/access holds remained excluded. Whole-roster exact and name-only comparisons against the committed catalog found no copied lists assigned to a second organization.

A separate 35-organization queue then finished normally, with 27 prepared lists, six partial lists, one non-public address and one format hold. A strict cached re-read and independent byte/field audit verified 773 complete names from 33 organizations against 126 source pages. All 773 were new. Thirty-two have no explicitly published subject; those fields remain empty. Teachers are linked to their proven school organization without an inferred campus assignment.

The latest published [official license archive](https://islod.obrnadzor.gov.ru/opendata-lic/data-20261020-structure-20150421.zip) was checked and downloaded on 21 October. Archive SHA256: `3670d71bb5df632c90b658b5f468fec0f5fb43c71f83baec5e886de60e3b78bc`. Streaming extraction inspected all 307,610 licenses and retained 39,655 active main-organization general-education license records, representing 39,531 organizations. The extracted input SHA256 is `f163fdffd04effa0e8a3ed8963016cb7782d7d9c7973f1f5d379894270b0fcaf`. All 508 remaining frontier organizations and all 35 new-parent organizations passed the current license and expiry check. The two new imports were audited against this input; earlier 20 October cohorts retain their original 19 October archive proof and actual source times.

A separate historical review contains 85 catalog organizations absent from both the 19 and 20 October active general-education extracts. The two extracts have identical eligible organization sets, so these are pre-existing review cases. Historical identities and dated evidence remain available pending program/identity review; these organizations supplied none of the new 21 October imports.

Across the completed 20–21 October expansion, 65 applied teacher runs matched every staged source row. Postchecks found zero source-field mismatches, imported artificial ratings/reviews, orphan teachers or duplicate active school organization numbers. New-only transactions validate staged counts, unique identities and length-prefixed payload checksums, prevent replay, and protect the complete previous UUID set and the same eight professional fields. A timed-out large preservation check was confirmed rolled back before applying smaller batches with the same guards. No database schema, authentication configuration or access policy changed.

School reconciliation produced 38 net additional active school profiles: 39 creations and one backed-up duplicate redirected to its canonical organization. Two existing map profiles retained their IDs when matched to exact licensed identities. Eight explicitly published main-program teaching addresses were added across three organizations. Distinct neighboring organizations, legal addresses, teaching places and teacher-to-school links were reviewed separately. The corresponding collector, address/subject parser and campus-block improvements were published in PRs #63 and #64; their full project suite passed after the code changes.

There are 235,235 total database teacher rows, including 214 retained rows on archived schools. The local canonical source contains 234,985 identities across 8,969 organizations; 36 separately maintained active profiles explain its difference from the public count. All preceding canonical objects remain unchanged. Canonical raw SHA256: `0ae8ac135afedd6575fff80a1c85ba9cebafe5a8e1cc12679e39c915eabc700a`; gzip SHA256: `d306b1c504878a5909bb6f0204278471e1f1a439f245dca677382de8e9f12242`.

Personnel are published in the website catalog only. Raw staff archives, exact page responses, identity proofs, backups and staging SQL remain in ignored local storage. This report contains aggregate results. Partial, unpublished, inaccessible and unsupported sources still require review, and a professional listing does not guarantee present employment.
