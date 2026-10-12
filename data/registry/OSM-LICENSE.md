# OpenStreetMap directory extract

`20261012-osm-schools.json` is an adapted OpenStreetMap database extract, © OpenStreetMap contributors, made available under the [Open Database License 1.0](https://opendatacommons.org/licenses/odbl/1-0/). [Copyright and attribution](https://www.openstreetmap.org/copyright).

The extract adds Russian administrative region names using OSM/Wambacher boundaries distributed by [geoBoundaries, RUS ADM1 (2017)](https://www.geoboundaries.org/api/current/gbOpen/RUS/ADM1/), also ODbL-1.0. It filters for explicit complete addresses and removes conservative duplicate candidates against a separate license-register directory. The resulting adapted extract is distributed here in full under ODbL-1.0. The report explains exclusions and limitations. This notice covers the map-derived database content, not application source code or user reviews.

Public source: Overpass API, `area["ISO3166-1"="RU"][admin_level=2]; nwr[amenity=school](area); out tags center;`, retrieved 2026-10-12. A map record does not verify educational license status, staff or continuing operation.
