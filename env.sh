# Usage: source env.sh
# RISC-V GCC (same as HW1) plus the local rv32emu.

_hw2_root="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
_repo_root="$(cd "$_hw2_root/../.." && pwd)"

export PATH="$_repo_root/tools/riscv/bin:$_repo_root/tools/gh-2.101.0/bin:$PATH"
export RV32EMU="$_hw2_root/rv32emu/build/rv32emu"
export PLAYGROUND="$_hw2_root/rv32emu/tests/system/playground"

rv32emu() { "$RV32EMU" "$@"; }

# playground-run [-O0|-O2]
# Rebuilds the gist tests and runs them on the local emulator.
playground-run() {
    local opt="${1:--O0}"
    make -C "$PLAYGROUND" clean
    make -C "$PLAYGROUND" OPT="$opt" run
}

unset _hw2_root _repo_root
