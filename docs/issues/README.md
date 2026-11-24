Drafts of issues for https://github.com/alpibrusl/cancho. Each one, when fixed, deletes a workaround in this repo.

| | | |
|---|---|---|
| 01 | bare-metal target, `--emit ll` | done: cancho `docs/freestanding.md` |
| 02 | volatile MMIO behind a capability | open: would delete the primitives in `board/boot.S` |
| 03 | runtime with no libc | done: same document; `board/board.c` is gone |
| 04 | entering cancho from an exception | not needed until preemption (milestone 4) |
