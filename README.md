# Git Rotate

Git Rotate lets you swap the `.git` folder underneath a project. The working
files stay where they are while the Git history, branches, remotes, and config
change with the selected record.

## Why Would Anyone Want Git Rotate?

Because apparently having one Git history wasn't enough.

- 🔄 **Multiple Git histories, one folder**

  Same files, completely different Git universes. Because copying the entire
  project was apparently too reasonable.
- 🕵️ **Escape `git blame`**

  Sometimes you don't want to know who wrote that line. Sometimes you
  definitely don't want Git to know either.
- 🏢 **Work vs personal Git**

  Same codebase, different Git history. Keep your side quests separate from
  your day job.
- 🌍 **Public vs private history**

  Publish the code without publishing the entire archaeological dig that
  produced it.
- 👥 **One codebase, multiple clients**

  Same files, different repositories. Everyone gets their own little reality.
- 🧪 **Experiment with Git without ruining everything**

  Rewrite history. Delete branches. Do something horrifying with `rebase`.
  Your other `.git` can sit quietly and pretend nothing happened.
- 🧹 **Fresh history without touching the files**

  Sometimes you just want the code without dragging along 4,000 commits of
  "fix typo".
- 🔐 **Stop pushing to the wrong remote**

  Different `.git` directories mean different remotes. Because apparently
  checking `git remote -v` was too much work.
- 🎭 **Different Git identities**

  One history for Serious Professional You(TM) and another for You Who Commits
  at 2 AM.
- 🚀 **Keep completely separate project timelines**

  Production, experiments, demos, forks, customer versions, questionable
  prototypes. Same working tree, different timelines.
- 💾 **Keep alternate realities around**

  Your files stay the same. Your Git history changes. It's basically multiverse
  theory, but for software projects.
- 🧯 **Do stupid Git experiments safely**

  Keep a backup `.git` somewhere and go absolutely feral in the other one.
- 🧠 **Because Git is weird**

  Git Rotate is a practical demonstration that your files and your Git history
  are actually two different things that just happen to live together.

## The elevator pitch

> **Git Rotate lets you swap the `.git` folder underneath your project.**
>
> Same files.
>
> Different history.
>
> Different branches.
>
> Different remotes.
>
> Different Git identity.
>
> **One working tree. Multiple timelines.**
>
> Because apparently Git wasn't complicated enough.

## Build It

Git Rotate is written in Zig and currently requires Zig `0.16.0` or newer.

```sh
zig build -Doptimize=ReleaseSafe
```

The executable is written to `zig-out/bin/git-rotate` (or
`git-rotate.exe` on Windows). Put that directory on your `PATH` so Git can
discover it as the `git rotate` subcommand.

You can also run it directly from the project root:

```sh
zig build run -- help
```

## How It Works

Run Git Rotate from the project directory whose files you want to keep:

```text
project/
  .git/                 active Git record (a symlink)
  .gitrotate/
    work/               saved Git record
    personal/           another saved Git record
    .RECORDS            active-record bookkeeping
  src/
  README.md
```

The first time Git Rotate runs, it creates `.gitrotate` and adds it to
`.gitignore`. Record directories contain Git metadata only; your working files
are shared by every record.

Before switching records, commit or stash changes that should belong to the
current history. Git Rotate changes Git metadata, but it does not reconcile
different branches or working-tree changes for you.

## Basic Usage

### Register the current repository

From an existing Git repository:

```sh
git rotate checkout work
```

This moves the current `.git` directory into `.gitrotate/work` and creates the
`.git` link that points to it. The name can contain up to 32 characters.

### Create a new local record

To create a fresh Git history for the same files:

```sh
git rotate checkout experiment local
```

This initializes a new Git repository for the record without cloning a remote.

### Create a record from a remote

Provide a record name and a remote URL:

```sh
git rotate checkout public origin https://example.com/owner/project.git
```

The shorter form defaults the remote name to `origin`:

```sh
git rotate checkout public https://example.com/owner/project.git
```

### Switch records

Use the record name as the command:

```sh
git rotate work
git rotate personal
```

The selected record becomes the active `.git` directory. Check the active
record and available records with:

```sh
git rotate status
```

The active record is marked with `*`.

### Delete a record

When a record is no longer needed:

```sh
git rotate delete experiment
```

Deletion is permanent. Back up any history you may need before removing it.

### Get help

```sh
git rotate help
```

Running `git rotate` without a command also prints the help message.

## When To Use It

Git Rotate is useful when the source files should remain shared but the Git
metadata should be isolated:

- maintaining separate work, personal, public, or client histories;
- testing history rewrites, rebases, and branch experiments;
- creating a clean history for a demo or publication;
- switching between repositories that intentionally share one working tree;
- keeping separate remotes and Git identities for the same files.

## Important Safety Notes

- Git Rotate changes `.git`, not the files in the working tree.
- Do not switch records with uncommitted changes unless you understand how the
  target record will interpret them.
- A record has its own branches, remotes, hooks, and Git configuration.
- The `.gitrotate` directory is ignored so it does not become part of a record.
- Keep backups before deleting records or performing destructive Git commands.
- Never assume that a commit in one record exists in another record.

## Command Summary

| Command | Purpose |
| --- | --- |
| `git rotate <record>` | Switch to a saved record |
| `git rotate status` | List records and mark the active record |
| `git rotate checkout <record>` | Save the current repository as a new record |
| `git rotate checkout <record> local` | Create a fresh local record |
| `git rotate checkout <record> [origin] <url>` | Create a record using a remote |
| `git rotate delete <record>` | Delete a record |
| `git rotate help` | Show built-in help |

## License

Git Rotate is open source software licensed under the [MIT License](LICENSE).
