# Intercom Bulk Cleaner

A Ruby CLI for bulk deleting those contacts through **Intercom's** API

## Setup

```bash
git clone <your-repository>
cd intercom-bulk-cleaner
cp .env.example .env
```

**Set your access token in the .env file before running the CLI:**

```bash
INTERCOM_ACCESS_TOKEN="your_intercom_token"
```

**Make it the executable:**

```bash
chmod +x bin/intercom-cleaner
```

## Workflow

```bash
bin/intercom-cleaner create-test
bin/intercom-cleaner export
bin/intercom-cleaner delete
```

- `create-test` creates the configured number of test contacts and records the run prefix.
- `export` paginates through contacts and exports only contacts matching that run prefix and the `user` role.
- `delete` validates the CSV and run prefix, asks for an exact confirmation phrase, deletes in batches, then verifies
  the result.

