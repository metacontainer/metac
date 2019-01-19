import xrest, metac/rest_common, metac/net

type
  KernelInterface* = object
    name*: string

restRef NetworkRef:
  sctpStream("packets")

restRef KernelInterfaceRef:
  sub("network", NetworkRef)
  update(KernelInterface)
  get() -> KernelInterface
  delete()

basicCollection(KernelInterface, KernelInterfaceRef)

restRef NetworkNamespaceRef:
  sub(interfaces, KernelInterfaceCollection)
