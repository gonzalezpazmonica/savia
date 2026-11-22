#!/usr/bin/env python3
"""Lanza una orden en una pseudo-terminal DESACOPLADA del árbol de procesos (doble fork + setsid).

Uso: pty-detached.py <fichero-resultado> <entradas separadas por |> <orden...>
Escribe <resultado>.out con la salida y <resultado> con el código de salida.

Es la evasión que SE-498 R6.1 declara como límite de la vía por terminal: sirve a los tests
para ejercer la vía débil sin ancestros que sean ejecutores conocidos.
"""
import os
import pty
import sys
import time

res, inputs, cmd = sys.argv[1], sys.argv[2].split("|"), sys.argv[3:]
if os.fork():
    os.wait()
    sys.exit(0)
os.setsid()
if os.fork():
    os._exit(0)
time.sleep(0.3)  # el padre intermedio ya ha salido: el padre pasa a ser el subreaper o el PID 1
pid, fd = pty.fork()
if pid == 0:
    os.execvp(cmd[0], cmd)
buf = b""
for line in inputs:
    time.sleep(0.4)
    os.write(fd, (line + "\n").encode())
while True:
    try:
        d = os.read(fd, 4096)
    except OSError:
        break
    if not d:
        break
    buf += d
_, st = os.waitpid(pid, 0)
with open(res + ".out", "wb") as f:
    f.write(buf)
with open(res + ".tmp", "w") as f:
    f.write(str(os.waitstatus_to_exitcode(st)))
os.replace(res + ".tmp", res)
