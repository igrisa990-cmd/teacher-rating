# Plain catalog search

Suggestions have been removed from the catalog, including rendering, suggestion keyboard handlers, the settings toggle and CSS. Previous browser preferences cannot enable them. The field is a native search input; live directory results, Enter/Find, region selection, case/е/ё matching, profile links and school scope remain available.

New query-history collection has stopped. Existing browser-local queries are not displayed; Search settings offer explicit removal of the old history. The user's region, theme, account preferences and authentication are unchanged.

Tests cover ordinary search with both prior suggestion-preference values, highlighting, result counts, no new history collection, legacy-history removal and school selection. Browser verification confirms the public database returns a recently imported teacher, the input has no suggestion controls and region selection opens directly, with no horizontal overflow at mobile width.
