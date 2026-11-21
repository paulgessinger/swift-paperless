# Localization

The app ships in English (source), Danish, German, French, Italian, Dutch,
Polish and Turkish.

## Catalogs

- `AppShared/Sources/AppShared/Resources/Localization/*.xcstrings`: all UI
  strings. Swift code uses generated symbols, one accessor per catalog, e.g.
  `Text(.settings(.offlineSyncTitle))`.
- `swift-paperless/Localization/AppShortcuts.xcstrings` and `Intents.xcstrings`:
  App Intents and Siri phrases. The system looks these up by key, so no Swift
  code references them.

## Workflow

Crowdin is where translators work. The `Crowdin synchronization` workflow runs
every 12 hours and on pushes to `main` that touch a catalog. It uploads the
catalogs and opens a `chore: Update localization` PR with Crowdin's result.

- Translations can also be edited in the catalogs directly; the sync keeps
  them.
- Crowdin fills untranslated entries with the English text and
  `"state" : "new"`. Treat `new` as untranslated, even though a value is
  present.
- When a translation is the same as the English (`Scan`, `%lld dpi`), set its
  state to `translated` so it no longer counts as missing.
- Edit catalogs with a tool that keeps Xcode's formatting: two-space indent and
  `"key" : value`. Python's
  `json.dumps(data, indent=2, separators=(",", " : "), ensure_ascii=False)`
  plus a trailing newline reproduces it exactly.

## Adding source strings

- Give every key a `comment` that says where the string appears and what any
  placeholder holds. Translators see only the string and the comment.
- State length limits in the comment, e.g. "keep it to about 12 characters"
  for swipe actions and badges.
- Use positional placeholders (`%1$@`, `%2$lld`) when a string has more than
  one, so translations can reorder them.
- When you change the meaning of an English string, rename the key or clear
  its translations. Translations marked `translated` are not flagged for
  review when only the English changes.

## Checks

`just lint-strings` lists `AppShared` keys that no Swift code references, and
`just lint-strings --remove` deletes them. It is not part of `just lint`; run
it when cleaning up.

## Tone

| Language | Address |
|---|---|
| Danish | du |
| German | du (lowercase) |
| French | vous |
| Italian | tu |
| Dutch | je |
| Polish | informal, with *Twój/Twoje* capitalized |
| Turkish | siz |

## Glossary

| English | da | de | fr | it | nl | pl | tr |
|---|---|---|---|---|---|---|---|
| Document | Dokument | Dokument | Document | Documento | Document | Dokument | Doküman |
| Tag | Etiket | Tag | Tag | Etichetta | Label | Tag | Etiket |
| Correspondent | Korrespondent | Korrespondent | Correspondant | Corrispondente | Correspondent | Korespondent | Muhatap |
| Document type | Dokumenttype | Dokumenttyp | Type de document | Tipologia di documento | Documentsoort | Typ dokumentu | Doküman türü |
| Storage path | Lagersti | Speicherpfad | Chemin de stockage | Percorso di archiviazione | Opslaglocatie | Ścieżka składowania | Depolama dizini |
| Custom fields | Brugerdefinerede felter | Benutzerdefinierte Felder | Champs personnalisés | Campi personalizzati | Aangepaste velden | Pola dodatkowe | Özel alanlar |
| Saved view | Gemt visning | Gespeicherte Ansicht | Vue enregistrée | Vista salvata | Opgeslagen weergave | Zapisany widok | Kayıtlı görünüm |
| Owner | Ejer | Eigentümer | Propriétaire | Proprietario | Eigenaar | Właściciel | Sahibi |
| Inbox | Indbakke | Posteingang | Boîte de réception | Posta in arrivo | Inbox | Skrzynka odbiorcza | Gelen kutusu |
| Trash | Papirkurv | Papierkorb | Corbeille | Cestino | Prullenbak | Kosz | Çöp kutusu |
| Upload (verb) | uploade | hochladen | envoyer | caricare | uploaden | przesłać | yüklemek |
| Download (verb) | hente | herunterladen | télécharger | scaricare | downloaden | pobrać | indirmek |
| Keep offline | Behold offline | Offline behalten | Conserver hors ligne | Mantieni offline | Offline bewaren | Zachowaj offline | Çevrimdışı tut |
| Sync | synkronisere | synchronisieren | synchroniser | sincronizzare | synchroniseren | synchronizować | eşitlemek |
| Library | Bibliotek | Bibliothek | Bibliothèque | Libreria | Bibliotheek | Biblioteka | Kitaplık |
| Thumbnail | Miniature | Vorschaubild | Miniature | Miniatura | Miniatuur | Miniatura | Küçük resim |

Avoid "archive" for anything other than Paperless-ngx's archived document
version, which already has that meaning in the app.
