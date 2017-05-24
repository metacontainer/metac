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

proc launchEnv(self: ComputeVmService, envDescription: ProcessEnvironmentDescription): Future[ProcessEnvironment] {.async.} =
  nil

proc launchProcess(self: ProcessEnvironmentImpl, description: ProcessEnvironment): Future[Process] =
  let process = ProcessImpl(instance: self.instance, env: self)

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
