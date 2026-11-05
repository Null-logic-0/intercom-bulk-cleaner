# Intercom Bulk Cleaner

A Ruby CLI to **find, export and bulk delete Intercom contacts**.

## The problem

Intercom workspaces fill up with contacts you no longer need: inactive users, test accounts, old leads, people who asked to be removed. Cleaning them up is hard:

- The Intercom dashboard has no good way to delete thousands of contacts at once.
- Intercom's API can do it, but you first have to find the right contacts and collect their IDs.
- Deleting the wrong contacts is a costly mistake, so you want to see exactly what will be deleted before anything happens.

## The solution

This tool splits the cleanup into safe steps:

1. **Search.** Find contacts by email (one or thousands at once) or any filter: dates, tags, custom attributes and more.
2. **Export.** Save the matches to a file (CSV, JSON or JSONL) that you can review, and edit if you want.
3. **Delete.** Delete exactly the contacts in that file, after a preview and a typed confirmation.
4. **Verify.** Check that every contact is really gone.

Searching and exporting only read data. Contacts are deleted only by `delete`.

## Setup

```bash
cp .env.example .env     # then set INTERCOM_ACCESS_TOKEN in .env
bundle install
chmod +x bin/intercom-cleaner
```

The access token needs permission to read and write contacts.

## Usage

### Interactive app (easiest)

```bash
bin/intercom-cleaner
```

This opens a menu you control with the arrow keys:

```
╭─ Intercom Bulk Cleaner ──────────────────────────╮
│ Search, export and bulk delete Intercom contacts │
│ Workspace: Acme Inc  ·  you@acme.io              │
╰──────────────────────────────────────────────────╯
? What do you want to do?
› Search & export              filter by email, dates, tags, custom attributes...
  Bulk lookup by email         paste a list or load a .txt / .csv
  Export all contacts          every user and/or lead
  Delete contacts from a file  preview, confirm, delete, verify
  Verify a past deletion       check deleted contacts are gone
  Test tools                   create and remove fake contacts
  Quit
```

- The banner shows which workspace you're connected to, so you know where a delete will happen.
- Pick a filter field by typing part of its name. Values are checked as you go, and an invalid one is asked again.
- Before exporting, you see how many contacts match and a preview table.
- Exports and deletions show progress bars.
- Each step leads to the next: export, then delete those contacts, then verify. File lists show your recent exports and deletion logs, newest first.
- Ctrl+C cancels the current step. At the main menu, it quits.

`bin/intercom-cleaner search` jumps straight to the search. Every command below also works on its own for scripts. When the output isn't a terminal, menus become numbered lists.

### Bulk search by email

```bash
bin/intercom-cleaner search-export -E emails.csv              # file: .txt (one per line) or .csv (email column)
bin/intercom-cleaner search-export -e a@x.com,b@y.com         # inline
```

Emails that match nothing are saved to `exports/..._not_found.txt`.

### Search by filters

```bash
bin/intercom-cleaner search-export -f "last_seen_at < 90d"
bin/intercom-cleaner search-export -f "email_domain = gmail.com" -f "created_at < 2025-01-01"
bin/intercom-cleaner search-export -f "custom_attributes.plan = free" --match any
```

A filter is written as `"FIELD OPERATOR VALUE"`, with spaces around the operator. Filters can be combined with bulk emails.

### Export everything

```bash
bin/intercom-cleaner export-all                 # all users
bin/intercom-cleaner export-all --role all      # users and leads
```

### Delete

```bash
bin/intercom-cleaner delete exports/contacts_search_<time>.csv --dry-run   # preview only
bin/intercom-cleaner delete exports/contacts_search_<time>.csv             # delete
```

It shows the count and a preview, then asks you to type `DELETE <count> CONTACTS`. Before deleting, the IDs are saved to `logs/deleted_<time>.csv`.

### Verify

```bash
bin/intercom-cleaner verify logs/deleted_<time>.csv
```

Each contact is looked up by ID. A "not found" answer means it's gone.

### Useful options

| Option | What it does |
|---|---|
| `--count` | Only show how many contacts match |
| `--dry-run` | Show what would be sent or deleted, without doing it |
| `--role user\|lead\|all` | Which contacts to include (default: `user`) |
| `--format csv\|json\|jsonl` | Output format (default: `csv`) |
| `--limit N` | Stop after N contacts |
| `--columns id,email,...` | Choose CSV columns |

See all fields and operators: `bin/intercom-cleaner search-export --help`

## Good to know

- **Date filters match whole days** in your workspace's timezone: `created_at > 2026-01-15` starts on Jan 16. Dates can be `YYYY-MM-DD`, a Unix timestamp or `90d` (90 days ago).
- **New contacts take a few minutes** to appear in search.
- **Deleting is a soft delete for 7 days.** Contacts disappear right away, but Intercom keeps the data for a 7-day grace period before it's permanently destroyed. During that time you can't re-create a contact with the same email.
- Intercom limits: 15 filters per group, 2 levels of nesting, 150 results per page and 100 contacts per delete batch. The tool handles these for you.

## Testing

Test in three levels, from safest to real:

**1. Automated tests.** Offline, no token needed.

```bash
bin/test
```

**2. Demo mode.** The full app with 500 fake contacts. Nothing is sent to Intercom.

```bash
bin/demo
```

Try every menu item: search, bulk lookup, export, delete, verify, test tools. Files go to `tmp/demo/`.

**3. Your real workspace, safely.**

```bash
bin/intercom-cleaner export-all --count                      # read-only: how many contacts?
bin/intercom-cleaner search-export -f "email ~ test" --limit 5 # read-only: small export
bin/intercom-cleaner delete <file> --dry-run                 # shows what would be deleted
```

Then try deleting with fake contacts. In the app, open **Test tools**:
create fake contacts, export the last test run, then delete the last test run.
The delete refuses anything that isn't from that test run. Or from the command line:

```bash
bin/intercom-cleaner create-test         # creates TEST_CONTACT_COUNT fake users
bin/intercom-cleaner export              # exports only those fake users
bin/intercom-cleaner delete --test-run   # refuses anything that isn't from that test run
```
