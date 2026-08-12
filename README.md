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
go run server.go
```

Following this, usage of Cesp in-editor is generally speaking always the same.
The host must be the first person to join the server, after which anyone else
may freely join.

The host should open files via their usual methods, whereas clients can open
files from the host by using a specific Cesp command.

If the host has allowed it, clients can also remotely write files, which works
by simply writing files as usual, as the normal action is overriden in Cesp buffers.

### Emacs

To join the server, either as host or client, use `cesp-connect-server`
To open a file, either use `list-cesp-files` to get an interactive menu, or use
`cesp-get-file` to directly input the file name.

### Neovim

You can use the following commands:

- `:CespJoin`: Join to session. Defaults to localhost, but you can specify
  server's address by adding it as an argument (`:CespJoin 123.123.123.123`)
- `:CespLeave`: Leave the session.
- `:CespExplore`: Lists all host's files. If you have Telescope plugin installed
  this will be much nicer.

