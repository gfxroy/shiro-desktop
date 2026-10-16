import Foundation

public struct VMInfo: Identifiable {
    public let name: String
    public let status: String
    public let type: String
    public let safe: Bool
    public var id: String { name }
}

public final class VirtualMachine {
    public init() {}
    public var executable: String? { ProcessRunner.locate("limactl") }
    private func cli() throws -> String {
        guard let executable else { throw ShiroError("Lima is required. Install it from Computer setup.") }; return executable
    }
    public func inventory() async throws -> [VMInfo] {
        let result = try await ProcessRunner.checked(cli(), ["list", "--json"])
        return try result.split(separator: "\n").map { line in
            let data = try JSON.parse(String(line)), config = data["config"]
            let validMounts = config["mounts"] == .null || { if case .array(let mounts) = config["mounts"] { return mounts.isEmpty }; return false }()
            let safe = !config.object.isEmpty && validMounts && config["ssh"]["forwardAgent"].bool == false && config["ssh"]["loadDotSSHPubKeys"].bool == false
            return VMInfo(name: data["name"].string ?? "", status: data["status"].string ?? "Unknown", type: data["vmType"].string ?? "", safe: safe)
        }.filter { !$0.name.isEmpty }
    }
    public func validate(_ name: String) throws {
        guard name.range(of: #"^[a-zA-Z0-9][a-zA-Z0-9_-]{0,80}$"#, options: .regularExpression) != nil else { throw ShiroError("Invalid VM name.") }
    }
    public func start(_ name: String) async throws { try validate(name); _ = try await ProcessRunner.checked(cli(), ["start", "--tty=false", name], timeout: 240) }
    public func stop(_ name: String) async throws { try validate(name); _ = try await ProcessRunner.checked(cli(), ["stop", name], timeout: 60) }
    public func create(name: String, yaml: URL) async throws {
        try validate(name)
        let fs = try FileManager.default.attributesOfFileSystem(forPath: NSHomeDirectory())
        guard (fs[.systemFreeSize] as? NSNumber)?.int64Value ?? 0 > 5 * 1024 * 1024 * 1024 else { throw ShiroError("At least 5 GB of free Mac disk space is required to create Shiro's VM. Free space or attach an existing VM.") }
        _ = try await ProcessRunner.checked(cli(), ["start", "--tty=false", "--name", name, yaml.path], timeout: 900)
    }
    public func install(name: String, script: Data) async throws {
        try validate(name)
        let info = try await inventory().first { $0.name == name }
        guard let info, info.safe, info.type == "vz" else { throw ShiroError("Choose a VZ VM without host mounts or forwarded SSH credentials. Shiro will not run agent commands in a VM with host access.") }
        // The installer is fixed application code. Model-generated code is never used here.
        let installer = """
        import base64, pathlib, subprocess
        for command in ['Xvfb', 'openbox', 'xdotool', 'scrot', 'chromium']:
            import shutil
            if not shutil.which(command): raise RuntimeError('Missing '+command+'. Use a Shiro VM template or install the desktop dependencies first.')
        import websocket
        import importlib.util,os
        if any(importlib.util.find_spec(module) is None for module in ['reportlab','openpyxl','docx']):
            environment=dict(os.environ, DEBIAN_FRONTEND='noninteractive')
            subprocess.run(['apt-get','update','-qq'],check=True,env=environment)
            subprocess.run(['apt-get','install','-y','--no-install-recommends','python3-reportlab','python3-openpyxl','python3-docx','poppler-utils'],check=True,env=environment)
        subprocess.run(['useradd', '-m', '-s', '/bin/bash', 'shiro-local'], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        root=pathlib.Path('/opt/shiro-local'); root.mkdir(exist_ok=True)
        (root/'guest.py').write_bytes(base64.b64decode('\(script.base64EncodedString())'))
        (root/'guest.py').chmod(0o755)
        subprocess.run(['install', '-d', '-o', 'shiro-local', '-g', 'shiro-local', '/home/shiro-local/workspace', '/home/shiro-local/.config'], check=True)
        unit='''[Unit]
        Description=Shiro local desktop
        After=network.target
        [Service]
        User=shiro-local
        Environment=HOME=/home/shiro-local
        Environment=DISPLAY=:88
        ExecStart=/usr/bin/xvfb-run -n 88 -f /home/shiro-local/.Xauthority -s "-screen 0 1280x800x24 -nolisten tcp" /usr/bin/dbus-run-session /usr/bin/openbox-session
        Restart=always
        [Install]
        WantedBy=multi-user.target
        '''
        pathlib.Path('/etc/systemd/system/shiro-local-desktop.service').write_text(unit)
        subprocess.run(['systemctl', 'daemon-reload'], check=True)
        subprocess.run(['systemctl', 'enable', '--now', 'shiro-local-desktop'], check=True)
        print('Shiro desktop installed')
        """
        _ = try await ProcessRunner.checked(cli(), ["shell", name, "--", "sudo", "python3", "-c", installer], timeout: 240)
    }
    public func perform(name: String, tool: String, arguments: JSON) async throws -> JSON {
        try validate(name)
        guard ToolDefinition.all.contains(where: { $0.name == tool && !["remember", "context", "bots", "memory_search", "memory_read", "memory_facts", "cv_create"].contains(tool) }) || tool == "health" || tool == "export" else { throw ShiroError("Unknown VM tool: \(tool)") }
        let payload = try JSON.object(["tool": .string(tool), "arguments": arguments]).data().base64EncodedString()
        let stdout = try await ProcessRunner.checked(cli(), ["shell", name, "--", "sudo", "-u", "shiro-local", "env", "HOME=/home/shiro-local", "DISPLAY=:88", "XAUTHORITY=/home/shiro-local/.Xauthority", "python3", "/opt/shiro-local/guest.py", payload], timeout: 65)
        return try JSON.parse(stdout.trimmingCharacters(in: .whitespacesAndNewlines))
    }
}

extension VirtualMachine {
    public func importFile(_ file: URL, name: String, registeredPath: String? = nil) async throws -> ChatFile {
        try validate(name)
        let info = try await inventory().first { $0.name == name }
        guard info?.safe == true, info?.status == "Running" else { throw ShiroError("Connect the isolated local computer before attaching files.") }
        let properties = try file.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        guard properties.isRegularFile == true, properties.isSymbolicLink != true, let size = properties.fileSize, size <= 32 * 1024 * 1024 else { throw ShiroError("Choose a regular file under 32 MB. Folders and symlinks are not attachments.") }
        let token = UUID().uuidString.lowercased()
        let filename = file.lastPathComponent.replacingOccurrences(of: #"[^\p{L}\p{N}._ -]"#, with: "_", options: .regularExpression)
        let destination = registeredPath ?? "attachments/" + token + "/" + filename
        guard AttachmentCache.accepts(destination), URL(fileURLWithPath: destination).lastPathComponent == filename else { throw ShiroError("Use an exact registered attachment path with the same filename.") }
        let staging = "/tmp/shiro-attachment-" + token
        _ = try await ProcessRunner.checked(cli(), ["copy", file.path, name + ":" + staging], timeout: 90)
        let args = JSON.object(["source": .string(staging), "path": .string(destination), "restore": .bool(registeredPath != nil)]).text
        let script = """
        import json,pathlib,shutil,subprocess
        a=json.loads(\(String(reflecting: args)))
        root=pathlib.Path('/home/shiro-local/workspace').resolve(); target=root/a['path']; source=pathlib.Path(a['source'])
        try:
            if source.is_symlink() or not source.is_file() or source.stat().st_size>33554432: raise ValueError('Invalid staged attachment')
            target.parent.mkdir(parents=True,exist_ok=True)
            if not target.parent.resolve().is_relative_to(root) or target.is_symlink(): raise ValueError('Unsafe attachment destination')
            if not (a['restore'] and target.exists()): shutil.copyfile(source,target)
            subprocess.run(['chown','-R','shiro-local:shiro-local',str(root/'attachments'/target.parent.name)],check=True)
        finally:
            source.unlink(missing_ok=True)
        """
        _ = try await ProcessRunner.checked(cli(), ["shell", name, "--", "sudo", "python3", "-c", script], timeout: 65)
        return ChatFile(path: destination, name: file.lastPathComponent, bytes: size)
    }
}
