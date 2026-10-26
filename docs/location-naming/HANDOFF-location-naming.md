# Wind Watch — handoff: user-editable location names

Scope: one change. Users must be able to set (and later change) the name of any location, because the reverse-geocoded names are often wrong for the spots sailors actually use. iPhone only; watch and web only *display* names and need no UI change. Everything else in `docs/design/DESIGN-HANDOFF.md` stands; this supersedes the "Naming" paragraph of its §8.3.

Renders: `reference/Phone-Location-Edit.png` (the sheet, new and existing), `reference/Phone-Location.png` (list with the ⓘ affordance). Sources: the two `.dc.html` files beside them — every size and colour is an inline value.

## 1. Data model

```
Location {
  id: UUID
  name: String            // user-owned, stored verbatim, 1–40 chars, trimmed
  suggestedName: String?  // what the geocoder said, kept for the chips; never shown as the title once `name` exists
  lat, lon: Double        // the pin, as placed
  cellLat, cellLon: Double // the HRRR grid cell the forecast actually comes from
  createdAt: Date
}
```

Rules:

- `name` is never re-geocoded, overwritten, or "corrected" by a refresh, a migration, or a re-pin. Once the user has typed it, it is theirs.
- Renaming never changes `lat/lon` or the cell. Moving the pin is a different action (not in this change).
- A new location starts with `name = suggestedName` (or `"Pinned location"` if the geocoder returns nothing) so Save is always possible.
- Duplicate names are allowed; the sheet *suggests* a ` 2` suffix, it does not block.
- Max 40 characters; trim whitespace; collapse internal runs of spaces. Empty after trim → Save disabled.

## 2. Where the sheet opens

| Trigger | Sheet title | Primary | Delete button |
|---|---|---|---|
| Long-press on the map (pin placed) | `New Location` | `Save` | no |
| Picking a search result | `New Location` | `Save` | no |
| ⓘ on a row in Locations | the location's current name | `Done` | yes, unless it is the last remaining location |

Present as a `.sheet` with `.presentationDetents([.large])`, drag indicator visible. `Cancel` on a new location discards the pin. `Cancel` on an existing one discards edits. Swipe-to-dismiss behaves as Cancel; if the name was changed, confirm with the standard "Discard Changes?" action sheet.

## 3. The sheet, top to bottom (402 pt wide, 16 pt insets, `card` fill #171C23, top corners 28)

1. Grabber (36×5, #3A424D), 10 pt from top.
2. Nav row, 44 pt: `Cancel` (17, `#4FA3D8`) · title (17 Semibold) · `Save`/`Done` (17 Bold, `#4FA3D8`; disabled → `ink.disabled` #5C6B7A).
3. `NAME` label (13 Semibold, `ink.secondary` #9AA4B1, +2 % tracking), 6 pt gap, then the field: 50 pt tall, `ground` fill #0B0E12, radius 12, 12 pt side padding, 1.5 pt inset ring `#4FA3D8` while focused, text 20 Semibold white, trailing clear button (28 pt circle, `#3A424D`, × in ground colour), `autocapitalization: .words`, `autocorrection: off`, `submitLabel: .done` (Return = Save when enabled).
   - On open for a **new** location: field is first responder with the whole suggestion **selected**, so typing replaces it.
   - On open for an **existing** location: field is not focused; tap to edit.
4. Helper line (13, `ink.secondary`, 18 pt leading): new → `Suggested from the map. Change it to what you call this spot; your name is never overwritten.` existing → `Renaming does not move the pin or change the forecast point.`
5. Map thumbnail, 150 pt tall, radius 12, non-interactive: the pin (`#4FA3D8`) and the 3 km HRRR cell as a dashed square (`#4FA3D8` at 60 %, fill 12 %, dash 3/2) with the caption `3 km HRRR cell` (10, secondary) beside it.
6. Two tiles (grid, 10 pt gap, `ground` fill, radius 10, 10/12 padding): `POSITION` → `48.100, −122.683` (tabular); `FORECAST POINT` → `HRRR cell 1.1 km NE` (distance and 8-point bearing from pin to cell centre; `at pin` if < 0.3 km).
7. `Suggestions:` row (13, secondary) with chips for the geocoder's other nearby names (up to 4; `ground` fill, radius 999, 6/10 padding, 13 `ink.body`). Tap a chip → it replaces the field text and focuses the field. Row hidden if the geocoder returned nothing.
8. Spacer.
9. Existing location only: `Delete Location` — full-width 50 pt, radius 12, fill `rgba(255,69,58,0.12)`, text 17 Semibold `#FF453A`. Taps → standard confirmation dialog `Delete "Marrowstone Pt"?` / `Delete` (destructive) / `Cancel`. Hidden when this is the last remaining location.

## 4. The list row (Locations screen)

Each row gains a trailing ⓘ: 22 pt circle-i glyph in `#4FA3D8`, 44×44 hit area, `accessibilityLabel: "Details for <name>"`. It is a separate control from the row's tap (which selects). In Edit mode the ⓘ is replaced by the minus button and drag handle, as already specified.

## 5. Propagation

- The hero header, trust line, peak chip, web page header and watch Settings/strip show `name` verbatim.
- Header truncation: single line, `.lineLimit(1)`, tail truncation; at default type ~22 characters fit on the main screen. (Open: wrap to two lines instead? Default is truncate.)
- Watch and complications read the name from the shared store on their next refresh; no push.
- The geocoder is called **once**, when the pin is placed. Never again for that location.

## 6. Geocoder

`CLGeocoder.reverseGeocodeLocation` (or MapKit's `MKReverseGeocodingRequest` on iOS 26). Build the suggestion in this order and stop at the first non-empty: `areasOfInterest.first` → `inlandWater` / `ocean` → `locality` → `subLocality` → `administrativeArea`. Collect the rest (deduplicated, excluding the chosen one) as the chips. Timeout 4 s; on failure the field opens empty with placeholder `Name this spot` and no chips — the user can still Save once they type.

## 7. Acceptance

- [ ] Long-press → sheet opens with the suggestion selected; typing replaces it; Save stores the typed name verbatim.
- [ ] ⓘ on any row opens the sheet with that location's name; Done saves; Cancel discards.
- [ ] Renaming does not change lat/lon or the HRRR cell.
- [ ] A refresh, app relaunch, or migration never changes a user-set name.
- [ ] Empty/whitespace name → Save disabled. 41+ characters → blocked at 40.
- [ ] Duplicate name → ` 2` suffix suggested, Save still allowed.
- [ ] Delete Location hidden for the last remaining location; confirmation dialog otherwise.
- [ ] New name appears on watch strip header and complication Smart Stack footer after next refresh.
- [ ] VoiceOver: field announces "Name, text field, Marrowstone Island"; chips announce as buttons; ⓘ announces "Details for Marrowstone Pt".
