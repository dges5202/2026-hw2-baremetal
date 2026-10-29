# Add a learner-local task mode

- state: open
- url: https://github.com/sysprog21/codetrial/pull/259

Task mode lets an instructor publish a PIN-encrypted problem set on a static HTTPS site, and lets a learner work one task with Jim on a CodeTrial they run locally with their own Gemini and LiveKit credentials. The learner signs in with GitHub (device flow), enters the PIN, picks one of the languages the task allows, accepts the announced rules, calibrates the camera and starts in fullscreen. Leaving fullscreen or the page, or looking away past the calibrated limit, ends the attempt as invalid; a camera, detector or connection failure ends it as interrupted; Finish or the deadline completes it with a learning review that carries no hiring verdict. Everything runs on a machine the learner controls, so the encryption and the rules deter rather than prevent, and every page and export says so. Interviews are unchanged. The contract is docs/task-mode.md.

The series starts with two commits that prepare the ground: stopping a dropped Gemini session's reader (interviews benefit too) and raising the mutation shard ceiling to 48, which a diff this size needs. Then task mode itself, including letting a task name the languages a learner may choose: Python when it names none, with C, C++ and Java compiled on Compiler Explorer as in interviews, which the page discloses; C runs only function judges, so a class task cannot list it. Two small test commits follow, bounding the data-dir launch test's wait and pinning the recovery instructions. The last two add the default task, `rubik`, and a scripted interview over it.

## Verification

`./scripts/test.sh` covers task mode with no credentials. The packaging tests need the `cryptography` package, which the gate takes from `target/task-tools` once a `build` has set it up.

CI runs the gate lanes, mutation testing and the security audit, and each commit builds on its own. The task mode suites are `tests/unit/tasks/` (`rubik.rs` is the scripted interview), `tests/unit/livekit/tasks.rs`, `tests/web/tasks.rs`, `tests/browser/task-*.test.js`, `tests/test_task_package.py`, `tests/test_task_authoring.py` and `tests/test_task_mode.py`. The Rust and Python sides validate the same fixtures under `tests/fixtures/task-mode/` and decrypt each other's packages.

## The default task

`new` without `--from` copies `rubik`. Unlike a catalog problem it is not one function to write. The learner starts from a working C cube solver that is correct and too slow and too large for the compiler service, so a run of it is reported as a timeout, and the work is the one a service owner faces: predict where the time goes, measure, change one thing at a time, and keep every answer the same until the run finishes in time. The marked lines show where the cost is (what ranking a position costs, what the queue holds, how each edge moves between positions) and are guidance only. The judge compares answers, so any implementation that returns the exact fewest turns for every case passes, including one leaner than the reference. The interviewer asks the learner to predict before running, to measure before changing, and afterwards how they know no answer changed.

The Python tests compile the starter and the reference with the flags the page asks Compiler Explorer for, show that both answer every case, and require the starter to be several times slower than the reference. Whether the starter exceeds Compiler Explorer's own execution limit is not something the tests can check, since that limit is the service's. `tests/unit/tasks/rubik.rs` drives a scripted interview through the session the live room uses: restate and trace, run the starter and see it time out, a hint, one change at a time, a targeted follow-up, Finish. Its steps in order:

