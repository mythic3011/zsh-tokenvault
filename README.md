# TokenVault

Zsh plugin for managing provider API keys, profile-scoped defaults, model selection, and command execution through an encrypted local vault.

## Features

- Loads as a standard `.plugin.zsh` plugin
- Supports oh-my-zsh custom plugin layout
- Splits config, i18n, core logic, auth, prompt rendering, models, and commands into separate modules
- Encrypts stored keys with `openssl`
- Uses `jq` for profile/model state
- Exposes commands such as `tv-add`, `tv-run`, `tv-model-set`, `tv-model-list`, `tv-codex-sync`, `tv-list`, and `tv-help`

## Requirements

- `zsh`
- `jq`
- `openssl`
- `python3`

## Install

### oh-my-zsh

Clone or copy this repository into:

```sh
git clone https://github.com/mythic3011/zsh-tokenvault ${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/plugins/tokenvault
```

Then add `tokenvault` to the `plugins=(...)` list in `.zshrc`.

    ```sh
    plugins=( 
        # other plugins...
        tokenvault
    )
    ```

### Other zsh plugin managers

The plugin entrypoint is:

```sh
tokenvault.plugin.zsh
```

As long as the plugin manager sources that file from the repository root, the internal module loader resolves `lib/` and `commands/` correctly.

## Usage

```sh
tv-help
tv-unlock
tv-add
tv-list
tv-run auto <command>
```

## Development

Run the local build and smoke test:

```sh
./build.sh
```

That script verifies:

- `zsh -n` for the loader and all modules
- oh-my-zsh-style plugin loading from `custom/plugins/tokenvault/tokenvault.plugin.zsh`
- a temp-directory smoke test for `tv-add`
- the real prompt worker path by waiting for `TV_PROMPT_CACHE`
- the functional command flow in `./test.sh`

Run the same verification in Docker:

```sh
./build.sh docker
```

## Repository Layout

```text
tokenvault.plugin.zsh   # plugin entrypoint / loader
lib/                    # shared modules
commands/               # command implementations
build.sh                # local verification script
```
