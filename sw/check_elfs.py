"""Checks sw/build.py applies to the Vitis ELFs, for host-built ELFs.

AMP ABI: fixed entries and non-overlapping private DDR, CPU1 DDR mapped
inner-cacheable/outer-noncacheable (L1 only, CPU0 owns L2), an initialized
autostart flag the JTAG loader can clear, and an FSBL that can boot from SD.
Standard library and arm-none-eabi binutils only.
"""
import re
import subprocess
import sys
from pathlib import Path


def tool(name, *args):
    return subprocess.check_output([f'arm-none-eabi-{name}', *args], text=True)


def symbols(elf):
    return {f[2]: (int(f[0], 16), f[1]) for f in (l.split() for l in tool('nm', '-n', str(elf)).splitlines()) if len(f) == 3}


def check(out):
    for name, low, high in [('app', 0x00100000, 0x01000000), ('display', 0x02000000, 0x03000000)]:
        elf = out/f'{name}.elf'
        entry = int(re.search(r'Entry point address:\s*(0x[0-9a-fA-F]+)', tool('readelf', '-h', str(elf)))[1], 16)
        if entry != low:
            raise SystemExit(f'{name}: unexpected entry {entry:#x}')
        for fields in (l.split() for l in tool('readelf', '-W', '-l', str(elf)).splitlines() if l.strip().startswith('LOAD ')):
            start = int(fields[3], 16); end = start+int(fields[5], 16)
            if start < low or end > high:
                raise SystemExit(f'{name}: segment {start:#x}..{end:#x} outside private DDR')
    app = symbols(out/'app.elf')
    if app.get('mic_boot_autostart', (0, ''))[1] not in 'Dd' or 'mic_boot_autostart' not in app:
        raise SystemExit('app: mic_boot_autostart must be initialized data')
    mmu = symbols(out/'display.elf')['MMUTable'][0]
    dump = tool('objdump', '-s', f'--start-address={mmu+32*4}', f'--stop-address={mmu+33*4}', str(out/'display.elf'))
    if 'e64d0102' not in dump.lower():
        raise SystemExit('display: CPU1 private DDR is not inner-only cached')
    if 'InitSD' not in symbols(out/'fsbl.elf'):
        raise SystemExit('fsbl: lacks SD initialization')
    print('ELF checks passed: entries, private DDR, CPU1 L1-only DDR, autostart flag, FSBL InitSD')


if __name__ == '__main__':
    check(Path(sys.argv[1]))
