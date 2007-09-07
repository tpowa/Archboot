# Number of servers to be started up by default
NFSD_OPTS=8

# Options to pass to rpc.mountd
# e.g. MOUNTDOPTS="-p 32767"
MOUNTD_OPTS="--no-nfs-version 1 --no-nfs-version 2"
# Options to pass to rpc.statd
# e.g. STATDOPTS="-p 32765 -o 32766"
STATD_OPTS=""
# Options to pass to rpc.rquotad
# e.g. RQUOTADOPTS="-p 32764"
RQUOTAD_OPTS=""
