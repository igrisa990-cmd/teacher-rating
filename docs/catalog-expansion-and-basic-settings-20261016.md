# Catalog expansion and basic settings — October 16, 2026

Import `20261016-staff-expanded` inserted **1,464 teachers**. The active site catalog now has **56,419 teachers, 41,662 schools and 2,123 schools with teacher profiles**. The import reports 0 unmatched schools, 0 ambiguous names and 0 links to existing people; a subsequent database query found 0 orphan teacher-school associations. No ratings or private contact information were imported.

## Sources and remaining coverage

A completed retry covered all 6,829 registry-linked websites previously held for organization identity review. The identity matcher now also recognizes the explicitly written «Основной государственный регистрационный номер», requiring the same valid 13-digit OGRN as the registry seed. A conflicting published OGRN still blocks the fallback based on legal name/address. This finite pass obtained 1,208 classroom-teacher records from 47 newly confirmed websites; 6,408 websites still need identity review. Network, TLS and access failures remain held. No restrictions or certificate checks are bypassed.

The document pass additionally attempted 19 XLS candidates and obtained 17. The read-only `xlrd` 2.0.2 wheel was verified with SHA256 `ea762c3d29f4cca48d82df517b6d89fbce4db3107f9d78713e48cd321d5c9aa9` and loaded from an ignored project-local directory. To reproduce: install with `python -m pip install --only-binary=:all: --require-hashes --target work/xls-runtime -r scripts/legacy-xls-requirements.txt`, then include that directory in `PYTHONPATH`. No spreadsheet application, formulas or macros execute. Sheet count and dimensions remain bounded.

Header matching accepts explicit position headers such as «Наименование должности в соответствии со штатным расписанием», while rejecting qualification-category columns that merely mention a position. A combined position/subject column does not become a guessed subject. Previously held table formats were retried; the complete document checkpoint set now contains 1,116 parsed documents, 167 accepted documents and 2,490 deduplicated observations across 110 organizations. Current academic-year, same-row classroom role, source hash and organization identity checks remain in force. The license and existing-record guards yield **256 new eligible profiles** from this document expansion.

The separate combined inventory retains all 23,603 original school checkpoints. Retry overlays can replace only previously unresolved identities with no established roster. All established HTML/document rosters are preserved byte-for-byte, with their original check times. After current-license and duplicate-roster validation, the full snapshot has 56,383 eligible teachers across 2,122 schools; 36 earlier public profiles account for the larger site total. Only the 1,464 new records were staged. Both diff and staging reject incomplete snapshots. Personnel archives and raw source documents stay local and ignored; GitHub receives code and aggregate reports.

This remains an incomplete national teacher catalog. Inaccessible sites, identity ambiguities, old documents, scanned pages and legacy DOC files require further work. Public source verification is not a guarantee of present employment. The existing school-license reconciliation from the official 20261015 snapshot remains unchanged.

## Search and settings

The settings overview shows current values for Appearance, Region, Navigation, Search and Account, with one focused page per section and a Back control. A quick color-mode selector supports light, dark, system and the theme default. Existing themes, account security, region preferences, dock customization, automatic account saving and retry remain available. Hiding the dock retains a Settings access button. The overview no longer renders the full theme grid or a redundant sidebar.

The catalog input offers current public profile matches and locally remembered submitted queries. Arrow keys and Enter select a profile; Escape dismisses suggestions. Ordinary Enter submits a query. Result names highlight matching letters, including equivalent е/ё spelling. Result summaries count displayed rows correctly after pagination. Existing case-insensitive prefixes, typo fallback, region scoping, request cancellation and caller RLS remain unchanged; no new search RPC or privileged helper was introduced.

History stores up to eight submitted queries in this browser for up to 30 days, with expiry cleanup, a clear action and an opt-out that removes stored queries. It is not synced to the account or transmitted as history. Suggestions reuse the current result page and add no network requests.

## Validation

JavaScript tests cover history normalization/expiry, malformed storage, opt-out deletion, escaped suggestions, keyboard profile selection, highlighted е/ё matches, pagination summaries, settings navigation and rendering without a theme selector. Existing directory, region, account, provenance and dock tests pass. Import tests reject incomplete retry inventories and replacement of established rosters. Python tests cover explicit header selection, qualification-column rejection, same-row roles and date isolation.

Browser checks covered 390px and 1280px layouts, direct keyboard opening of a real teacher profile, color-mode switching, nested Appearance/Search/Navigation settings, history opt-out, and access to Settings while the dock is hidden. Registration, SMTP, SMS and account roles were not changed. All finite collection and parsing passes completed.
