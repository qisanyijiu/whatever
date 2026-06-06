# whatever

`whatever` is a macOS SwiftUI app for Chinese native speakers practicing English
with cloze exercises.

## Features

- Minimal practice screen with only the source Chinese and target English.
- Inline English blanks with instant feedback.
- Green underline means correct, red underline means incorrect, gray means empty.
- Built-in seed exercises stored as JSON instead of hard-coded Swift data.
- Paste English text or import a `.txt` file to generate new exercises.
- Download a TED talk transcript from a TED URL and generate exercises.
- Download a public subtitle/script URL (`.srt`, `.vtt`, `.txt`, or readable
  text page) and generate exercises.
- Imported exercises are saved locally and restored on the next launch.

## Run

Build and launch the app:

```bash
./script/build_and_run.sh
```

Build only:

```bash
swift build
```

The launch script creates:

```text
dist/whatever.app
```

## Importing Content

Use the import button in the toolbar to paste English text, select a `.txt`
file, select a subtitle file (`.srt` or `.vtt`), paste a TED talk URL, or paste
a public subtitle/script URL. The app cleans transcript text, splits it into
sentences, and chooses one to three content words per sentence as blanks.

For copyrighted shows such as *Yes, Prime Minister*, provide a legally
accessible subtitle or script URL; the app does not bundle copyrighted scripts.

The current translation service is a placeholder. Imported questions show
`待翻译` in the Chinese line until a real translation provider is connected.

## Data

Seed questions live in:

```text
Sources/EnglishClozeCoach/Resources/SeedPracticeItems.json
```

Imported questions are saved under macOS Application Support:

```text
~/Library/Application Support/whatever/PracticeItems.json
```

For compatibility, the app can still read older saved data from:

```text
~/Library/Application Support/EnglishClozeCoach/PracticeItems.json
```
