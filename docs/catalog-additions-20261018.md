# Verified school and teacher additions, 18 October 2026

The live catalog gained 181 schools and 679 teachers. It now contains 42,139 active schools and 79,550 active teachers; 3,413 schools have teacher profiles. Both imports used the existing private staging and apply functions. No schema, Auth, roles, SMS or SMTP changes were made.

## Schools

The complete official 17 October license archive was already downloaded and checked. This pass revisited its 732 unresolved school-address records. The additional parser recognizes explicit physical locality labels in compact addresses, alternative punctuation, rural/railway settlements and names beginning with ordinal numbers. It does not derive a locality from a school name, a postal code or a municipality alone. House numbers with letter suffixes, administrative qualifiers, conflicting locality labels and ambiguous nested addresses stay unresolved.

182 organization records met these rules and had no existing organization OGRN. Database preflight found one matching map profile; it was held for separate organization-identity review. The other 181 were inserted with exact official names, addresses, licenses and source references. No map profile was attached and no existing organization was updated. The remaining queue has 550 unresolved address records plus one held map match. Counts describe records needing review, not a count of all missing schools.

Source: [published license archive](https://islod.obrnadzor.gov.ru/opendata-lic/data-20261017-structure-20150421.zip), selected from the official published versions list. Archive SHA256: `bff7219977ac62fb7ee29801b848641dc3a0b5e96b790ce3a17de78baaa2d928`. Reviewed additions SHA256: `01ac019c738f19202b7b4cd50513136599d8f41466a7d64da015870d4c6e4e82`.

## Teachers

All 2,278 remaining empty format-review checkpoints were surveyed. Their 819 checksum-proven pages containing teacher labels identified four additional dedicated roster templates: compact staff cards, Oshkole name/position headings, position-photo cards and GS Team member popups. Only each template's explicit owned name, teaching position and discipline fields are read. Nested people, ambiguous fields, support roles, contacts, education, biographies and qualifications cannot supply a teaching role or subject.

47 current-license checkpoints matched the templates. Five lacked independently available organization proof and one produced no eligible staff; 41 rosters passed identity and original-page checksum validation. A second source audit re-read every new person's name, subject and provenance from 42 exact pages. The resulting 679 additions cover five regions. 179 subjects were not published and remain empty. Original source check dates are preserved: this is a re-read of proven snapshots, not a claim of newly fetched pages or current employment.

The canonical local source now has 79,514 records. All 78,835 earlier source records are identical. Cross-organization roster fingerprints were checked, and preflight found no existing teacher identity/import key for any new row. The import compared the prior 79,085 database records' names, school assignments and professional/source fields before and after; any change would have aborted the transaction. No existing teachers were linked, moved or edited.

New teacher payload SHA256: `78ebfc55a9eaa044e3f49361167ebaaf9e584e87ccf08b372d11fbc824a3f3e7`; canonical local source SHA256: `5a8d510cfee7a02043b941254a92481cecffff0110166c72229ed1baf39cbe25`.

## Verification and recovery

School run `20261018-compact-address-schools` applied once at 2026-10-18T14:31:09.400558Z. Staff run `20261018-staff-roster-templates` applied once at 2026-10-18T14:39:20.386673Z. Do not replay their staging or apply files. Private staged payloads retain audit provenance. Reviewed UTF-8 length-prefixed payload MD5 values were `eca7ff6419b5c377ea8c3b1ad7f9c015` and `cdac0514e1465fadffd867efe8385c7e`.

Post-import queries found zero orphan teachers, duplicate active OGRNs or mismatched imported names/subjects/addresses/provenance fields. Parser regression suites cover same-person association, nested/ambiguous cards, no qualification/contact inference, explicit localities and house-number rejection. Existing national-staff/cache/identity/snapshot tests pass.

Only code, tests and aggregate reports are published. Raw personnel snapshots, source pages, canonical archives and SQL staging remain under ignored `work/`. National school, campus and teacher coverage remains incomplete.
