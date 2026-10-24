"""Writes mods/VoiceWatchdog/durations.tsv: the length of every cue in CueSheet_Voice.

The ACB is compressed inside the paks, so it is read (read-only) from the running game
once it has loaded the voice cue sheet; the title screen is enough. Windows only.
  python scripts/voice-durations.py
"""
import ctypes
import ctypes.wintypes as wt
import os
import struct
import subprocess

SIZES = {0: 1, 1: 1, 2: 2, 3: 2, 4: 4, 5: 4, 6: 8, 7: 8, 8: 4, 9: 8, 0xA: 4, 0xB: 8}
FORMATS = {0: '>B', 1: '>b', 2: '>H', 3: '>h', 4: '>I', 5: '>i', 6: '>Q', 7: '>q', 8: '>f', 9: '>d'}


def utf_table(buf, off):
    """Parses one CRI @UTF table; returns (name, rows)."""
    if buf[off:off + 4] != b'@UTF':
        raise ValueError('no @UTF table at %#x' % off)
    base = off + 8
    _, rows_off, str_off, data_off, name_off, ncol, width, nrow = struct.unpack_from('>HHIIIHHI', buf, base)
    strings, data = base + str_off, base + data_off

    def string(o):
        end = buf.find(b'\0', strings + o)
        return bytes(buf[strings + o:end]).decode('utf-8', 'replace')

    def value(kind, at):
        if kind == 0xA:
            return string(struct.unpack_from('>I', buf, at)[0])
        if kind == 0xB:
            o, n = struct.unpack_from('>II', buf, at)
            return data + o, n
        return struct.unpack_from(FORMATS[kind], buf, at)[0]

    cols, p = [], base + 24
    for _ in range(ncol):
        flags = buf[p]
        name = string(struct.unpack_from('>I', buf, p + 1)[0])
        p += 5
        storage, kind = flags & 0xF0, flags & 0x0F
        const = None
        if storage in (0x30, 0x70):
            const = value(kind, p)
            p += SIZES[kind]
        cols.append((name, storage, kind, const))
    rows = []
    for r in range(nrow):
        at, row = base + rows_off + r * width, {}
        for name, storage, kind, const in cols:
            if storage == 0x50:
                row[name] = value(kind, at)
                at += SIZES[kind]
            else:
                row[name] = const
        rows.append(row)
    return string(name_off), rows


class MemoryInfo(ctypes.Structure):
    _fields_ = [('BaseAddress', ctypes.c_void_p), ('AllocationBase', ctypes.c_void_p), ('AllocationProtect', wt.DWORD),
                ('PartitionId', wt.WORD), ('RegionSize', ctypes.c_size_t), ('State', wt.DWORD),
                ('Protect', wt.DWORD), ('Type', wt.DWORD)]


def game_regions():
    """Yields the readable committed memory regions of the running game."""
    out = subprocess.run(['tasklist', '/FI', 'IMAGENAME eq StarlitSeason-Win64-Shipping.exe', '/FO', 'CSV', '/NH'],
                         capture_output=True, text=True).stdout
    if 'StarlitSeason' not in out:
        raise SystemExit('Start the game first (the title screen is enough).')
    pid = int(out.split('","')[1])
    k32 = ctypes.WinDLL('kernel32', use_last_error=True)
    k32.OpenProcess.restype = ctypes.c_void_p
    k32.VirtualQueryEx.argtypes = [ctypes.c_void_p, ctypes.c_void_p, ctypes.POINTER(MemoryInfo), ctypes.c_size_t]
    k32.ReadProcessMemory.argtypes = [ctypes.c_void_p, ctypes.c_void_p, ctypes.c_void_p, ctypes.c_size_t,
                                      ctypes.POINTER(ctypes.c_size_t)]
    handle = k32.OpenProcess(0x410, False, pid)  # PROCESS_QUERY_INFORMATION | PROCESS_VM_READ
    addr, info = 0, MemoryInfo()
    while k32.VirtualQueryEx(handle, addr, ctypes.byref(info), ctypes.sizeof(info)):
        base, size = info.BaseAddress or 0, info.RegionSize
        if info.State == 0x1000 and not info.Protect & 0x100 and info.Protect & 0xEE and size < 1 << 31:
            buf, done = ctypes.create_string_buffer(size), ctypes.c_size_t()
            if k32.ReadProcessMemory(handle, base, buf, size, ctypes.byref(done)):
                yield buf.raw[:done.value]
        addr = base + size
        if addr >= 0x7FFFFFFFFFFF:
            break


def find_voice_acb():
    """Returns (buffer, header row) of the loaded CueSheet_Voice ACB."""
    for buf in game_regions():
        at = buf.find(b'@UTF')
        while at >= 0:
            if buf.find(b'CueNameTable', at, at + 8192) >= 0:
                try:
                    name, rows = utf_table(buf, at)
                    if name == 'Header' and rows[0].get('Name') == 'CueSheet_Voice' and rows[0]['CueTable'][1]:
                        return buf, rows[0]
                except (ValueError, struct.error, IndexError, KeyError):
                    pass
            at = buf.find(b'@UTF', at + 1)
    raise SystemExit('CueSheet_Voice is not loaded yet; wait for the title screen and retry.')


def main():
    out = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'mods', 'VoiceWatchdog', 'durations.tsv')
    buf, header = find_voice_acb()
    names = utf_table(buf, header['CueNameTable'][0])[1]
    cues = utf_table(buf, header['CueTable'][0])[1]
    rows = sorted((r['CueName'], cues[r['CueIndex']]['Length']) for r in names)
    with open(out, 'w', encoding='ascii', newline='\n') as f:
        f.write('# CueSheet_Voice cue lengths in ms, v1.61 (%d cues). Made by scripts/voice-durations.py\n' % len(rows))
        for name, length in rows:
            f.write('%s\t%d\n' % (name, length))
    print('%d cues -> %s' % (len(rows), os.path.normpath(out)))


if __name__ == '__main__':
    main()
