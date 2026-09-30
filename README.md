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

Paste this into your AI coding tool. If you have a Deepgram key, put it where it says MY_KEY_HERE. If you don't, leave it and you'll get Apple's speech. You'll approve a couple of permission pop-ups (Microphone and Accessibility) along the way.

```
Set up the Dictation app on my Mac from https://github.com/louievillaverde/build-your-own-dictation. It's a native macOS dictation app written in Swift. Do every step yourself, and only stop when you need me to click something.

1. Clone it into ~/dictation. Read the README, build.sh and the Sources folder first.
2. Check that the Xcode command line tools are installed (xcode-select -p). If they aren't, run xcode-select --install and wait for me to finish the installer.
3. My Deepgram key: MY_KEY_HERE
   If that's a real key, save it as DEEPGRAM_API_KEY=<the key> in ~/.dictation-secrets.env and chmod 600 the file. If it still says MY_KEY_HERE, skip this step. The app will use Apple's on-device speech, which needs no account.
4. Run ./build.sh. It picks how to sign the app on its own, so don't edit it. If the build fails, fix the cause and run it again until /Applications/Dictation.app is installed.
5. Open Dictation. As each permission pop-up appears, tell me what to approve: Microphone first, then Accessibility (System Settings > Privacy & Security > Accessibility, switch Dictation on). If macOS asks about Speech Recognition, I'll approve that too. Wait for me to say done after each one.
6. Once Accessibility is on, quit and reopen Dictation so the hotkey starts working.
7. Test it: tell me to click into a text box, hold right Option, say a sentence and let go. Then read ~/Library/Application Support/Dictation/debug.log and tell me which engine handled the take and whether it pasted.
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
