# Buildfarm Query API

`cgi-bin/bfapi.pl` is a read-only, JSON query interface to the buildfarm
database. It exposes the same data that backs the HTML dashboard, history,
failures and members pages, but as plain JSON suitable for scripting.

All responses are `Content-Type: application/json`. There is no
authentication; the API is read-only and returns only data already published
on the public web pages. Owner email addresses are obfuscated, as on the web
pages.

## Routing

The resource is selected by the URL path; filters are supplied as additional
path segments and/or query-string parameters:

```
/cgi-bin/bfapi.pl/<resource>[/<arg>...][?<param>=<value>...]
```

`<resource>` is one of `status`, `history`, `failures`, `members`, `build`,
`log`, `commit`. An unknown resource returns HTTP 400-style JSON:

```json
{ "error": "unknown resource 'foo'; expected one of: build, commit, failures, history, log, members, status" }
```

### Branch names

Branches may be given by either their internal name (`HEAD`) or their public
name (`master`); the two are accepted interchangeably. In output, the branch
is always reported by its public name (`master`).

---

## `GET /cgi-bin/bfapi.pl/status[/<branch>[/<member>]]`

Current dashboard status — the latest run for each member and branch.

**Filters**

| Parameter | Where | Description |
|-----------|-------|-------------|
| `<branch>` | path seg 1 | restrict to one branch |
| `<member>` | path seg 2 | restrict to one animal |
| `member` | query | restrict to one animal (alternative to the path) |
| `owner` | query | restrict to animals owned by this email |
| `sortby` | query | `name`, `os`, or `compiler` (otherwise grouped by branch) |

**Example**

```
GET /cgi-bin/bfapi.pl/status/HEAD?sortby=os
```

**Each row**

```jsonc
{
  "when_ago_secs": 1234,            // seconds since the snapshot (GMT)
  "sysname": "myanimal",
  "snapshot": "2026-05-31 04:00:00",
  "status": 0,                      // build exit status; 0 = success
  "stage": "OK",                    // stage reached ("OK" on success)
  "branch": "master",
  "build_flags": ["cassert", "tap-tests", "..."],
  "operating_system": "Linux",
  "os_version": "...",
  "compiler": "gcc",
  "compiler_version": "...",
  "architecture": "x86_64",
  "git_head_ref": "...",
  "report_time": "2026-05-31 04:05:00+00",
  "log_archive_filenames": ["config.log", "..."]
}
```

---

## `GET /cgi-bin/bfapi.pl/history/<member>[/<branch>]`

Recent run history for one animal, newest first, drawn from the recent-500
cache. A member name is required.

**Filters**

| Parameter | Where | Description |
|-----------|-------|-------------|
| `<member>` | path seg 1 | **required** — the animal name |
| `<branch>` | path seg 2 | restrict to one branch |
| `branch` | query | restrict to one branch (alternative to the path) |
| `limit` | query | max rows, default 100, capped at 500 |

Omitting the member yields:

```json
{ "error": "history requires a member name" }
```

**Example**

```
GET /cgi-bin/bfapi.pl/history/myanimal/REL_17_STABLE?limit=20
```

**Each row**

```jsonc
{
  "when_ago_secs": 1234,
  "sysname": "myanimal",
  "snapshot": "2026-05-30 04:00:00",
  "status": 0,
  "stage": "OK",
  "branch": "REL_17_STABLE",
  "script_version": "18.1",
  "git_head_ref": "...",
  "run_secs": 842
}
```

---

## `GET /cgi-bin/bfapi.pl/failures[/<branch>]`

Recent failures across the farm within a time window.

**Filters** (`member`, `stage` and `branch` are repeatable)

| Parameter | Where | Description |
|-----------|-------|-------------|
| `<branch>` | path seg 1 | restrict to one branch |
| `member` | query | restrict to these animals (repeatable) |
| `stage` | query | restrict to these failing stages (repeatable) |
| `branch` | query | restrict to these branches (repeatable) |
| `max_days` | query | window in days, default 10 |
| `skipok` | query | if set, drop rows whose animal is currently green (`current_stage == "OK"`) |

**Example**

```
GET /cgi-bin/bfapi.pl/failures/HEAD?stage=Check&stage= Make&max_days=5
```

**Each row**

```jsonc
{
  "when_ago_secs": 1234,
  "sysname": "myanimal",
  "snapshot": "2026-05-29 04:00:00",
  "status": 2,
  "stage": "Check",                 // the failing stage
  "branch": "master",
  "build_flags": ["cassert", "..."],
  "operating_system": "Linux",
  "compiler": "gcc",
  "os_version": "...",              // as of report time (from personality)
  "compiler_version": "...",        // as of report time (from personality)
  "git_head_ref": "...",
  "report_time": "2026-05-29 04:05:00+00",
  "current_stage": "OK"             // the animal's current dashboard stage
}
```

---

## `GET /cgi-bin/bfapi.pl/members[/<member>]`

Buildfarm animal metadata. Animals with status `pending` or `declined` are
excluded.

**Filters**

| Parameter | Where | Description |
|-----------|-------|-------------|
| `<member>` | path seg 1 | restrict to one animal |
| `sort_by` | query | `name`, `owner`, `os`, `compiler`, or `arch` (default `name`) |

**Example**

```
GET /cgi-bin/bfapi.pl/members?sort_by=os
```

**Each row**

