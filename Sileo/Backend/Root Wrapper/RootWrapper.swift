import Foundation
import Darwin

#if targetEnvironment(macCatalyst)
final public class MacRootWrapper {

    static let shared = MacRootWrapper()
    let sharedPipe = AptRootPipeWrapper()

    public var connection: NSXPCConnection?
    private var invalidated = false
    public var helper: RootHelperProtocol?
    public var wrapperClass: LaunchAsRoot.Type

    init() {
        guard let bundleURL = Bundle.main.builtInPlugInsURL?.appendingPathComponent("SileoRootWrapper.bundle"),
              let bundle = Bundle(url: bundleURL),
              bundle.load(),
              let klass = objc_getClass("LaunchAsRoot") as? LaunchAsRoot.Type
        else {
            fatalError("Unable to initialize ability to spawn a process as root")
        }

        self.wrapperClass = klass
        _ = klass.shared
        func connect() {
            if !connectToDaemon() {
                klass.shared.installDaemon()
                guard connectToDaemon() else {
                    fatalError("[Sileo] Authorization Alpha-Alpha 3-0-5.")
                }
            }
        }
        connect()

        guard let helper = helper else { fatalError("[Sileo] Protocol 3: Protect the Pilot") }
        helper.version { version in
            guard version == DaemonVersion else {
                self.connection?.invalidationHandler = nil
                self.connection?.invalidate()

                klass.shared.installDaemon()
                guard self.connectToDaemon() else {
                    fatalError("[Sileo] Authorization Alpha-Alpha 3-0-5.")
                }
                return
            }
        }
    }

    public func spawn(args: [String], outputCallback: ((_ output: String?) -> Void)? = nil) -> (Int, String, String) {
        guard !args.isEmpty,
              let launchPath = args.first
        else {
            fatalError("Found invalid args when spawning a process as root")
        }

        var arguments = args
        arguments.removeFirst()

        var status = -1
        var stdoutStr = ""
        var stderrStr = ""

        guard let helper = helper else {
            fatalError("[Sileo] Protocol 3: Protect the Pilot")
        }
        // swiftlint:disable identifier_name
        helper.spawn(command: launchPath, args: args) { _status, _stdoutStr, _stderrStr in
            status = _status
            stdoutStr = _stdoutStr
            stderrStr = _stderrStr
        }
        return (status, stdoutStr, stderrStr)
    }

    public func connectToDaemon() -> Bool {
        guard self.connection == nil,
              let connection = wrapperClass.shared.connection(),
              self.helper == nil else { return true }
        connection.remoteObjectInterface = NSXPCInterface(with: RootHelperProtocol.self)
        connection.exportedInterface = NSXPCInterface(with: AptRootPipeProtocol.self)
        connection.exportedObject = sharedPipe
        connection.invalidationHandler = {
            self.invalidated = true
        }

        connection.resume()

        guard let helper = connection.synchronousRemoteObjectProxyWithErrorHandler({ _ in
            return
        }) as? RootHelperProtocol else {
            return false
        }
        var version = ""
        helper.version { _version in
            version = _version
        }
        guard version == DaemonVersion else {
            return false
        }
        self.connection = connection
        self.helper = helper
        return true
    }
    
    public func resetConnection() {
        self.connection?.invalidate()
        self.connection = nil
        self.helper = nil
        
        guard connectToDaemon() else {
            fatalError("[Sileo] Authorization Alpha-Alpha 3-0-5.")
        }
    }
}
#endif

