"""Quick diagnostic for lldb attach / breakpoint / memory-read on WeChat.

Loaded into lldb via:  command script import diag_test.py
Run via:              diagtest <pid>

Expected healthy output (WeChat 4.1.11, re-signed, SIP ON):
    ATTACH_OK pid=xxxx
    BP_CCCryptorCreate_locations=1
    READ_OK pc=... bytes=...
    DETACHED
"""
import lldb


def diagtest(debugger, command, result, internal_dict):
    try:
        pid = int(command.split()[0])
    except Exception:
        print("USAGE: diagtest <pid>")
        return
    target = debugger.CreateTarget("")
    err = lldb.SBError()
    process = target.Attach(lldb.SBAttachInfo(pid), err)
    if not err.Success() or not process or not process.IsValid():
        print("ATTACH_FAIL:", err.GetCString())
        return
    print("ATTACH_OK pid=%d" % process.GetProcessID())

    bp = target.BreakpointCreateByName("CCCryptorCreate")
    print("BP_CCCryptorCreate_locations=%d" % bp.GetNumLocations())

    # memory-read self test at the program counter (always a readable code page)
    thread = process.GetSelectedThread()
    if thread.IsValid():
        frame = thread.GetFrameAtIndex(0)
        pc = frame.GetPC()
        data = process.ReadMemory(pc, 16, err)
        if err.Success():
            print("READ_OK pc=%#x bytes=%s" % (pc, bytes(data).hex()))
        else:
            print("READ_FAIL pc=%#x: %s" % (pc, err.GetCString()))
    else:
        print("NO_THREAD")

    process.Detach()
    print("DETACHED")


def __lldb_init_module(debugger, internal_dict):
    debugger.HandleCommand("command script add -f diag_test.diagtest diagtest")
