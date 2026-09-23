"""Volatile JTAG load and finite microphone captures; run with .venv Python."""
import argparse
from datetime import datetime
import glob
from pathlib import Path
import re
import subprocess
import time
import serial

ROOT=Path(__file__).resolve().parents[1]

def port():
    ports=glob.glob('/dev/serial/by-id/usb-Silicon_Labs_CP2102N*')
    if len(ports)!=1:raise RuntimeError(f'Expected one CP2102N UART, found {ports}')
    return ports[0]

def openocd(script,log,timeout=120):
    tcl=log.with_suffix('.tcl')
    tcl.write_text(script+'\nshutdown\n')
    try:
        result=subprocess.run(['openocd','-f',str(ROOT/'scripts/openocd/ax7020.cfg'),'-f',str(tcl)],
            stdout=subprocess.PIPE,stderr=subprocess.STDOUT,text=True,timeout=timeout)
    except subprocess.TimeoutExpired as error:
        output=error.stdout or ''
        if isinstance(output,bytes):output=output.decode('utf-8',errors='replace')
        log.write_text(output+f'\nHOST_TIMEOUT seconds={timeout}\n')
        raise
    log.write_text(result.stdout)
    print(result.stdout,flush=True)
    if result.returncode:raise RuntimeError(f'OpenOCD failed ({result.returncode}): {log}')

def entry(elf):
    text=subprocess.check_output(['arm-none-eabi-readelf','-h',str(elf)],text=True)
    return int(re.search(r'Entry point address:\s*(0x[0-9a-fA-F]+)',text)[1],16)

def fsbl_wait(elf):
    text=subprocess.check_output(['arm-none-eabi-objdump','-d',str(elf)],text=True)
    start=text.index('<FsblHandoffJtagExit>:')
    # Only select the WFE in the actual handoff function. This is after its
    # cache/MMU teardown; do not guess how many milliseconds DDR init needs.
    window=text[start:start+3000]
    match=re.search(r'^\s*([0-9a-f]+):[^\n]*\bwfe\b',window,re.M)
    if not match:raise RuntimeError('FSBL has no recognizable JTAG wait instruction')
    return int(match[1],16)

def manual_boot_override(elf):
    symbols=subprocess.check_output(['arm-none-eabi-nm','-n',str(elf)],text=True)
    match=re.search(r'^([0-9a-fA-F]+)\s+[Dd]\s+mic_boot_autostart$',symbols,re.M)
    if match:return f'mww phys 0x{int(match[1],16):x} 0'
    # Only images without self-start support may skip the override. Otherwise
    # CPU0 would wake CPU1 while the debugger also owns it.
    if re.search(r'\samp_start_secondary$',symbols,re.M):
        raise RuntimeError('ELF can start CPU1 but has no initialized mic_boot_autostart to disable')
    return ''

def load_ranges(elf):
    text=subprocess.check_output(['arm-none-eabi-readelf','-W','-l',str(elf)],text=True)
    ranges=[]
    for line in text.splitlines():
        fields=line.split()
        if fields and fields[0]=='LOAD':
            start=int(fields[3],16);ranges.append((start,start+int(fields[5],16)))
    if not ranges:raise RuntimeError(f'ELF has no loadable segments: {elf}')
    return ranges

def check_layout(app,display):
    # JTAG DCC scratch is independent of both apps, DMA and the IPC section.
    for lo,hi in load_ranges(app):
        if lo<0x100000 or hi>0x01000000:raise RuntimeError('CPU0 ELF exceeds its private low-DDR reservation')
    if display.exists():
        for lo,hi in load_ranges(display):
            if lo<0x02000000 or hi>0x03000000:raise RuntimeError('CPU1 ELF exceeds its private DDR reservation')

