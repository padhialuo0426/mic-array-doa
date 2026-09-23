"""Build both A9 applications with Vitis's bundled Python (2025.2).

MIC_BUILD_DIR selects the directory containing top.xsa. MIC_ARM_TOOLCHAIN
optionally selects the directory containing arm-none-eabi-{nm,readelf,objdump}.
"""
import os
from pathlib import Path
import shutil
import subprocess
import re
import zipfile
import xml.etree.ElementTree as ET
import vitis

root=Path(__file__).resolve().parents[1]
out=Path(os.environ['MIC_BUILD_DIR'])
workspace=out/'vitis'
exe_suffix='.exe' if os.name=='nt' else ''

def arm_tools():
    configured=os.environ.get('MIC_ARM_TOOLCHAIN')
    candidates=[]
    if configured:
        candidates.append(Path(configured))
    else:
        located=shutil.which('arm-none-eabi-nm'+exe_suffix)
        if located:candidates.append(Path(located).parent)
        installation=os.environ.get('XILINX_VITIS')
        if installation:
            base=Path(installation)
            for host in ['nt','lin']:
                candidates.append(base/'gnu/aarch32'/host/'gcc-arm-none-eabi/bin')
    for candidate in candidates:
        if all((candidate/f'arm-none-eabi-{name}{exe_suffix}').is_file()
               for name in ['nm','readelf','objdump']):return candidate
    raise RuntimeError('Set MIC_ARM_TOOLCHAIN to the Vitis ARM toolchain bin directory')

tools=arm_tools()
# Refuse a stale XSA without the board's SD pin routing.
with zipfile.ZipFile(out/'top.xsa') as archive:
    hwh=ET.fromstring(archive.read(next(n for n in archive.namelist() if n.endswith('.hwh'))))
    ps=next(m for m in hwh.iter('MODULE') if m.get('MODTYPE')=='processing_system7')
    params={p.get('NAME'):p.get('VALUE') for p in ps.iter('PARAMETER')}
    for name,value in {'PCW_SD0_PERIPHERAL_ENABLE':'1','PCW_SD0_SD0_IO':'MIO 40 .. 45',
                       'PCW_SD0_GRP_CD_ENABLE':'1','PCW_SD0_GRP_CD_IO':'MIO 47',
                       'PCW_SD0_GRP_WP_ENABLE':'0'}.items():
        if params.get(name)!=value:raise RuntimeError(f'SD hardware mismatch: {name}={params.get(name)}')