![The scripted interview, from the test in tests/unit/tasks/rubik.rs](https://raw.githubusercontent.com/sysprog21/codetrial/pr-259-screenshots/5-simulated-interview.png)

The task page below was loaded with `rubik` in a browser test harness. The room, the face detector and the compiler are the test doubles the browser tests already use, so the all-cases-pass screenshot comes from a stubbed runner and shows the page, not a real compile or a live interview.

![Assignment unlocked](https://raw.githubusercontent.com/sysprog21/codetrial/pr-259-screenshots/1-assignment.png)
![Ready to start](https://raw.githubusercontent.com/sysprog21/codetrial/pr-259-screenshots/2-ready.png)
![Working, the starter loaded](https://raw.githubusercontent.com/sysprog21/codetrial/pr-259-screenshots/3-working.png)
![All public cases reported as passed by the stubbed runner](https://raw.githubusercontent.com/sysprog21/codetrial/pr-259-screenshots/4-all-cases-pass.png)

## Trying it by hand

Building a set needs no credentials. `scripts/task-package.py` starts a bank from reference tasks: `references` lists the shipped examples in `problem-bank/task-examples/` (completion targets, required cases, custom checks, several languages) and then every catalog problem, and `new` copies one into a bank with its sidecar and set rules written out in full to edit in place, `rubik` when no `--from` names one. The first `build` sets up `target/task-tools`.

```sh
scripts/task-package.py references
scripts/task-package.py new --bank course
scripts/task-package.py new --bank course --from delimiter-closer --id closer
scripts/task-package.py new --bank course --from two-sum --id pair-sum \
    --languages python,javascript,cpp
scripts/task-package.py preview --bank course --task-id pair-sum
scripts/task-package.py build --bank course \
    --site https://USER.github.io/REPO --output publish
```

`--id` gives the copy its own id but keeps the reference's origin, so the checks that keep a catalog problem's source out of what the learner reads still apply while you rewrite it; `new` writes nothing unless the whole bank still validates. `build` asks for a six-digit PIN without echo, takes the next version the output does not hold, and prints each task's assignment link. Publish `publish/` as the root of a GitHub Pages site or any static HTTPS host; the server refuses plain HTTP.

Taking a task needs a Gemini API key, LiveKit credentials and a GitHub OAuth App with device flow enabled, whose public client ID goes in `GITHUB_CLIENT_ID` (without it the page falls back to browser sign-in, which also needs `GITHUB_CLIENT_SECRET`). Run `cargo run -- web` on the default loopback address and open a printed link such as `http://localhost:3000/t/course/pair-sum?site=...&version=1`; a first run goes through Setup and returns to the link. Then, in desktop Chromium or Firefox with a camera and microphone:

- sign in, enter the PIN, and on `pair-sum` switch languages to see the starter, the editor label and the Compiler Explorer notice follow; `delimiter-closer` offers Python and JavaScript, each with its own completion target;
- accept the rules, allow the devices, calibrate (a calibration without the typed line is refused) and Start;
- run the public tests, ask for a hint, discuss a revision, and Finish to get the learning review and its export;
- in further attempts, leave fullscreen, switch tabs or look away past the limit (each ends as invalid), and stop the camera or reload the page (each ends as interrupted).

Task mode is off on a server reachable from elsewhere, one that records, or one that shares a fixed room; its routes then answer `loopback_required`.

## Not done here

The recorded live pilot run the issue's gate asks for, against real LiveKit and Gemini with a published Pages set and real fullscreen and camera behaviour; docs/task-mode.md lists what it must cover. Release builds offer device sign-in only once a maintainer sets the repository variable `CODETRIAL_GITHUB_CLIENT_ID`; until then they fall back to browser sign-in.

Close #242

<!-- This is an auto-generated description by cubic. -->
---
## Summary by cubic
Adds a learner-local task mode where an instructor publishes a PIN-encrypted problem set on a static HTTPS site and a learner works one task with Jim on a locally run CodeTrial using their own Gemini and LiveKit credentials. Interviews are unchanged, and the contract is `docs/task-mode.md`.

**Task mode**
- A task's sidecar lists the languages learners may choose, defaulting to Python; C, C++, and Java compile on Compiler Explorer, so the page says their runs leave the machine. The learner picks a language before calibration connects the room, and the starter, targets, runs and review all follow it.
- Breaking an announced rule (leaving fullscreen or the page, or exceeding the calibrated look-away limit) ends the attempt as invalid; camera, detector, or connection failure ends it as interrupted; Finish or the deadline completes it with a learning review that carries no hiring verdict.
- One attempt runs per process, its result is held only for its own room and expires, and page actions route through the session so recovery sees that room's state; an assignment link opened before any config exists lands on Setup and reloads into the task once Setup saves.
- Everything runs on a machine the learner controls, so the encryption and the rules deter rather than prevent, and every page and export says so.
- The instructor's tool starts a bank from a shipped example or a catalog problem, so a task is edited rather than written from nothing; `--languages` names the set, dropping targets marked in a language it leaves out.
- Release builds enable device sign-in only when a maintainer sets the repository variable `CODETRIAL_GITHUB_CLIENT_ID`; without it they fall back to browser sign-in, and GitHub's signed-in user id counts as the learner's identity only when GitHub issued it.

**Supporting fixes**
- A dropped Gemini session's reader is stopped.
- CI installs the packaging tools in a venv outside the cached target directory.
- The mutation shard ceiling rises to 48.
- The report layout test waits for the offline summary instead of racing it.
- Tests accept a valid output parameter for compiled tasks and distinguish result expiry by room alone.

Still missing from the issue's gate: a recorded live pilot run against real LiveKit and Gemini with a published set and real fullscreen and camera behaviour.

<sup>Written for commit 1a006f4d86313555483d4f6af20c6516bec96590. Summary will update on new commits.</sup>

<a href="https://cubic.dev/pr/sysprog21/codetrial/pull/259?utm_source=github" target="_blank" rel="noopener noreferrer" data-no-image-dialog="true"><picture><source media="(prefers-color-scheme: dark)" srcset="https://www.cubic.dev/buttons/review-in-cubic-dark.svg"><source media="(prefers-color-scheme: light)" srcset="https://www.cubic.dev/buttons/review-in-cubic-light.svg"><img alt="View guided diff" src="https://www.cubic.dev/buttons/review-in-cubic-light.svg"></picture></a> <a href="https://www.cubic.dev/action/auto-fix/pr/sysprog21/codetrial/259?returnTo=https%3A%2F%2Fgithub.com%2Fsysprog21%2Fcodetrial%2Fpull%2F259&source=description" target="_blank" rel="noopener noreferrer" data-no-image-dialog="true"><picture><source media="(prefers-color-scheme: dark)" srcset="https://www.cubic.dev/buttons/turn-on-auto-fix-dark.svg"><source media="(prefers-color-scheme: light)" srcset="https://www.cubic.dev/buttons/turn-on-auto-fix-light.svg"><img alt="Turn on auto-fix" src="https://www.cubic.dev/buttons/turn-on-auto-fix-light.svg"></picture></a>

<!-- End of auto-generated description by cubic. -->



