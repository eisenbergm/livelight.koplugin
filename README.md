# Live Light

A KOReader plugin that makes the brightness and warmth edge swipes behave the way they do in Kobo's own software: the light changes **while your finger is moving**, not after you lift it.

- Slide up or down the **left edge** of the screen for brightness.
- Slide up or down the **right edge** for warmth.
- A small box shows the level as you go.

## Why

KOReader already lets you swipe the screen edges to change the light, but it waits for the whole swipe to finish, measures it, and then jumps. You swipe, look, swipe again, look again. On a Kobo running its stock software, the light simply follows your finger. This plugin brings that back.

People have been asking for this in KOReader for a long time ([#2096](https://github.com/koreader/koreader/issues/2096), [#5313](https://github.com/koreader/koreader/issues/5313), [#14498](https://github.com/koreader/koreader/issues/14498)).

## Tested on

| Device | KOReader | Result |
|---|---|---|
| Kobo Clara BW | <!-- TODO: your KOReader version --> | Works |

That is the only device it has been tried on. It should work on any touch device where KOReader can control the frontlight, but that is untested. KOReader's maintainers have noted that on some devices each light change takes long enough that live updating may feel sluggish. Reports from other devices are welcome.

Devices without a warmth light get brightness on the left edge only; the right edge is left alone.

## Install

1. Download `livelight.koplugin.zip` from the [Releases](../../releases) page and unzip it. You should have a folder named `livelight.koplugin`.
2. Connect your e-reader to a computer with USB.
3. Copy the `livelight.koplugin` folder into KOReader's `plugins` folder. On a Kobo that is `.adds/koreader/plugins/`. The `.adds` folder is hidden: on a Mac, press **Cmd+Shift+.** in Finder to show it.
4. Eject the device and restart KOReader.

You do not need to change any gesture settings. Live Light takes priority over KOReader's built-in edge swipes while it is switched on, and hands the edges back when it is switched off.

To update, copy the new folder over the old one and restart KOReader. To uninstall, delete the folder.

## Using it

Put a finger on the left or right edge of the screen (the outer eighth) and slide up or down. Start moving straight away: if you rest your finger for about half a second first, KOReader treats it as a long-press.

- About 70% of the screen height covers the full range.
- Sliding brightness all the way down turns the light off; sliding back up turns it on.
- Warmth moves in the device's own steps (0 to 10 on a Clara BW), so it changes in notches.
- Once a slide has started, your finger can wander off the edge strip and it keeps working until you lift.

### Settings

Top menu → gear icon → **Taps and gestures** → **Live Light**:

- **Change the light while sliding along the screen edges**: the main on/off switch.
- **Show the level while sliding**: show or hide the box with the number.

## Where it works

- **While reading a book.** <!-- Confirmed on the Clara BW. -->
- **KOReader's file browser, History, Favorites, Collections** and other full-screen lists.
- **[Bookshelf](https://github.com/AndyHazz/bookshelf.koplugin) home screens**, with one exception: after you leave a book, Bookshelf keeps it open underneath until the device has gone untouched for 30 to 40 seconds (or you open a different book), and until then the edges fall back to KOReader's normal swipe-then-jump behaviour. <!-- TODO: confirm on device before publishing. -->

It deliberately stays out of pop-up menus, dialogs, and full-screen viewers such as the image viewer and book map, where dragging already means something else.

## Things to know

- **The number looks rough while it is changing.** E-ink can only redraw quickly in pure black and white, with no grey to smooth the edges of text. Live Light uses that fast mode for the number while your finger is moving, then redraws it cleanly when you pause for a moment or lift. The word beside it is always drawn cleanly.
- **Screen corners.** A slide that starts in a top or bottom corner of an edge strip adjusts the light instead of opening KOReader's top or bottom menu. Swiping from the rest of the top or bottom edge still opens the menus. Corner taps and long-presses are not affected.
- **A very fast flick** is applied in one step when you lift, since KOReader never reports it as a slide in progress. On list screens such as History, a fast downward flick from the edge still closes the list, as it does without this plugin.

## How it works

KOReader reports a completed swipe only when the finger lifts, but it also sends a stream of "pan" events while the finger is moving. Live Light listens to those and sets the light on each one.

- **In a book**, it registers touch zones through KOReader's standard mechanism, ordered ahead of the reader's own zones and the Gestures plugin's edge swipes. Nothing in the Gestures plugin is modified.
- **On list screens**, KOReader's `Menu` widget consumes every pan before any touch zone sees it. So the plugin wraps three of `Menu`'s gesture handlers at runtime and gets first look at each pan, passing on anything that is not an edge slide. No KOReader files are changed on disk, but this part depends on KOReader internals and could be broken by a future KOReader update.
- **Under Bookshelf**, the file-browser zones carry a `filemanager_` prefix, which is how Bookshelf decides which touches to pass down to the file browser underneath it.

The light is changed through the same KOReader calls the built-in gesture and light dialog use.

## Tests

The plugin's logic is covered by an off-device simulation: a fake screen, a fake light, and a fake finger that produces the same events KOReader's gesture detector does. It runs under Node using [Fengari](https://fengari.io/), a Lua interpreter written in JavaScript.

```bash
npm install fengari fengari-interop
```

```bash
node tests/run.js tests/livelight_harness.lua "$PWD/livelight.koplugin" "$PWD"
```

The simulation checks the logic, not the device: how the screen and light actually respond can only be judged on a real e-reader.

## Credits

<!-- TODO: author name, and whether to mention it was written with Claude. -->

## Licence

<!-- TODO: choose a licence and add a LICENSE file. KOReader itself is AGPL-3.0, and plugins conventionally match it. -->
