import xrest, metac/restcommon

type
  KernelInterface* = object
    name*: string

restRef NetworkRef:
  sctpConnection("packets")

restRef InterfaceRef:
  sub(network, NetworkRef)
  update(KernelInterface)
  get() -> KernelInterface
  delete()

restRef InterfaceCollection:
  collection(InterfaceRef)
  create(InterfaceRef)
  get() -> seq[InterfaceRef]

restRef NetworkNamespaceRef:
  sub(interfaces, InterfaceCollection)
