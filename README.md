# Cesp (Cross-editor sharing-protocol)

A protocol and implementations for live file sharing via a protocol and server
that works across multiple editors and operating systems, intended to be quite
minimal in it's feature set.
Cesp does **not** currently have any sort of methods for preventing data
corruption. You are expected to be sitting with your pal and being vigilant
about any problems. Whether or not such features will be implemented is up
in the air.
Not all editors will work 100% the same, but Cesp should guarantee reasonable
stability.

| Editor | Status |
| ------ | ------- |
| Neovim | Works |
| Emacs  | Works as a client but not host |
| Vscode | Someday |
| Vim    | Possibly someday |

## Installation

### Emacs

Currently `cesp.el` is not in any package repositories, so for the time being you
will have to add this repository as a submodule in your `.emacs.d`.

Assuming you have the repository cloned into `~/.emacs.d/cesp`, you will simply
need to add this to your `init.el` to make Cesp work.

```lisp
(add-to-list 'load-path "~/.emacs.d/cesp/emacs")
(require 'cesp)
```

Currently the only customizable feature is your username, which is simply read
from the variable ´cesp-name´

```lisp
(setq cesp-name "Jaakko Pekka")
```

It can also be changed from the easy customization menu.

### Neovim

Add Cesp with your package manager and then set it up by requiring it and
calling the `setup` function.

```lua
local cesp = require("cesp")
cesp.setup({
    -- Default port to use
    port = 8080
    -- Name displayed to others
    name = "Liitava Pomeranian"
    -- Default cursor styling (extmarks)
	cursor = {
		pos = "eol",
		hl_group = "Cursor",
	},
})
```

## Basic usage

To use Cesp, the host machine should first start up the server via:
```bash
# cesp/server/
go run . -port=8080 -ignore=.vscode,node_modules /path/to/project
```

Following this, usage of Cesp in-editor is generally speaking always the same.

### Emacs

You can use the following commands:

- `cesp-connect-server`: Join a server, either as a host or client.
- `cesp-disconnect`: Disconnect from a Cesp server.
- `list-cesp-files`: List all of the host's files and choose one to open.
- `cesp-get-file`: Directly input the name of a host's file to open.
- `cesp-reload-buffer`: Re-open the current file.
- `cesp-connected-p`: Whether or not your are currently connected to a Cesp
  server.

### Neovim

You can use the following commands:

- `:CespJoin`: Join a session. Defaults to localhost, but you can specify
  the server's address by adding it as an argument (`:CespJoin 123.123.123.123`)
- `:CespLeave`: Leave the session.
- `:CespExplore`: List all of the host's files. If you have the Telescope plugin
  installed this will be much nicer.
