const path=require('node:path');const fs=require('node:fs/promises');
(async()=>{
 const {packager}=await import('@electron/packager');
 const platform=process.argv[2]||process.platform,arch=process.argv[3]||process.arch;
 if(!['darwin','win32','linux'].includes(platform)||!['x64','arm64'].includes(arch))throw new Error('Use darwin/win32/linux and x64/arm64.');
 const version=require('../package.json').version;
 const output=await packager({dir:path.resolve(__dirname,'..'),out:path.resolve(__dirname,'../../releases/portable'),name:'Shiro-Portable',platform,arch,electronVersion:require('../package.json').devDependencies.electron,appVersion:version,appBundleId:'com.shirobot.portable',overwrite:true,asar:false,prune:true,download:{rejectUnauthorized:true},ignore:[/^\/tests($|\/)/,/^\/scripts($|\/)/,/^\/package-lock\.json$/,/^\/node_modules($|\/)/]});
 for(const folder of output){await fs.writeFile(path.join(folder,'PREVIEW-STATUS.txt'),`Shiro Portable ${version}\nTarget: ${platform} ${arch}\nWindows/Linux packages are unverified previews until tested on those operating systems.\nRequires a local model server; computer tools additionally require Docker.\nSee README.md included with this package.\n`);await fs.copyFile(path.resolve(__dirname,'../README.md'),path.join(folder,'README.md'));console.log(folder);}
})().catch(e=>{console.error(e.message);process.exitCode=1;});
