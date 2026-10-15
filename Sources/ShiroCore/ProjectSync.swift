import Foundation

public enum ProjectSync {
    public static func archive(folder: URL, destination: URL) async throws -> Int {
        let root = folder.resolvingSymlinksInPath().standardizedFileURL
        guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey], options: [.skipsHiddenFiles]) else { throw ShiroError("Cannot read the linked folder.") }
        var names: [String] = [], bytes = 0
        while let url = enumerator.nextObject() as? URL {
            if ["node_modules", "venv", "dist", "build", "__pycache__"].contains(url.lastPathComponent) { enumerator.skipDescendants(); continue }
            let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
            if values.isSymbolicLink == true { enumerator.skipDescendants(); continue }
            guard values.isRegularFile == true else { continue }
            guard (values.fileSize ?? 0) <= 10_000_000 else { throw ShiroError("\(url.lastPathComponent) exceeds the 10 MB sync limit. Choose a smaller project folder.") }
            bytes += values.fileSize ?? 0
            guard names.count < 1000, bytes <= 50_000_000 else { throw ShiroError("Sync supports up to 1000 files / 50 MB. Link a focused project folder.") }
            let resolved = url.resolvingSymlinksInPath().standardizedFileURL.path
            guard resolved.hasPrefix(root.path + "/") else { throw ShiroError("A project file escapes its linked folder.") }
            names.append(String(resolved.dropFirst(root.path.count + 1)))
        }
        let list = destination.appendingPathExtension("list")
        try Data((names.joined(separator: "\0") + (names.isEmpty ? "" : "\0")).utf8).write(to: list)
        defer { try? FileManager.default.removeItem(at: list) }
        _ = try await ProcessRunner.checked("/usr/bin/env", ["COPYFILE_DISABLE=1", "/usr/bin/tar", "-cf", destination.path, "-C", root.path, "--null", "-T", list.path], timeout: 60)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: destination.path)
        return names.count
    }
    public static func push(project: Project, vm: VirtualMachine, name: String) async throws -> Int {
        guard let folder = project.linkedFolder, let cli = vm.executable else { throw ShiroError("Link a Mac folder and connect the computer first.") }
        try vm.validate(name)
        let archive = FileManager.default.temporaryDirectory.appendingPathComponent("shiro-\(UUID()).tar")
        defer { try? FileManager.default.removeItem(at: archive) }
        let count = try await self.archive(folder: URL(fileURLWithPath: folder), destination: archive)
        let remote = "/tmp/shiro-project-\(UUID()).tar"
        _ = try await ProcessRunner.checked(cli, ["copy", archive.path, name + ":" + remote], timeout: 90)
        // Lima copies as its login user; the fixed broker transfers it to the
        // unprivileged Shiro user before extraction into the project directory.
        let script = """
        import tarfile, pathlib, sys, os, shutil
        source=pathlib.Path(sys.argv[1]); target=pathlib.Path('/home/shiro-local/workspace')/sys.argv[2]
        base=pathlib.Path('/home/shiro-local/workspace')
        if base.is_symlink() or not target.resolve().is_relative_to(base) or target.parent.is_symlink(): raise ValueError('Project path escapes workspace')
        target.mkdir(parents=True,exist_ok=True)
        if target.is_symlink(): raise ValueError('Project directory cannot be a symlink')
        with tarfile.open(source) as t:
            for m in t.getmembers():
                p=target/m.name
                if not m.isfile() or not p.resolve().is_relative_to(target.resolve()): raise ValueError('Unsafe archive entry')
                p.parent.mkdir(parents=True,exist_ok=True)
                if p.is_symlink(): raise ValueError('Target file is a symlink')
                with t.extractfile(m) as r, p.open('wb') as w: shutil.copyfileobj(r,w)
                os.chown(p, int(sys.argv[3]), int(sys.argv[4]))
        source.unlink()
        print('Synced')
        """
        // UID/GID are resolved inside the guest rather than assumed.
        let wrapper = "import pwd,sys,subprocess; u=pwd.getpwnam('shiro-local'); subprocess.run(['python3','-c',sys.argv[1],sys.argv[2],sys.argv[3],str(u.pw_uid),str(u.pw_gid)],check=True); subprocess.run(['chown','-hR','shiro-local:shiro-local','/home/shiro-local/workspace/'+sys.argv[3]],check=True)"
        _ = try await ProcessRunner.checked(cli, ["shell", name, "--", "sudo", "python3", "-c", wrapper, script, remote, project.workspacePath], timeout: 90)
        return count
    }
    public static func pull(project: Project, vm: VirtualMachine, name: String) async throws {
        guard let folder = project.linkedFolder, let cli = vm.executable else { throw ShiroError("Link a Mac folder first.") }
        try vm.validate(name)
        let archive = FileManager.default.temporaryDirectory.appendingPathComponent("shiro-pull-\(UUID()).tar")
        let remote = "/tmp/shiro-pull-\(UUID()).tar"
        defer { try? FileManager.default.removeItem(at: archive) }
        let script = """
        import pathlib,tarfile,sys
        root=pathlib.Path('/home/shiro-local/workspace')/sys.argv[1]
        base=pathlib.Path('/home/shiro-local/workspace')
        if not root.is_dir() or root.is_symlink() or base.is_symlink() or not root.resolve().is_relative_to(base): raise ValueError('Project is not a regular workspace folder')
        files=[p for p in root.rglob('*') if p.is_file() and not p.is_symlink() and p.resolve().is_relative_to(root.resolve()) and not any(x.startswith('.') for x in p.relative_to(root).parts)]
        if len(files)>1000 or sum(p.stat().st_size for p in files)>50000000: raise ValueError('Project exceeds sync limits')
        with tarfile.open(sys.argv[2],'w') as t:
            for p in files: t.add(p,arcname=str(p.relative_to(root)),recursive=False)
        """
        _ = try await ProcessRunner.checked(cli, ["shell", name, "--", "sudo", "-u", "shiro-local", "python3", "-c", script, project.workspacePath, remote], timeout: 90)
        _ = try await ProcessRunner.checked(cli, ["copy", name + ":" + remote, archive.path], timeout: 90)
        try await restore(archive: archive, folder: URL(fileURLWithPath: folder))
        _ = try? await ProcessRunner.checked(cli, ["shell", name, "--", "rm", "--", remote], timeout: 10)
    }
    public static func restore(archive: URL, folder: URL) async throws {
        guard let python = ProcessRunner.locate("python3") else { throw ShiroError("Python 3 is required for project sync.") }
        let script = """
        import pathlib,tarfile,sys,shutil,time
        root=pathlib.Path(sys.argv[2]).resolve(); backup=root/'.shiro-backups'/str(time.time_ns())
        if not root.is_dir(): raise ValueError('Linked folder is missing')
        if backup.parent.is_symlink() or not backup.resolve().is_relative_to(root): raise ValueError('Unsafe backup directory')
        with tarfile.open(sys.argv[1]) as t:
            members=t.getmembers()
            if len(members)>1000 or sum(m.size for m in members)>50000000: raise ValueError('Archive exceeds limits')
            targets=[]
            for m in members:
                parts=pathlib.PurePosixPath(m.name).parts
                p=root/m.name
                if not m.isfile() or not parts or any(x.startswith('.') for x in parts) or not p.resolve().is_relative_to(root) or p.is_symlink(): raise ValueError('Unsafe project archive path: '+m.name)
                targets.append((m,p))
            for m,p in targets:
                if p.exists():
                    b=backup/m.name; b.parent.mkdir(parents=True,exist_ok=True); shutil.copy2(p,b)
                p.parent.mkdir(parents=True,exist_ok=True)
                with t.extractfile(m) as r, p.open('wb') as w: shutil.copyfileobj(r,w)
        print('Saved to linked folder; overwritten originals backed up in .shiro-backups')
        """
        _ = try await ProcessRunner.checked(python, ["-c", script, archive.path, folder.path], timeout: 90)
    }
}
