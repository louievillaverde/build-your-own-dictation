# Build your own dictation app

A native macOS dictation app written in Swift. Hold a key, talk, let go, and your words show up wherever your cursor is.

It works with no account at all, and if you add your own API keys, they're your accounts and nobody else's.

**The full guide:** [leadpiranha.com/free/dictation-app](https://www.leadpiranha.com/free/dictation-app)

## What it does

- **Hold to talk.** Hold right Option (or any key you pick in Settings), talk and let go. Double-tap it to go hands-free, and press Esc to cancel.
- **Works with no account.** Out of the box it uses Apple's on-device speech. Add a Deepgram key for faster, more accurate text (Nova-3), or switch to ElevenLabs Scribe.
- **Spells your names right.** Keep a plain list of names and words, one per line, and it sends that list with every take.
- **Pauses your music** while you talk and picks it back up when you stop.
- **Keeps everything.** Every take is saved in a History window (Control-Option-H) and in a daily text file in `~/Dictations`. Control-Option-V pastes the last one again.
- **Cleans up filler** for free. Add an Anthropic key and it can also run a Claude Haiku cleanup pass, which you can turn on or off per type of app.
- **Has a backup.** If a cloud engine fails or the internet drops, Apple's on-device speech takes over.

## What you need

- A Mac with **Apple Silicon** and **macOS 26** (Tahoe)
- The Xcode command line tools (`xcode-select --install`)
- An AI coding tool that can run commands on your Mac, like Claude Code, Codex or Cursor, if you want it to do the setup for you
- Optional: a [Deepgram](https://deepgram.com) key (recommended, new accounts get free credit), an ElevenLabs key, and an Anthropic API key

## Set it up with one prompt

Paste this into your AI coding tool. It offers to set up a free Deepgram key with you; skip it and you'll get Apple's speech. You'll approve a couple of permission pop-ups (Microphone and Accessibility) along the way.

```
Set up the Dictation app on my Mac from https://github.com/louievillaverde/build-your-own-dictation. Do every step yourself and only stop when you need me to click something.

1. Clone it to ~/dictation and read the README.
2. Make sure the Xcode command line tools are installed.
3. Ask me if I want Deepgram for faster, more accurate transcription (free $200 credit, no card). If yes, open https://console.deepgram.com/signup for me, walk me through creating an API key, have me paste it here, and save it as DEEPGRAM_API_KEY in ~/.dictation-secrets.env (chmod 600). If no, skip it. The app uses Apple's on-device speech.
4. Run ./build.sh and fix anything that fails until Dictation.app is installed.
5. Open Dictation and tell me which permission pop-ups to approve (Microphone and Accessibility, maybe Speech Recognition). Restart it once Accessibility is on.
6. Have me hold right Option, say a sentence and let go, then confirm it typed.
```

## Build it by hand

```sh
git clone https://github.com/louievillaverde/build-your-own-dictation ~/dictation
cd ~/dictation
# optional: echo 'DEEPGRAM_API_KEY=your-key' > ~/.dictation-secrets.env && chmod 600 ~/.dictation-secrets.env
./build.sh                 # builds, signs and installs /Applications/Dictation.app
./build.sh --no-install    # builds build/Dictation.app only
```

`build.sh` signs with your first "Apple Development" identity if you have one, and ad hoc (`-`) if you don't. Set `SIGN_IDENTITY` to pick a different one. With ad hoc signing, macOS may forget the Microphone and Accessibility grants after each rebuild, so grant them again if the hotkey stops working.

## Where things live

| What | Where |
| --- | --- |
| API keys | `~/.dictation-secrets.env` (or set them in Settings > Engines) |
| Your names and words | `~/Library/Application Support/Dictation/vocab.txt` |
| Spoken shortcuts | `~/Library/Application Support/Dictation/snippets.tsv` |
| History database and audio | `~/Library/Application Support/Dictation/` |
| Debug log | `~/Library/Application Support/Dictation/debug.log` |
| Daily text archive | `~/Dictations/` |
| Settings | `defaults read com.example.dictation` |

`tools/` has small helpers for testing: `dictatectl.swift` triggers the app from the command line, `fakekey.swift`, `hover.swift` and `drag.swift` simulate input, and `import_wispr.py` brings in your Wispr Flow history and dictionary.

## License

MIT. See [LICENSE](LICENSE).
