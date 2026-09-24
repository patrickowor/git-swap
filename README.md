# Git Rotate

Git Rotate lets you swap the `.git` folder underneath a project. The working
files stay where they are while the Git history, branches, remotes, and config
change with the selected record.

## Why Would Anyone Want Git Rotate?

Because apparently having one Git history wasn't enough.

- *"I have 4 remotes and I hate all of them."*

    Instead of doing `git remote` yoga every time you want to switch between `fork-a`, `fork-b`, and `upstream`, just rotate the `.git` and boom: new history, same files, no drama.

- *"My repo is possessed."*

    `git fsck` comes back looking like a crime scene report? Don't perform an exorcism. Just swap in a `.git` that isn't cursed and pretend the last one never happened.

- *"I need this exact codebase to lie about where it came from, twice a day, in CI."*

    Testing against staging and prod histories back to back? Rotate, test, rotate, test. It's basically repo cosplay.

- *"We moved platforms and I refuse to re-download 40GB."*

    GitHub to GitLab migration? Keep every byte on disk, just rotate in the new `.git` and let it think it's always lived there.

- *"I have uncommitted changes and a repo the size of a moon."*

    Keep your precious WIP files, attach them to a much smaller, less bloated `.git`. Nobody has to know about the 200,000-commit history you left behind.

- *"I want a 'good' version and a 'chaos' version of the same project."*

    Keep `.git.clean` and `.git.sandbox` around and rotate between them depending on your mood, deadline, or life choices.

- *"I did a history rewrite and I have deep regret."*

    `filter-repo` went sideways? Don't cry. Rotate back to your pre-rewrite backup like it never happened. Instant time travel, no witnesses.

- *"I want to A/B test my hooks without losing my mind."*

    Different hooks, different LFS config, different submodules. Rotate through them on the same files like trying on outfits before a date.

- *"I need read-only mode real quick."*

    Swap from your push-happy fork `.git` to a look-but-don't-touch upstream `.git`. Your WIP stays put, your permissions get humbled.

- *"I `rsync`'d my files and now I need a `.git` real fast."*

    Slap on a shallow `.git` instead of doing a full clone over hotel Wi-Fi. Speed beats completeness.


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
