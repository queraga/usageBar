# Releasing UsageBar

Two workflows cover the whole pipeline:

| Workflow  | Runs on                                         | Does                                                |
| --------- | ----------------------------------------------- | --------------------------------------------------- |
| `CI`      | pull requests, pushes to `main` and `develop` | tests, then a Release build + DMG as an artifact    |
| `Release` | pushes to `main` (plus manual runs)             | tests, then build, package, and publish the release |

Both workflows run the same test suite, and `Release` gates its build behind its own `Tests`
job, so a merge to `main` only builds and publishes if the tests pass.

Releases land on the [Releases page](https://github.com/queraga/usageBar/releases) with two
assets under stable names, so download links never change between versions:

- `UsageBar.dmg` — the installer users download
- `UsageBar.app.zip` — the raw app bundle

## Cutting a release

The version is `MARKETING_VERSION` in `UsageBar.xcodeproj` — the single source of truth. To
ship a new version, bump it in the PR that should ship:

```bash
Scripts/app-version.sh   # what the next merge to main would release
```

When the PR merges to `main`, the `Release` workflow tests, builds, and creates a **draft**
release for that version with the DMG and zip attached. Review the notes on the Releases page
and press **Publish release** when you are happy — the git tag is created at that moment.

What a merge to `main` does depends on the version's state:

| State of that version       | Result of the merge                                              |
| --------------------------- | ---------------------------------------------------------------- |
| never released              | tests, builds, creates a draft release                           |
| an unpublished draft exists | tests, builds, updates that draft with the newer build and notes |
| already published           | tests and builds only — nothing is published or overwritten      |

So merges that do not bump `MARKETING_VERSION` (a README fix, a refactor) are still fully
tested and built, but publish nothing. Their DMG is available as a workflow artifact under the
run in the Actions tab.

Every build is also attached to its workflow run as an artifact, so you can test the exact
binary a draft contains before publishing it.

## Manual build, nothing published

**Actions → CI → Run workflow**, pick any branch or tag, and the run tests, builds, and
packages both `UsageBar.dmg` and `UsageBar.app.zip` as an artifact named
`UsageBar-<version>-build<run>`. Download it from the run's summary page; artifacts are kept
for 30 days. `CI` has no release steps at all, so this can never publish anything.

```bash
gh workflow run ci.yml --ref my-branch   # or use the Actions tab
gh run watch                             # then download from the run page
```

Use this to hand someone a build to try, or to check a change on real hardware without
touching the Releases page.

## Beta from `develop`

To rehearse a release before anything reaches `main`: **Actions → Release → Run workflow**,
pick the `develop` branch, set `channel` to `beta`, and run it.

The version becomes the project's `MARKETING_VERSION` with a beta iteration appended —
`0.2.0-beta1`, then `-beta2` on the next run, and so on. The number is one higher than the
highest `<version>-betaN` already released, counting drafts, so consecutive runs never collide
and the count restarts when you bump `MARKETING_VERSION`.

A beta is **always a draft**, even if you tick `publish`:

- draft releases are visible only to collaborators with push access, never to users
- they do not appear in the Releases list for visitors, and `releases/latest` ignores them
- no git tag is created, so nothing on `develop` is marked as shipped
- the notes carry a "Pre-release build for testing" banner naming the branch and commit

Download `UsageBar.dmg` from the draft to test it, then delete the draft when you are done —
nothing else references it. Betas carry the full version in the app itself
(`CFBundleShortVersionString` is `0.2.0-beta1`), so you can tell a beta from a final build in
the About panel.

Publishing from `main` is unaffected: `MARKETING_VERSION` stays `0.2.0`, so the merge to `main`
still drafts a clean `0.2.0` whose changelog covers everything since the last published
release.

## Manual release runs

**Actions → Release → Run workflow** on `main` publishes. Its inputs:

- `channel` — `release` (default) or `beta`, as above
- `version` — an exact version, overriding the channel
- `publish` — publish immediately instead of creating a draft (ignored for betas)
- `refresh` — rebuild and re-upload assets even if that version is already released

## Release notes

`Scripts/release-notes.sh <version>` generates the notes: one bullet per non-merge commit
since the previous released version, install steps, the Gatekeeper note (omitted once builds
are notarized), asset checksums, and a compare link. Run it locally to preview what the next
merge would publish. Because a draft has no tag yet, its changelog is measured from the last
_published_ release, and the notes are regenerated each time the draft is refreshed — so
hand-edits to a draft's notes are overwritten by the next merge to `main`. Edit the notes just
before publishing, or after.

## Local equivalents of what CI does

```bash
./Tests/run.sh                        # provider and store tests
VERSION=0.2.0 Scripts/build.sh        # release/UsageBar.app
Scripts/make-dmg.sh 0.2.0             # release/UsageBar-0.2.0.dmg
Scripts/release-notes.sh 0.2.0        # preview the release body
```

Release builds override `MARKETING_VERSION` with the resolved version and `CFBundleVersion`
with the workflow run number, so `CURRENT_PROJECT_VERSION` in the project file never needs
touching.
