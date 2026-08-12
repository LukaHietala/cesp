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
