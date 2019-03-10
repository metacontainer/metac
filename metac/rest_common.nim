import metac/sctpstream, sctp, reactor, reactor/unix, metac/os_fs

export sctpstream, sctp

type
  Metadata* = object
    name*: string
