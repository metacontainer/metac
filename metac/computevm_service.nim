# Implements the ComputeLauncher using VMLauncher.
import reactor, caprpc, capnp, metac/schemas, metac/instance, metac/persistence

type
  ComputeVmService = ref object of RootObj
    instance: ServiceInstance
    launcher: VMLauncher

  ProcessEnvironmentImpl = ref object of RootObj
    instance: ServiceInstance
    vm: VM

  ProcessImpl = ref object of RootObj
    instance: ServiceInstance
    env: ProcessEnvironmentImpl

proc file(self: ProcessImpl, index: uint32): Future[Stream] {.async.} =
  discard

proc kill(self: ProcessImpl, signal: uint32): Future[void] {.async.} =
  discard

proc returnCode(self: ProcessImpl, ): Future[int32] {.async.} =
  discard

proc wait(self: ProcessImpl, ): Future[void] {.async.} =
  discard

capServerImpl(ProcessImpl, [Process])

proc launchProcess(self: ProcessEnvironmentImpl, processDescription: ProcessDescription): Future[Process] {.async.} =
  discard

proc network(self: ProcessEnvironmentImpl, index: uint32): Future[L2Interface] {.async.} =
  discard

capServerImpl(ProcessEnvironmentImpl, [ProcessEnvironment])

proc launchEnv(self: ComputeVmService, envDescription: ProcessEnvironmentDescription): Future[ProcessEnvironment] {.async.} =
  let env = ProcessEnvironmentImpl(instance: self.instance)

  return env.asProcessEnvironment

proc launchProcess(self: ProcessEnvironmentImpl, description: ProcessEnvironment): Future[Process] {.async.} =
  let process = ProcessImpl(instance: self.instance, env: self)

  return process.asProcess

proc launch(self: ComputeVmService, processDescription: ProcessDescription,
            envDescription: ProcessEnvironmentDescription): Future[ComputeLauncher_launch_Result] {.async.} =
  let env = await self.launchEnv(envDescription)
  let process = await env.launchProcess(processDescription)
  return ComputeLauncher_launch_Result(process: process, env: env)

capServerImpl(ComputeVmService, [ComputeLauncher])

proc main*() {.async.} =
  let instance = await newServiceInstance("computevm")

  let vmLauncher = await instance.getServiceAdmin("vm", VMServiceAdmin).getLauncher
  let serviceImpl = ComputeVmService(instance: instance, launcher: vmLauncher)
  let serviceAdmin = serviceImpl.asComputeLauncher

  await instance.registerRestorer(
    proc(d: CapDescription): Future[AnyPointer] =
      case d.category:
      else:
        return error(AnyPointer, "unknown category"))


  await instance.runService(
    service=Service.createFromCap(nothingImplemented),
    adminBootstrap=serviceAdmin.castAs(ServiceAdmin)
  )

when isMainModule:
  main().runMain()