@discardableResult func spawn(command: String, args: [String], root: Bool = false) -> (Int, String, String) {
    var pipestdout: [Int32] = [0, 0]
    var pipestderr: [Int32] = [0, 0]

    let bufsiz = Int(BUFSIZ)

    pipe(&pipestdout)
    pipe(&pipestderr)

    guard fcntl(pipestdout[0], F_SETFL, O_NONBLOCK) != -1 else {
        return (-1, "", "")
    }
    guard fcntl(pipestderr[0], F_SETFL, O_NONBLOCK) != -1 else {
        return (-1, "", "")
    }

    var fileActions: posix_spawn_file_actions_t?
    posix_spawn_file_actions_init(&fileActions)
    defer { posix_spawn_file_actions_destroy(&fileActions) }
    posix_spawn_file_actions_addclose(&fileActions, pipestdout[0])
    posix_spawn_file_actions_addclose(&fileActions, pipestderr[0])
    posix_spawn_file_actions_adddup2(&fileActions, pipestdout[1], STDOUT_FILENO)
    posix_spawn_file_actions_adddup2(&fileActions, pipestderr[1], STDERR_FILENO)
    posix_spawn_file_actions_addclose(&fileActions, pipestdout[1])
    posix_spawn_file_actions_addclose(&fileActions, pipestderr[1])

    let argv: [UnsafeMutablePointer<CChar>?] = args.map { $0.withCString(strdup) }
    defer { for case let arg? in argv { free(arg) } }

    var pid: pid_t = 0

    #if targetEnvironment(macCatalyst)
    let env = [ "PATH=/opt/procursus/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin" ]
    let proenv: [UnsafeMutablePointer<CChar>?] = env.map { $0.withCString(strdup) }
    defer { for case let pro? in proenv { free(pro) } }
    let spawnStatus = posix_spawn(&pid, command, &fileActions, nil, argv + [nil], proenv + [nil])
    #else
    // Weird problem with a weird workaround
    let env = [ "PATH=/usr/bin:/rootfs/usr/bin:/usr/local/bin:/rootfs/usr/local/bin:/bin:/rootfs/bin:/usr/sbin:/rootfs/usr/sbin", "LANG=C" ] //the output JSON of apt may be localized so that sileo can't parse, here we forece set it to en_US.UTF-8
    let envp: [UnsafeMutablePointer<CChar>?] = env.map { $0.withCString(strdup) }
    defer { for case let env? in envp { free(env) } }
    
    let spawnStatus: Int32
    if #available(iOS 13, *) {
        if root {
            var attr: posix_spawnattr_t?
            posix_spawnattr_init(&attr)
            defer { posix_spawnattr_destroy(&attr) }
            posix_spawnattr_set_persona_np(&attr, 99, UInt32(POSIX_SPAWN_PERSONA_FLAGS_OVERRIDE))
            posix_spawnattr_set_persona_uid_np(&attr, 0)
            posix_spawnattr_set_persona_gid_np(&attr, 0)
            spawnStatus = posix_spawn(&pid, command, &fileActions, &attr, argv + [nil], envp + [nil])
        } else {
            spawnStatus = posix_spawn(&pid, command, &fileActions, nil, argv + [nil], envp + [nil])
        }
    } else {
        spawnStatus = posix_spawn(&pid, command, &fileActions, nil, argv + [nil], envp + [nil])
    }
    #endif
    NSLog("SileoLog: spawn \(command) with \(args)")
    if spawnStatus != 0 {
        NSLog("SileoLog: spawn error=\(spawnStatus),\(String(cString: strerror(spawnStatus)))")
        return (Int(spawnStatus), "ITS FAILING HERE", "Error = \(String(cString: strerror(spawnStatus)))\n\(command)")
    }

    close(pipestdout[1])
    close(pipestderr[1])

    var stdoutStr = ""
    var stderrStr = ""

    let mutex = DispatchSemaphore(value: 0)

    let readQueue = DispatchQueue(label: "org.coolstar.sileo.command",
                                  qos: .userInitiated,
                                  attributes: .concurrent,
                                  autoreleaseFrequency: .inherit,
                                  target: nil)

    let stdoutSource = DispatchSource.makeReadSource(fileDescriptor: pipestdout[0], queue: readQueue)
    let stderrSource = DispatchSource.makeReadSource(fileDescriptor: pipestderr[0], queue: readQueue)

    stdoutSource.setCancelHandler {
        close(pipestdout[0])
        mutex.signal()
    }
    stderrSource.setCancelHandler {
        close(pipestderr[0])
        mutex.signal()
    }

    stdoutSource.setEventHandler {
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufsiz)
        defer { buffer.deallocate() }

        let bytesRead = read(pipestdout[0], buffer, bufsiz)
        guard bytesRead > 0 else {
            if bytesRead == -1 && errno == EAGAIN {
                return
            }

            stdoutSource.cancel()
            return
        }

        let array = Array(UnsafeBufferPointer(start: buffer, count: bytesRead)) + [UInt8(0)]
        array.withUnsafeBufferPointer { ptr in
            let str = String(cString: unsafeBitCast(ptr.baseAddress, to: UnsafePointer<CChar>.self))
            NSLog("SileoLog: stdout=\(str)")
            stdoutStr += str
        }
    }
    stderrSource.setEventHandler {
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufsiz)
        defer { buffer.deallocate() }

        let bytesRead = read(pipestderr[0], buffer, bufsiz)
        guard bytesRead > 0 else {
            if bytesRead == -1 && errno == EAGAIN {
                return
            }

            stderrSource.cancel()
            return
        }

        let array = Array(UnsafeBufferPointer(start: buffer, count: bytesRead)) + [UInt8(0)]
        array.withUnsafeBufferPointer { ptr in
            let str = String(cString: unsafeBitCast(ptr.baseAddress, to: UnsafePointer<CChar>.self))
            NSLog("SileoLog: stderr=\(str)")
            stderrStr += str
        }
    }

    stdoutSource.resume()
    stderrSource.resume()

    mutex.wait()
    mutex.wait()
    var status: Int32 = 0
    waitpid(pid, &status, 0)

    return (Int(status), stdoutStr, stderrStr)
}