def collect(uart,log,timeout=20):
    deadline=time.monotonic()+timeout;output=bytearray()
    while time.monotonic()<deadline:
        block=uart.read(max(1,uart.in_waiting))
        if block:
            output.extend(block)
            print(block.decode('ascii',errors='replace'),end='',flush=True)
            if re.search(rb'READY frames=\d+[^\r\n]*[\r\n]',output):break
    text=output.decode('ascii',errors='replace');log.write_text(text)
    if 'READY ' not in text:raise RuntimeError(f'UART did not reach READY: {log}')
    if 'ERROR ' in text:raise RuntimeError(f'Firmware reported an error: {log}')
    return text

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action',choices=['flash','capture'])
    parser.add_argument('--build',type=Path,default=ROOT/'build/latest')
    parser.add_argument('--seconds',type=int,choices=[1,5,20,60],default=5)
    parser.add_argument('--out',type=Path)
    args=parser.parse_args()
    out=args.out or ROOT/'outputs/hardware'/datetime.now().strftime('%Y%m%d_%H%M%S')
    out.mkdir(parents=True,exist_ok=True)
    with serial.Serial(port(),115200,timeout=.1) as uart:
        uart.reset_input_buffer()
        if args.action=='flash':
            build=args.build.resolve();fsbl=build/'fsbl.elf';app=build/'app.elf';bit=build/'top.bit';display=build/'display.elf'
            for file in [fsbl,app,bit]:
                if not file.is_file():raise FileNotFoundError(file)
            check_layout(app,display)
            cpu1_load=f'echo [load_image {{{display}}}]\necho [verify_image {{{display}}}]' if display.exists() else ''
            stop=fsbl_wait(fsbl)
            openocd(f'''init
targets zynq.cpu1
cortex_a smp off
halt
wait_halt 2000
arm mcr 15 0 1 0 0 0
targets zynq.cpu0
cortex_a smp off
halt
wait_halt 2000
arm mcr 15 0 1 0 0 0
mww phys 0xf8f02100 0
set boot_mode [expr {{[lindex [read_memory 0xf800025c 32 1 phys] 0] & 7}}]
echo "LATCHED_BOOT_MODE=$boot_mode"
if {{$boot_mode==0}} {{
    echo [load_image {{{fsbl}}}]
    bp 0x{stop:x} 4 hw
    resume 0x{entry(fsbl):x}
    wait_halt 15000
    rbp 0x{stop:x}
    echo FSBL_INITIALIZATION_COMPLETE
}} else {{
    echo "Using exported PS7 initialization for non-JTAG boot latch"
    arm mcr 15 0 1 0 0 0
    source {{{build/'ps7_init.tcl'}}}
    source {{{ROOT/'scripts/openocd/ps7_compat.tcl'}}}
    ps7_init
    echo PS7_INITIALIZATION_COMPLETE
}}
echo [pld load 0 {{{bit}}}]
mww 0xf8000008 0xdf0d
mww 0xf8000900 0xf
mww 0xf8000240 0
mww 0xf8000004 0x767b
echo [virtex2 read_stat 0]
echo "FCLK_CTRL=[read_memory 0xf8000170 32 1 phys]"
echo "PL_RESET=[read_memory 0xf8000240 32 1 phys]"
echo "LEVEL_SHIFTERS=[read_memory 0xf8000900 32 1 phys]"
set capture_id [lindex [read_memory 0x43c00020 32 1 phys] 0]
echo "CAPTURE_ID=$capture_id"
if {{$capture_id!=0x4d494331}} {{error "PL register readback mismatch"}}
echo [load_image {{{app}}}]
zynq.cpu0 configure -work-area-phys 0x01000000 -work-area-virt 0x01000000 -work-area-size 0x10000 -work-area-backup 1
echo [verify_image {{{app}}}]
{cpu1_load}
{manual_boot_override(app)}
mww phys 0x12000000 0
resume 0x{entry(app):x}
echo APPLICATION_STARTED''',out/'flash.log')
            collect(uart,out/'uart.log')
            if display.exists():
                # CPU0 has finished SCU/L2 initialization and startup captures.
                # Only now may the AMP secondary start; it never owns shared L2.
                openocd(f'''init
targets zynq.cpu1
cortex_a smp off
halt
wait_halt 2000
arm mcr 15 0 1 0 0 0
resume 0x{entry(display):x}
echo DISPLAY_CPU1_STARTED''',out/'cpu1_start.log')
                time.sleep(1)
                uart.write(b'i');uart.flush()
                status=collect(uart,out/'cpu1_uart.log')
                if not re.search(r'AMP ready=a9010001 core=1\b',status):
                    raise RuntimeError('CPU1 did not report successful display initialization')
        else:
            # A TF-card boot starts chirp streaming, which ignores every command
            # but 'q'. At the READY menu 'q' is ignored and READY is reprinted.
            uart.write(b'q');uart.flush();collect(uart,out/'stop_stream.log',timeout=10)
            uart.reset_input_buffer()
            command,expected_frames={1:(b'c',16384),5:(b'd',81380),20:(b'e',325521),60:(b'm',976563)}[args.seconds]
            uart.write(command);uart.flush()
            text=collect(uart,out/'uart.log',timeout=args.seconds+25)
            match=re.search(r'CAPTURE mode=mic frames=(\d+) bytes=(\d+) addr=(0x[0-9a-f]+)',text)
            if not match:raise RuntimeError('No capture buffer metadata')
            frames,size,address=map(lambda x:int(x,0),match.groups())
            if size!=frames*32 or frames!=expected_frames or address!=0x10000000:
                raise RuntimeError('Unexpected capture metadata')
            binary=(out/'capture.bin').resolve()
            # At roughly 200 KiB/s, a 31 MB minute recording needs longer
            # than the short-capture default. Keep a conservative margin.
            try:
                openocd(f'''init
targets zynq.cpu0
cortex_a smp off
halt
wait_halt 2000
dump_image {{{binary}}} 0x{address:x} {size}
resume''',out/'dump.log',timeout=max(120,size//100000+30))
            except (subprocess.TimeoutExpired,RuntimeError):
                # A killed DCC memory-read helper can leave the core's saved
                # execution context incomplete. Preserve DDR and keep it
                # halted; recover the data, then reload the app before use.
                openocd('init\ntargets zynq.cpu0\ncortex_a smp off\nhalt\nwait_halt 2000',out/'dump_halt.log',timeout=30)
                raise
            if binary.stat().st_size!=size:raise RuntimeError('Truncated JTAG dump')
            print(f'CAPTURE_FILE={binary}')
    print(f'Artifacts: {out.resolve()}')

if __name__=='__main__':main()