print('Starting local Vitis build service',flush=True)
client=vitis.create_client(host='127.0.0.1')
try:
    client.set_workspace(str(workspace))
    platform=client.create_platform_component(name='platform',hw_design=str(out/'top.xsa'),
        os='standalone',cpu='ps7_cortexa9_0',domain_name='standalone_a9_0',no_boot_bsp=False)
    cpu1=platform.add_domain(name='standalone_a9_1',cpu='ps7_cortexa9_1',os='standalone')
    cpu1.set_config(option='proc',param='proc_extra_compiler_flags',value='-O2 -g -DUSE_AMP=1')
    table=workspace/'platform/ps7_cortexa9_1/standalone_a9_1/bsp/libsrc/standalone/src/arm/cortexa9/gcc/translation_table.S'
    if not table.exists():platform.build()
    source=table.read_text()
    if '0x15de6' not in source:raise RuntimeError('Unexpected CPU1 translation table; refusing unsafe cache mapping')
    # AMP upstream changes only the first DDR section. Our private image is
    # at 32 MiB: make ALL CPU1 DDR sections inner-cacheable, outer-noncacheable
    # before startup touches code/stack. CPU0 retains exclusive L2 control.
    table.write_text(source.replace('0x15de6','0x14de6'))
    shutil.copy2(table,out/'cpu1_translation_table.S')
    platform.build()
    ninja=table.parents[5]/'build_configs/gen_bsp/build.ninja'
    # Vitis also leaves an earlier compile_commands.json at libsrc/; inspect
    # the generated Ninja rules that actually compile the final BSP.
    rules=ninja.read_text()
    amp_rules=[]
    for source_name in ['boot.S','xil_cache.c']:
        blocks=[b for b in rules.split('\n\n') if b.startswith('build ') and source_name+'.obj:' in b]
        if len(blocks)!=1 or '-DUSE_AMP=1' not in blocks[0]:
            raise RuntimeError(f'CPU1 BSP lacks AMP compilation for {source_name}')
        amp_rules.append(blocks[0])
    (out/'cpu1_bsp_flags.txt').write_text('\n\n'.join(amp_rules)+'\n')
    xpfm=client.find_platform_in_repos('platform')
    app=client.create_app_component(name='mic_demo',platform=xpfm,domain='standalone_a9_0',template='empty_application')
    app.import_files(from_loc=str(root/'sw'/'mic_demo'),files=['main.c','doa.c','doa.h',
        'chirp.c','chirp.h','led_ring.c','led_ring.h','realtime.c','realtime.h',
        'amp_ipc.c','amp_ipc.h','amp_control.c','amp_control.h'],dest_dir_in_cmp='src')
    config=workspace/'mic_demo'/'src'/'UserConfig.cmake'
    with config.open('a') as f:
        f.write('\nlist(APPEND USER_LINK_LIBRARIES m)\nstring(APPEND USER_COMPILE_OPTIONS " -O2 -Wall -Wextra -Wstack-usage=4096")\n')
    app.build()
    display=client.create_app_component(name='display',platform=xpfm,domain='standalone_a9_1',template='empty_application')
    display.import_files(from_loc=str(root/'sw/mic_demo'),files=['radar.c','radar.h','radar_assets.h',
        'video.c','video.h','led_ring.c','led_ring.h','chirp.h','amp_ipc.c','amp_ipc.h'],dest_dir_in_cmp='src')
    display.import_files(from_loc=str(root/'sw/display_core'),files=['main.c'],dest_dir_in_cmp='src')
    ds=workspace/'display/src'
    with (ds/'UserConfig.cmake').open('a') as f:
        f.write('\nlist(APPEND USER_LINK_LIBRARIES m)\nstring(APPEND USER_COMPILE_OPTIONS " -O2 -Wall -Wextra -DUSE_AMP=1 -Wstack-usage=4096")\n')
    linker=ds/'lscript.ld'
    content,n=re.subn(r'(ps7_ddr_0_memory_0\s*:\s*ORIGIN\s*=\s*)0x[\da-fA-F]+,\s*LENGTH\s*=\s*0x[\da-fA-F]+',
                      r'\g<1>0x02000000, LENGTH = 0x01000000',linker.read_text())
    if n!=1:raise RuntimeError('Cannot reserve CPU1 private DDR region')
    linker.write_text(content)
    display.build()
    apps=list((workspace/'mic_demo').rglob('*.elf'))
    fsbls=list((workspace/'platform').rglob('*fsbl*.elf'))
    if not apps or not fsbls:raise RuntimeError(f'Missing ELF: app={apps}, fsbl={fsbls}')
    shutil.copy2(apps[0],out/'app.elf')
    display_elf=list((workspace/'display').rglob('*.elf'))
    if len(display_elf)!=1:raise RuntimeError(f'Expected one CPU1 ELF: {display_elf}')
    shutil.copy2(display_elf[0],out/'display.elf')
    shutil.copy2(fsbls[0],out/'fsbl.elf')
    for name in ['ps7_init.tcl','ps7_init.c','ps7_init.h']:
        matches=list((workspace/'platform').rglob(name))
        if matches:shutil.copy2(matches[0],out/name)
    for name in ['app','display','fsbl']:
        for utility,args,report_suffix in [('nm',['-n'],'symbols.txt'),('readelf',['-h'],'header.txt'),('objdump',['-d'],'disassembly.txt')]:
            with (out/f'{name}_{report_suffix}').open('wb') as f:
                subprocess.run([str(tools/f'arm-none-eabi-{utility}{exe_suffix}'),*args,str(out/f'{name}.elf')],check=True,stdout=f)
    # The boot vector and non-overlapping private memory are part of the AMP ABI.
    for name,low,high in [('app',0x00100000,0x01000000),('display',0x02000000,0x03000000)]:
        header=(out/f'{name}_header.txt').read_text()
        entry=int(re.search(r'Entry point address:\s*(0x[0-9a-fA-F]+)',header)[1],16)
        if entry!=low:raise RuntimeError(f'{name} unexpected entry {entry:#x}')
        segments=subprocess.check_output([str(tools/f'arm-none-eabi-readelf{exe_suffix}'),'-W','-l',str(out/f'{name}.elf')],text=True)
        loads=[line.split() for line in segments.splitlines() if line.strip().startswith('LOAD ')]
        if not loads:raise RuntimeError(f'{name} has no load segments')
        for fields in loads:
            start=int(fields[3],16);end=start+int(fields[5],16)
            if start<low or end>high:raise RuntimeError(f'{name} exceeds private DDR: {start:#x}..{end:#x}')
        (out/f'{name}_segments.txt').write_text(segments)
    if not re.search(r'\bInitSD$',(out/'fsbl_symbols.txt').read_text(),re.M):
        raise RuntimeError('FSBL lacks SD initialization')
    # Verify the final linked CPU1 table (not merely the source) bypasses L2
    # for its private memory from its first instruction after enabling MMU.
    symbols=(out/'display_symbols.txt').read_text()
    match=re.search(r'^([0-9a-fA-F]+)\s+\w\s+MMUTable$',symbols,re.M)
    if not match:raise RuntimeError('CPU1 MMU table symbol missing')
    mmu=int(match[1],16)
    dump=subprocess.check_output([str(tools/f'arm-none-eabi-objdump{exe_suffix}'),'-s',
        f'--start-address={mmu+32*4}',f'--stop-address={mmu+33*4}',str(out/'display.elf')],text=True)
    (out/'cpu1_cache_check.txt').write_text(dump)
    if 'e64d0102' not in dump.lower():raise RuntimeError('CPU1 private DDR is not inner-only cached')
    for name in ['LICENSE','THIRD_PARTY_NOTICES.md']:
        shutil.copy2(root/name,out/name)
    shutil.copytree(root/'licenses',out/'licenses',dirs_exist_ok=True)
    (out/'sd_build_validated.txt').write_text('SD0 MIO40..45 CD47; CPU0=0x00100000; CPU1=0x02000000; AMP cache checked\n')
    print('MIC_SOFTWARE_BUILD_OK')
finally:
    vitis.dispose()