@discardableResult func spawnAsRoot(args: [String], platformatise: Bool = false, outputCallback: ((_ output: String?) -> Void)? = nil) -> (Int, String, String) {
    #if targetEnvironment(simulator) || TARGET_SANDBOX
    fatalError("Commands should not be run in sandbox")
    #elseif targetEnvironment(macCatalyst)
    MacRootWrapper.shared.spawn(args: args, outputCallback: outputCallback)
    #else
    if #available(iOS 13, *) {
        var args = args
        let command = args.first!
        args[0] = String(command.split(separator: "/").last!)
        return spawn(command:command, args: args, root: true)
    } else {
        guard let giveMeRootPath = Bundle.main.path(forAuxiliaryExecutable: "giveMeRoot") else {
            return (-1, "", "")
        }
        return spawn(command: giveMeRootPath, args: ["giveMeRoot"] + args)
    }
    #endif
}

func deleteFileAsRoot(_ url: URL) {
    NSLog("SileoLog: deleteFileAsRoot \(url)")
//    Thread.callStackSymbols.forEach{NSLog("SileoLog: operationList callstack=\($0)")}

    guard FileManager.default.fileExists(atPath: url.path) else {return}
    #if targetEnvironment(simulator) || TARGET_SANDBOX
    try? FileManager.default.removeItem(at: url)
    #else
    spawnAsRoot(args: [CommandPath.rm, "-rf", rootfs("\(url.path)")])
    #endif
}

func hardLinkAsRoot(from: URL, to: URL) {
    //this may cause the file status to be out of sync with `ln`, and `ln -f` command will automatically overwrite the target file
//    deleteFileAsRoot(to)

    #if targetEnvironment(simulator) || TARGET_SANDBOX
    try? FileManager.default.createSymbolicLink(at: to, withDestinationURL: from)
    #else
    spawnAsRoot(args: [CommandPath.ln, "-f", rootfs("\(from.path)"), rootfs("\(to.path)")])
    spawnAsRoot(args: [CommandPath.chown, "0:0", rootfs("\(to.path)")])
    spawnAsRoot(args: [CommandPath.chmod, "0644", rootfs("\(to.path)")])
    #endif
}

func moveFileAsRoot(from: URL, to: URL) {
    //this may cause the file status to be out of sync with `mv`, and `mv` will automatically overwrite the target file
//    deleteFileAsRoot(to)

    #if targetEnvironment(simulator) || TARGET_SANDBOX
    try? FileManager.default.moveItem(at: from, to: to)
    #else
    // /var/mobile/Library/Caches/Sileo/Downloads/CFNetworkDownload_*.tmp
    if let attributes = try? FileManager.default.attributesOfItem(atPath: from.path),
       let permissions = attributes[.posixPermissions] as? NSNumber {
        NSLog("SileoLog: moveFileAsRoot perm=\(String(format:"%o", permissions.intValue)) from \(from) to \(to)")
        if permissions.intValue == 0o600 {
            spawnAsRoot(args: [CommandPath.chmod, "0666", rootfs("\(from.path)")])
        }
    }

    spawnAsRoot(args: [CommandPath.mv, rootfs("\(from.path)"), rootfs("\(to.path)")])
    spawnAsRoot(args: [CommandPath.chown, "0:0", rootfs("\(to.path)")])
    spawnAsRoot(args: [CommandPath.chmod, "0644", rootfs("\(to.path)")])
    #endif
}

