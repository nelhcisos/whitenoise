# Sources of the game

`index.html` is built from these files. The master's chapter (scrolls, boards, engine) and the
days (end of shift, the ride home) are spliced in by `build_master.py`:

    python3 src/build_master.py <folder with the master/ and days/ files flattened> index.html

The rest of the game (title, clinic, barin, home screen) is edited directly in `index.html`.
`art/` holds the scripts that drew the pixel sprites and icons. `tests/` holds the Playwright
checks: `e2e.js` plays the whole game, `hometest.js` checks the home screen.

The books retold from lectures (bracket positioning, «Элайнеры с нуля», «Элайнеры от А до Я») are not built into
the game: they live in `lectures/` (see `lectures/README.md` for how to bring one back). Build from a folder with
`src/master/*` and `src/days/*` only.