```jsonc
{
  "name": "myanimal",
  "operating_system": "Linux",
  "os_version": "...",
  "compiler": "gcc",
  "compiler_version": "...",
  "owner_email": "someone [ a t ] example.com",
  "sys_notes_date": "2026-01-15",
  "sys_notes": "...",
  "arch": "x86_64",
  "status": "approved",
  "status_date": "2026-01-01",
  "branches": ["master:0", "REL_17_STABLE:1"],   // "branch:days-since-last-run"
  "personalities": [
    { "compiler_version": "...", "os_version": "...", "effective_date": "2025-09-01" }
  ]
}
```

---

## `GET /cgi-bin/bfapi.pl/build/<member>?snapshot=<ts>|latest[&branch=<branch>]`

The full record for a single run. A member name is required, and a snapshot
must be supplied as a query parameter (it contains a space, so it is awkward
in a path). `snapshot=latest` resolves to the animal's most recent run in the
last 30 days and **requires** a `branch`.

**Filters**

| Parameter | Where | Description |
|-----------|-------|-------------|
| `<member>` | path seg 1 | **required** — the animal name |
| `snapshot` | query | **required** — `YYYY-MM-DD HH:MM:SS` (GMT) or `latest` |
| `branch` | query | required only when `snapshot=latest` |

**Example**

```
GET /cgi-bin/bfapi.pl/build/myanimal?snapshot=latest&branch=HEAD
```

**Response** (a single object, not an array)

```jsonc
{
  "sysname": "myanimal",
  "snapshot": "2026-05-31 04:00:00",
  "when_ago_secs": 1234,
  "status": 0,
  "stage": "OK",
  "branch": "master",
  "conf_sum": "...",                // the build configuration summary
  "scm": "git",
  "scmurl": "...",
  "git_head_ref": "abc123...",
  "changed_this_run": "...",        // raw change list as recorded by the client
  "changed_since_success": "...",
  "build_flags": ["cassert", "..."],
  "log_archive_filenames": ["config.log", "..."],
  "report_time": "2026-05-31 04:05:00+00",
  "run_secs": 842,
  "operating_system": "Linux",
  "os_version": "...",              // as of report time (from personality)
  "compiler": "gcc",
  "compiler_version": "...",        // as of report time (from personality)
  "architecture": "x86_64",
  "owner_email": "someone [ a t ] example.com",
  "stages": [                       // logs available via /log, ".log" stripped
    { "stage": "configure", "duration_secs": 12 },
    { "stage": "make",      "duration_secs": 230 },
    { "stage": "check",     "duration_secs": 540 }
  ]
}
```

Unknown member/snapshot returns `{ "error": "no such build" }`.

---

## `GET /cgi-bin/bfapi.pl/log/<member>/<stage>?snapshot=<ts>|latest[&branch=<branch>]`

The captured log text for one stage of one run. The `stage` is given without
the `.log` suffix (the values returned in a build's `stages` list). As with
`/build`, `snapshot=latest` requires a `branch`.

**Filters**

| Parameter | Where | Description |
|-----------|-------|-------------|
| `<member>` | path seg 1 | **required** — the animal name |
| `<stage>` | path seg 2 | **required** — stage name, e.g. `make`, `check` |
| `snapshot` | query | **required** — `YYYY-MM-DD HH:MM:SS` (GMT) or `latest` |
| `branch` | query | required only when `snapshot=latest` |
| `format` | query | `json` (default) or `text` |

**Examples**

```
GET /cgi-bin/bfapi.pl/log/myanimal/check?snapshot=2026-05-31%2004:00:00
GET /cgi-bin/bfapi.pl/log/myanimal/check?snapshot=latest&branch=HEAD&format=text
```

**Response** (`format=json`)

```jsonc
{
  "sysname": "myanimal",
  "snapshot": "2026-05-31 04:00:00",
  "branch": "master",
  "stage": "check",
  "log_text": "...the full stage log..."
}
```

With `format=text`, the body is the raw log as `text/plain`. Unknown
member/snapshot/stage returns `{ "error": "no such log" }`.

---

## `GET /cgi-bin/bfapi.pl/commit/<gitref>`

All runs built at a given git commit, newest first. The ref is matched as a
hex prefix and must be at least 5 hex digits.

**Filters**

| Parameter | Where | Description |
|-----------|-------|-------------|
| `<gitref>` | path seg 1 | **required** — commit hash or prefix (>= 5 hex digits) |
| `member` | query | restrict to one animal |
| `branch` | query | restrict to one branch |
| `limit` | query | max rows, default 200, capped at 1000 |

**Example**

```
GET /cgi-bin/bfapi.pl/commit/9a1b2c3d?branch=HEAD
```

**Each row**

```jsonc
{
  "when_ago_secs": 1234,
  "sysname": "myanimal",
  "snapshot": "2026-05-31 04:00:00",
  "status": 0,
  "stage": "OK",
  "branch": "master",
  "git_head_ref": "9a1b2c3d...",
  "report_time": "2026-05-31 04:05:00+00",
  "run_secs": 842
}
```

> Note: `git_head_ref` is not indexed, so this query is a table scan bounded
> by `limit`. Supply as many digits of the hash as you can.

---

## Notes

* `build_flags` is normalized for display: configure-style prefixes are
  stripped, defaults that are no longer optional (integer datetimes, thread
  safety) are made explicit on the relevant branches, and a few flag names are
  canonicalized (e.g. `libxml` → `xml`, `asserts` → `cassert`).
* Times in `snapshot` are GMT; `report_time` carries an explicit `+00` offset.
* `when_ago_secs` is the integer number of seconds between the snapshot and
  the current GMT time.
