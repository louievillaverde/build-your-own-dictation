# Build your own dictation app

A native macOS dictation app written in Swift. Hold a key, talk, let go, and your words show up wherever your cursor is.

It runs on your own API keys, so it's your accounts and nobody else's.

**The full guide:** [leadpiranha.com/free/dictation-app](https://www.leadpiranha.com/free/dictation-app)

## What it does

- **Hold to talk.** Hold right Option (or any key you pick in Settings), talk and let go. Double-tap it to go hands-free, and press Esc to cancel.
- **Fast and accurate.** It sends your voice to Deepgram's Nova-3 model while you're still talking. ElevenLabs Scribe is built in as a second engine.
- **Spells your names right.** Keep a plain list of names and words, one per line, and it sends that list with every take.
- **Pauses your music** while you talk and picks it back up when you stop.
- **Keeps everything.** Every take is saved in a History window (Control-Option-H) and in a daily text file in `~/Dictations`. Control-Option-V pastes the last one again.
- **Cleans up filler** for free. Add an Anthropic key and it can also run a quick cleanup pass, which you can turn on or off per type of app.
- **Has a backup.** If the internet drops, Apple's on-device speech takes over.

## What you need

- A Mac with **Apple Silicon** and **macOS 26** (Tahoe)
- The Xcode command line tools (`xcode-select --install`)
- A [Deepgram](https://deepgram.com) API key
- Optional: an ElevenLabs key and an Anthropic API key
- [Claude Code](https://claude.com/claude-code), if you want it to do the setup for you

## Set it up with one prompt

Open Terminal, start Claude Code and paste this in. Swap in your Deepgram key where it says to.

```
Set up the Dictation app for me from https://github.com/louievillaverde/build-your-own-dictation. It's a native macOS dictation app written in Swift.

1. Clone it into ~/dictation and read the README, build.sh, Info.plist and the Sources folder first.
2. Make sure the Xcode command line tools are installed (xcode-select -p). If they aren't, run xcode-select --install and wait for me.
3. Run `security find-identity -v -p codesigning` and tell me whether build.sh will sign with my "Apple Development" identity or ad hoc. It picks on its own, so don't edit it.
4. Save my Deepgram key as DEEPGRAM_API_KEY=MY_KEY_HERE in ~/.dictation-secrets.env and chmod 600 that file.
5. Run ./build.sh. If the build fails, fix it and run it again until it installs /Applications/Dictation.app.
6. Open the app. Then walk me through granting Microphone, and Accessibility in System Settings > Privacy & Security, one at a time. Wait for me to say done after each one.
7. After I grant Accessibility, quit and reopen Dictation so the hotkey starts working.
8. Launch at login turns itself on the first time the app opens. Check it's on in Dictation's Settings.
9. Tell me to click into a text box, hold right Option, say a sentence and let go. Then check ~/Library/Application Support/Dictation/debug.log and confirm the take went through Deepgram.
```

## Build it by hand

```sh
git clone https://github.com/louievillaverde/build-your-own-dictation ~/dictation
cd ~/dictation
echo 'DEEPGRAM_API_KEY=your-key' > ~/.dictation-secrets.env && chmod 600 ~/.dictation-secrets.env
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
