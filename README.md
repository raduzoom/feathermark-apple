# FeatherMark for Apple platforms

The Mac app and, from Phase 12, the iPhone and iPad app, with the Swift packages both use. FeatherMark is a free, native, lightweight Markdown note app for macOS 15 and later (iOS and iPadOS 18 to come). Notes stay on your Mac in a local library and export to a plain Markdown folder at any time. Optional Feather Cloud sync is end-to-end encrypted.

## Running

Open the generated project in Xcode and run the FeatherNote scheme, or build from the command line (below). The library lives in `~/Library/Application Support/FeatherMark/`.

## Building

Needs Xcode and [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```bash
xcodegen generate && xcodebuild test -project FeatherNote.xcodeproj -scheme FeatherNote -destination 'platform=macOS'
```

## Packages

Shared by the Mac app and the iPhone and iPad app (macOS 15 and iOS 18) unless noted:

- `FeatherCore`: the local library. SQLite with full-text search, notebooks, tags, Trash, attachments, the change log sync reads, and export to and import from a Markdown folder. `fncore` is its command-line harness.
- `FeatherCrypto`: end-to-end encryption (keys, envelopes, Argon2id) and the Keychain stores.
- `FeatherSync`: the Feather Cloud client and sync engine.
- `FeatherEditor`: the live-preview Markdown editor. `FeatherEditorCore` is shared; the AppKit view is macOS only.
- `FeatherAppModel`: the app's behaviour (`AppModel`), Feather Cloud accounts and settings.
- `FeatherImport`: Evernote and Notion import (macOS only).

Run every check, macOS and iOS: `bash scripts/test_all.sh`.

## Related repositories

- `feather-note-server`: the Feather Cloud sync server (AGPL-3.0)
- `feather-note-universal`: specs, sync protocol, crypto test vectors, designs and plans (CC BY 4.0)

## License

MIT, see [LICENSE](LICENSE).

## Trademark

The name FeatherMark stays with the author. Forks must use a different name.
