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
- Local user creation and login.
- Per-user completion progress, recent history, mistake tracking, and SRS review.
- Daily goal tracking, current streak, weekly completion chart, and local macOS reminders.
- Deck-based libraries with search, rename, delete, item editing, and deck-level progress.
- Import preview editor for reviewing Chinese prompts, English sentences, and blanks before saving.
- Mistake review and daily review queues.
- System speech playback plus a dictation/shadowing practice page.
- Local answer tolerance for casing, punctuation, contractions, light stemming, and small typos.
- Multiple local OpenAI-compatible AI profiles with manual active-provider selection.
- Use the selected AI profile to translate imported English into Chinese prompts.
- Use the selected AI profile to explain the current cloze answers, with local fallback.
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

Imported questions start with an editable `待翻译` Chinese prompt. After
generating the preview, use `AI 翻译中文` to translate those prompts with the
currently selected AI profile.

## Data

Seed questions live in:

```text
Sources/EnglishClozeCoach/Resources/SeedPracticeItems.json
```

Decks and imported questions are saved under macOS Application Support:

```text
~/Library/Application Support/whatever/Decks.json
```

Local users and study records are saved under:

```text
~/Library/Application Support/whatever/Users.json
~/Library/Application Support/whatever/Users/<user-id>/StudyData.json
```

Study records include the daily goal and reminder preferences. The reminder
itself is scheduled through macOS local notifications.

AI interface profile metadata is saved locally as:

```text
~/Library/Application Support/whatever/AIProviders.json
```

API keys are stored in macOS Keychain under the app service name
`whatever.ai-providers`. Older JSON files that still contain API keys are
migrated into Keychain on load and rewritten without the secret value.

AI profiles use OpenAI-compatible chat completions. Store a base URL such as
`https://api.openai.com/v1`, a model name, and an API key, then choose the
active profile from the AI page.

For compatibility, the app can still read older saved data from:

```text
~/Library/Application Support/EnglishClozeCoach/PracticeItems.json
```

The older flat `PracticeItems.json` format is migrated into a deck on first
load when no `Decks.json` exists.
