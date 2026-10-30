# Cleanup rules and profiles

Everything **Junk Files** cleans comes from rules. Each rule says where to look, what to spare, how risky the removal
is and what happens afterwards. The app shows that explanation next to every category (the ⓘ button), so you never
remove something without knowing why it's safe.

## In the app

Open **Rules & Profiles** in the sidebar:

- **Profiles** add rules for a kind of work. TidyMyMac marks the ones that match the tools found on your Mac.

  | Profile | Rules |
  | --- | --- |
  | Developer | `node_modules` folders installed more than 30 days ago, Gradle distributions, extracted Cargo sources, the local Maven repository, `~/.cache` |
  | Photographer | Lightroom Classic previews and Smart Previews, catalog backups older than 90 days |
  | Video editor | Final Cut Pro render files and optimized/proxy media, the Adobe media cache, the DaVinci Resolve render cache |

- **My Rules** lets you create your own rule with a form: pick folders in the Finder, choose what gets removed (their
  contents, the folders themselves, or items with a given name such as `node_modules` at any depth), add filters
  (extensions, age, names to keep) and a risk level. **Test Rule** shows what the rule would find right now, without
  removing anything.
- **Built-in Rules** can each be switched off.

## Safety limits

These apply to every rule, including yours:

- a rule can never remove `/`, `/System`, `/Library`, `/Applications`, `/Users`, your home folder, `~/Library`,
  `~/Documents`, `~/Desktop`, `~/Downloads`, `~/Pictures`, `~/Movies`, `~/Music`, iCloud Drive, or any folder that
  contains one of them;
- it can't sweep the whole contents of `/`, a system folder, your home folder or `~/Library`;
- a name search can't use a pattern made only of wildcards, such as `*`;
- your rules never force permanent deletion: they go through the Trash unless you turned on **Permanently delete junk
  files** in Settings.

Nothing is removed without being listed first: you still review every item before cleaning.

## Contributing a built-in rule or profile

Built-in rules live in [`Resources/Rules`](../Resources/Rules): `general.json` for everyone, and one file per
profile. A profile file starts with a `profile` block:

```json
{
  "profile": {
    "id": "photographer",
    "icon": "camera",
    "tint": "peach",
    "detect": ["~/Pictures/Lightroom", "/Applications/Capture One.app"],
    "title": { "en": "Photographer", "fr": "Photographe", "es": "Fotógrafo", "de": "Fotograf" },
    "detail": { "en": "Photo catalog previews and backups.", "fr": "…", "es": "…", "de": "…" }
  },
  "rules": [
    {
      "id": "photo-lightroom-previews",
      "icon": "photo.stack",
      "risk": "safe",
      "selectedByDefault": true,
      "target": "search",
      "names": ["*Previews.lrdata"],
      "exclude": ["*Smart Previews.lrdata"],
      "maxDepth": 4,
      "locations": ["~/Pictures"],
      "title": { "en": "Lightroom Classic previews", "fr": "…", "es": "…", "de": "…" },
      "detail": { "en": "Thumbnails and previews of Lightroom catalogs.", "fr": "…", "es": "…", "de": "…" },
      "afterRemoval": { "en": "Lightroom rebuilds them as you browse your photos…", "fr": "…", "es": "…", "de": "…" }
    }
  ]
}
```

| Field | Required | Meaning |
| --- | --- | --- |
| `id` | yes | Unique identifier across all rules. |
| `locations` | yes | Paths starting with `~/` (your home folder) or `/`. |
| `title`, `detail`, `afterRemoval` | yes | Name, one-line description, and what happens once the items are gone: are they recreated, and how to get them back. Translated into every language of the app. |
| `risk` | yes | `safe`: recreated automatically, nothing is lost. `review`: may contain things worth keeping. `irreversible`: deleted for good. |
| `icon` | yes | An [SF Symbols](https://developer.apple.com/sf-symbols/) name. |
| `selectedByDefault` | no (`false`) | Whether the category starts checked. Keep `review` rules unchecked. |
| `target` | no (`contents`) | `contents`: each item inside the locations. `location`: each location as a whole. `search`: items matching `names` at any depth up to `maxDepth`. |
| `names`, `maxDepth` | for `search` | Names to look for, with `*` and `?` wildcards, and how many folder levels to explore (default 4). The search doesn't enter `node_modules` or Photos and Music libraries. |
| `includeHidden` | no (`false`) | Include items whose name starts with a dot. |
| `extensions` | no | Only items with one of these extensions, for example `["dmg", "pkg"]`. |
| `exclude` | no | Names to leave alone, with wildcards. |
| `olderThanDays` | no | Only items not modified for this many days. |
| `permanent` | no | Skip the Trash (only used for emptying the Trash itself). |

In a profile block, `tint` is one of `mint`, `aqua`, `sky`, `lavender`, `rose`, `lime`, `peach`, `amber`, `coral`,
and `detect` lists paths whose presence suggests the profile.

Before opening a pull request:

1. run `./scripts/check-translations.sh`: it also checks the rules (required fields, risk level, unique ids,
   translations);
2. build the app and run `build/TidyMyMac.app/Contents/MacOS/TidyMyMac --list-rules -enabledRuleProfiles '(your-profile)'`
   to see what each rule finds on your Mac, without removing anything (add `--json` for a machine-readable plan);
3. in the pull request, explain what the rule removes, why it's safe, and how the data comes back.
