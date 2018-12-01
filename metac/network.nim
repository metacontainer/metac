import xrest, metac/rest_common, metac/net

type
  KernelInterface* = object
    name*: string

restRef NetworkRef:
  sctpStream("packets")

restRef InterfaceRef:
  sub("network", NetworkRef)
  update(KernelInterface)
  get() -> KernelInterface
  delete()

basicCollection(KernelInterface, InterfaceRef)

restRef NetworkNamespaceRef:
  sub(interfaces, KernelInterfaceCollection)
