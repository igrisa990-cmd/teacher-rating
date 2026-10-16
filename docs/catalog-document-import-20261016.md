# Verified document rosters and current school licenses

The site catalog now contains **41,662 school profiles and 54,955 teachers across 2,071 schools**. Import `20261016-staff-documents` added **2,119 teachers from 104 schools**, with zero unmatched schools, ambiguous names or links to existing people. No ratings, contacts, degrees, photos or biographies were imported. The preceding settings/search release remains deployed.

## School verification

The official [version index](https://islod.obrnadzor.gov.ru/opendata_licenses_files/saved_resource.html) was checked again on October 16. Its latest listed [archive is 20261015](https://islod.obrnadzor.gov.ru/opendata-lic/data-20261015-structure-20150421.zip), 93,474,611 bytes, SHA256 `43fbf1aaea5f2fdcd4242cceb4715ebf06158a539233b2b787d9f63ee5339fec`.

All 307,567 licenses were traversed: 136,205 active, 39,661 with current main-organization general-education programs. Organization/address validation yields 37,637 eligible organizations. Their sorted local key set and the corresponding database set share MD5 `6b9cb48865e45b48678c9fbcde220c9a`; missing active school profiles: **0**. The import added **1 school** and refreshed **76** existing records. The larger public profile count includes map records and historical organizations; this is not proof that every building or branch is separately represented.

Six previously eligible organizations have no current general-education license in this snapshot. A second full-archive pass inspected all **14** license records belonging to them and confirmed that every one explicitly says «Не действует». This conclusion is based on source statuses, rather than absence from a filtered list. Their profiles, IDs, reviews and archive state are preserved, with a visible «Лицензия не действует» badge and dated explanation.

The nullable license-status fields require a checked timestamp and an official snapshot URL. A private SECURITY INVOKER trigger copies an already-authorized incoming active-license source update into the status fields. It reads no source table and adds no client permissions. A newer inactive check cannot be erased by replaying an older active snapshot. A later valid source can restore active status while preserving archive state. The existing importer and RLS remain unchanged.

## Document extraction

The finite cached-HTML document inventory has 1,598 staff links. This pass attempted **1,279 PDF, DOCX and XLSX candidates** with a current year or an unverified date, including previously downloaded checkpoints. **1,099 documents** were obtained and parsed. Requests are sequential within an origin, respect robots/crawl delay and public DNS, validate TLS, pin resolved addresses, stop on access challenges and reject cross-origin redirects. Files are limited to 5 MB; OOXML expansion, worksheets and PDF page counts are bounded.

An official school's organization identity was fetched and verified again before downloading its documents. The parser accepts explicit full-name and position columns, including split surname/name/patronymic columns. A classroom-teacher role must occur in the same row. Subjects come only from an explicit subject column; 649 of the new records have no published subject and remain unknown. Repeated names within the same organization are merged before the existing license and duplicate-roster checks.

Academic-year dates are checked independently of download time and upload-folder dates. A 2025–2026 academic roster is held as older than the current year. For a filename without a date, the roster heading must supply a current year; a 2026 training course in an employee's qualifications cannot establish roster currency. Scanned pages are held for review even if an OCR text layer exists. Unmapped, split or ambiguous rows are not reconstructed by guessing. Partial tables can add verified people without establishing that the entire faculty has been captured.

The 1,099 parsed documents produced 2,530 row observations in 160 accepted documents, deduplicated to 2,119 people. Other outcomes: 760 dates require review, 140 table formats require review, 29 scanned documents, 9 page-limit cases and 1 oversized worksheet. Access/format exclusions and older/legacy DOC/XLS sources remain in the local review inventory. The national teacher database is **still incomplete**.

The separate combined inventory retains all 23,603 original school checkpoints and their original HTML check times. It now prepares 54,919 eligible teacher records; 36 earlier public records account for the site total of 54,955. The full inventory must finish before diff/staging: incomplete reports are rejected by both helpers. Only the 2,119 new records were staged and imported. Personnel/source archives and raw documents stay in ignored local directories. GitHub receives code and aggregate reports only.

## Validation

- Python tests cover full and split names, explicit role columns, role isolation, private-field rejection, legitimate health-related subject names, academic years and qualification-date isolation. Representative PDF layouts were rendered and compared with extraction.
- SQL checks in pinned PGlite 0.5.10 cover license proof, idempotence, rejection of older-source status rollback, later active-license recovery and preservation of archived profiles.
- JavaScript tests cover source badges and rejection of invalid status-source URLs/dates, catalog provenance, existing staff parsing and snapshot completeness guards.
- Public REST search found a newly imported teacher by full name; prefix search still returned results. A cold prefix request took 5.9 seconds and the new-name query 0.5 seconds on the free instance. Existing bounded search latency limitations still apply.
- Database import reports show 0 ambiguous names, 0 unmatched schools and 0 orphan teacher-school associations. Database size after this import was 480,652,435 bytes. Supabase advisors produced no findings for the new status trigger or the search cache.
- No registration, email delivery, SMS settings or account roles were changed. All finite collection/parser processes finished; no background collector is left running.
