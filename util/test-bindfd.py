import socket, subprocess, sys, os

sock = socket.socket(socket.AF_UNIX)
p = '/tmp/test-bindfd'
if os.path.exists(p): os.unlink(p)
sock.bind(p)
sock.listen(5)
env = dict(os.environ, BIND_FD=str(sock.fileno()), LD_PRELOAD='./build/bindfd.so')
sys.exit(subprocess.call(sys.argv[1:], pass_fds=[sock.fileno()], env=env))
