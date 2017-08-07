import socket, subprocess, sys, os

sock = socket.socket(socket.AF_UNIX)
sock.connect('/tmp/test-bindfd')
env = dict(os.environ, CONNECT_FD=str(sock.fileno()), LD_PRELOAD='./build/bindfd.so')
sys.exit(subprocess.call(sys.argv[1:], pass_fds=[sock.fileno()], env=env))
