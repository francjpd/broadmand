#!/usr/bin/env python3
"""Drive a command in a pty, feed it input, capture output, return its status.

Used by tests/popup.test.sh to exercise the interactive popup primitive.
The caller base64-encodes the bytes to send so nothing has to survive shell
quoting.

Usage:
    ptydrive.py --timeout SECONDS [--delay SECONDS] --input BASE64 -- CMD [ARG...]
"""

import argparse
import base64
import os
import pty
import select
import signal
import sys
import time


def parse_args():
    parser = argparse.ArgumentParser()
    parser.add_argument("--timeout", type=float, default=10.0)
    parser.add_argument("--delay", type=float, default=0.4,
                        help="seconds to wait before sending input")
    parser.add_argument("--input", default="")
    parser.add_argument("cmd", nargs=argparse.REMAINDER)
    args = parser.parse_args()
    cmd = args.cmd
    if cmd and cmd[0] == "--":
        cmd = cmd[1:]
    if not cmd:
        parser.error("no command given")
    args.cmd = cmd
    return args


def drain(fd, output):
    """Read whatever is ready without blocking. Returns False on EOF."""
    readable, _, _ = select.select([fd], [], [], 0.05)
    if fd not in readable:
        return True
    try:
        chunk = os.read(fd, 4096)
    except OSError:
        return False
    if not chunk:
        return False
    output.extend(chunk)
    return True


def main():
    args = parse_args()
    data = base64.b64decode(args.input) if args.input else b""

    pid, fd = pty.fork()
    if pid == 0:  # child
        try:
            os.execvp(args.cmd[0], args.cmd)
        finally:
            os._exit(127)

    output = bytearray()
    start = time.time()
    deadline = start + args.timeout
    sent = False
    status = None

    while time.time() < deadline:
        if not sent and (time.time() - start) >= args.delay:
            if data:
                try:
                    os.write(fd, data)
                except OSError:
                    pass
            sent = True
        drain(fd, output)
        wpid, wstatus = os.waitpid(pid, os.WNOHANG)
        if wpid == pid:
            status = wstatus
            break

    if status is None:
        try:
            os.kill(pid, signal.SIGKILL)
        except OSError:
            pass
        _, status = os.waitpid(pid, 0)

    # Collect any final output.
    for _ in range(10):
        if not drain(fd, output):
            break

    sys.stdout.buffer.write(bytes(output))
    sys.stdout.buffer.flush()

    if os.WIFEXITED(status):
        sys.exit(os.WEXITSTATUS(status))
    if os.WIFSIGNALED(status):
        sys.exit(128 + os.WTERMSIG(status))
    sys.exit(1)


if __name__ == "__main__":
    main()
